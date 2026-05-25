/*
 * pagerank_openmp_gpu.c
 * OpenMP target PageRank with a mapping baseline and a persistent-data path.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <omp.h>

#define NAME_LEN 64
#define SHT_SIZE (1 << 17)

typedef struct StrEntry {
    char key[NAME_LEN];
    int val;
    struct StrEntry *next;
} StrEntry;

static StrEntry *sht[SHT_SIZE];

static void die_alloc(const char *what) {
    fprintf(stderr, "allocation failed: %s\n", what);
    exit(1);
}

static void *xmalloc(size_t n) {
    void *p = malloc(n);
    if (!p) die_alloc("malloc");
    return p;
}

static void *xcalloc(size_t count, size_t size) {
    void *p = calloc(count, size);
    if (!p) die_alloc("calloc");
    return p;
}

static void *xrealloc(void *ptr, size_t n) {
    void *p = realloc(ptr, n);
    if (!p) die_alloc("realloc");
    return p;
}

static void sht_clear(void) {
    for (int i = 0; i < SHT_SIZE; i++) {
        StrEntry *e = sht[i];
        while (e) {
            StrEntry *next = e->next;
            free(e);
            e = next;
        }
        sht[i] = NULL;
    }
}

static unsigned str_hash(const char *s) {
    unsigned h = 5381;
    while (*s) h = ((h << 5) + h) ^ (unsigned char) *s++;
    return h % SHT_SIZE;
}

static int sht_get_or_insert(const char *key, int *next_id) {
    unsigned h = str_hash(key);
    for (StrEntry *e = sht[h]; e; e = e->next) {
        if (strcmp(e->key, key) == 0) return e->val;
    }
    StrEntry *e = xmalloc(sizeof(*e));
    snprintf(e->key, NAME_LEN, "%s", key);
    e->val = (*next_id)++;
    e->next = sht[h];
    sht[h] = e;
    return e->val;
}

typedef struct {
    int *data;
    int size;
    int cap;
} IntVec;

static void iv_push(IntVec *v, int x) {
    if (v->size == v->cap) {
        v->cap = v->cap ? v->cap * 2 : 16;
        v->data = xrealloc(v->data, (size_t) v->cap * sizeof(int));
    }
    v->data[v->size++] = x;
}

typedef struct {
    int n_nodes, n_edges;
    int *row_ptr;
    int *col_idx;
    int *out_degree;
    double *inv_out_degree;
    char (*names)[NAME_LEN];
} CSRGraph;

typedef struct {
    int iterations;
    double setup_time;
    double kernel_time;
    double teardown_time;
    double pr_time;
} GpuTiming;

static int parse_line(const char *line, char *na, char *nb) {
    const char *p = line;
    if (*p == '"') {
        p++;
        char *q = na;
        while (*p && *p != '"') *q++ = *p++;
        *q = 0;
        if (*p == '"') p++;
    } else {
        char *q = na;
        while (*p && *p != ',') *q++ = *p++;
        *q = 0;
    }
    if (*p != ',') return 0;
    p++;
    while (*p && *p != ',') p++;
    if (*p != ',') return 0;
    p++;
    if (*p == '"') {
        p++;
        char *q = nb;
        while (*p && *p != '"') *q++ = *p++;
        *q = 0;
    } else {
        char *q = nb;
        while (*p && *p != ',') *q++ = *p++;
        *q = 0;
    }
    return na[0] && nb[0];
}

static CSRGraph *load_csv(const char *filename, int directed) {
    FILE *fp = fopen(filename, "r");
    if (!fp) {
        perror(filename);
        exit(1);
    }
    sht_clear();
    int next_id = 0;
    IntVec srcs = {0}, dsts = {0};
    char line[512], na[NAME_LEN], nb[NAME_LEN];
    while (fgets(line, sizeof(line), fp)) {
        line[strcspn(line, "\r\n")] = 0;
        if (!line[0] || !parse_line(line, na, nb)) continue;
        int ia = sht_get_or_insert(na, &next_id);
        int ib = sht_get_or_insert(nb, &next_id);
        iv_push(&srcs, ia);
        iv_push(&dsts, ib);
        if (!directed) {
            iv_push(&srcs, ib);
            iv_push(&dsts, ia);
        }
    }
    fclose(fp);

    int n = next_id;
    int m = srcs.size;
    CSRGraph *g = xmalloc(sizeof(*g));
    g->n_nodes = n;
    g->n_edges = m;
    g->row_ptr = xcalloc((size_t) n + 1, sizeof(int));
    g->out_degree = xcalloc((size_t) (n ? n : 1), sizeof(int));
    g->inv_out_degree = xcalloc((size_t) (n ? n : 1), sizeof(double));
    g->col_idx = xmalloc((size_t) (m ? m : 1) * sizeof(int));
    g->names = xmalloc((size_t) (n ? n : 1) * NAME_LEN);

    for (int s = 0; s < SHT_SIZE; s++) {
        for (StrEntry *e = sht[s]; e; e = e->next) {
            snprintf(g->names[e->val], NAME_LEN, "%s", e->key);
        }
    }

    int *in_cnt = xcalloc((size_t) (n ? n : 1), sizeof(int));
    for (int i = 0; i < m; i++) {
        g->out_degree[srcs.data[i]]++;
        in_cnt[dsts.data[i]]++;
    }
    for (int i = 0; i < n; i++) {
        g->row_ptr[i + 1] = g->row_ptr[i] + in_cnt[i];
        g->inv_out_degree[i] =
            g->out_degree[i] ? 1.0 / (double) g->out_degree[i] : 0.0;
    }
    int *pos = xcalloc((size_t) (n ? n : 1), sizeof(int));
    for (int i = 0; i < m; i++) {
        int d = dsts.data[i];
        g->col_idx[g->row_ptr[d] + pos[d]++] = srcs.data[i];
    }

    free(srcs.data);
    free(dsts.data);
    free(in_cnt);
    free(pos);
    sht_clear();
    return g;
}

static void free_graph(CSRGraph *g) {
    free(g->row_ptr);
    free(g->col_idx);
    free(g->out_degree);
    free(g->inv_out_degree);
    free(g->names);
    free(g);
}

static int target_probe(int *device_id) {
    int is_initial = 1;
    int used_device = -1;
#pragma omp target map(from:is_initial, used_device)
    {
        is_initial = omp_is_initial_device();
        used_device = omp_get_device_num();
    }
    *device_id = used_device;
    return !is_initial;
}

static double *pagerank_naive(const CSRGraph *g, double damping, double tol,
                              int max_iter, double *pr_a, double *pr_b,
                              GpuTiming *timing) {
    int n = g->n_nodes;
    int m = g->n_edges;
    int *row_ptr = g->row_ptr;
    int *col_idx = g->col_idx;
    int *out_degree = g->out_degree;
    double *inv_out_degree = g->inv_out_degree;
    double *pr = pr_a;
    double *pr_new = pr_b;
    double base = (1.0 - damping) / n;

    for (int i = 0; i < n; i++) pr[i] = 1.0 / n;
    timing->setup_time = 0.0;
    timing->teardown_time = 0.0;
    double t0 = omp_get_wtime();
    for (int iter = 0; iter < max_iter; iter++) {
        double dangling = 0.0;
#pragma omp target teams distribute parallel for map(to:pr[0:n], out_degree[0:n]) reduction(+:dangling)
        for (int i = 0; i < n; i++) {
            if (out_degree[i] == 0) dangling += pr[i];
        }

        double dang = damping * dangling / n;
#pragma omp target teams distribute parallel for map(to:pr[0:n], row_ptr[0:n+1], col_idx[0:m], inv_out_degree[0:n]) map(from:pr_new[0:n])
        for (int v = 0; v < n; v++) {
            double s = 0.0;
            for (int k = row_ptr[v]; k < row_ptr[v + 1]; k++) {
                int u = col_idx[k];
                s += pr[u] * inv_out_degree[u];
            }
            pr_new[v] = base + dang + damping * s;
        }

        double diff = 0.0;
#pragma omp target teams distribute parallel for map(to:pr[0:n], pr_new[0:n]) reduction(+:diff)
        for (int i = 0; i < n; i++) diff += fabs(pr_new[i] - pr[i]);

        double *tmp = pr;
        pr = pr_new;
        pr_new = tmp;
        timing->iterations = iter + 1;
        if (diff < tol) break;
    }
    timing->kernel_time = omp_get_wtime() - t0;
    timing->pr_time = timing->kernel_time;
    return pr;
}

static double *pagerank_persistent(const CSRGraph *g, double damping, double tol,
                                   int max_iter, double *pr_a, double *pr_b,
                                   GpuTiming *timing) {
    int n = g->n_nodes;
    int m = g->n_edges;
    int *row_ptr = g->row_ptr;
    int *col_idx = g->col_idx;
    int *out_degree = g->out_degree;
    double *inv_out_degree = g->inv_out_degree;
    double base = (1.0 - damping) / n;
    int use_a = 1;
    double teardown_start = 0.0;

    for (int i = 0; i < n; i++) pr_a[i] = 1.0 / n;
    double pr_start = omp_get_wtime();
    double setup_start = omp_get_wtime();
#pragma omp target data map(to:row_ptr[0:n+1], col_idx[0:m], out_degree[0:n], inv_out_degree[0:n]) map(tofrom:pr_a[0:n]) map(alloc:pr_b[0:n])
    {
        timing->setup_time = omp_get_wtime() - setup_start;
        double kernel_start = omp_get_wtime();
        for (int iter = 0; iter < max_iter; iter++) {
            double dangling = 0.0;
            double diff = 0.0;
            if (use_a) {
#pragma omp target teams distribute parallel for reduction(+:dangling)
                for (int i = 0; i < n; i++) {
                    if (out_degree[i] == 0) dangling += pr_a[i];
                }
                double dang = damping * dangling / n;
#pragma omp target teams distribute parallel for
                for (int v = 0; v < n; v++) {
                    double s = 0.0;
                    for (int k = row_ptr[v]; k < row_ptr[v + 1]; k++) {
                        int u = col_idx[k];
                        s += pr_a[u] * inv_out_degree[u];
                    }
                    pr_b[v] = base + dang + damping * s;
                }
#pragma omp target teams distribute parallel for reduction(+:diff)
                for (int i = 0; i < n; i++) diff += fabs(pr_b[i] - pr_a[i]);
            } else {
#pragma omp target teams distribute parallel for reduction(+:dangling)
                for (int i = 0; i < n; i++) {
                    if (out_degree[i] == 0) dangling += pr_b[i];
                }
                double dang = damping * dangling / n;
#pragma omp target teams distribute parallel for
                for (int v = 0; v < n; v++) {
                    double s = 0.0;
                    for (int k = row_ptr[v]; k < row_ptr[v + 1]; k++) {
                        int u = col_idx[k];
                        s += pr_b[u] * inv_out_degree[u];
                    }
                    pr_a[v] = base + dang + damping * s;
                }
#pragma omp target teams distribute parallel for reduction(+:diff)
                for (int i = 0; i < n; i++) diff += fabs(pr_a[i] - pr_b[i]);
            }
            use_a = !use_a;
            timing->iterations = iter + 1;
            if (diff < tol) break;
        }
        timing->kernel_time = omp_get_wtime() - kernel_start;
        teardown_start = omp_get_wtime();
        if (!use_a) {
#pragma omp target update from(pr_b[0:n])
        }
    }
    timing->teardown_time = omp_get_wtime() - teardown_start;
    timing->pr_time = omp_get_wtime() - pr_start;
    return use_a ? pr_a : pr_b;
}

int main(int argc, char **argv) {
    if (argc < 3) {
        printf("Usage: %s <csv_file> <directed|undirected> [damping=0.85] [tol=1e-10] [max_iter=1000] [output=pagerank_gpu_output.txt] [persistent|naive]\n",
               argv[0]);
        return 1;
    }
    const char *filename = argv[1];
    int directed = (strcmp(argv[2], "directed") == 0);
    double damping = (argc > 3) ? atof(argv[3]) : 0.85;
    double tol = (argc > 4) ? atof(argv[4]) : 1e-10;
    int max_iter = (argc > 5) ? atoi(argv[5]) : 1000;
    const char *out_file = (argc > 6) ? argv[6] : "pagerank_gpu_output.txt";
    const char *variant = (argc > 7) ? argv[7] : "persistent";
    if (strcmp(variant, "naive") != 0 && strcmp(variant, "persistent") != 0) {
        fprintf(stderr, "Unknown GPU variant '%s' (expected naive or persistent)\n",
                variant);
        return 1;
    }

    int device_id = -1;
    int target_devices = omp_get_num_devices();
    int device_verified = target_probe(&device_id);
    const char *require_device = getenv("PR_REQUIRE_DEVICE");
    if (require_device && atoi(require_device) != 0 && !device_verified) {
        fprintf(stderr,
                "GPU target execution required, but target region ran on the initial device.\n");
        fprintf(stderr, "Target devices : %d\n", target_devices);
        fprintf(stderr, "Target executed on device: NO\n");
        return 2;
    }

    double t_load0 = omp_get_wtime();
    CSRGraph *g = load_csv(filename, directed);
    double load_t = omp_get_wtime() - t_load0;
    int n = g->n_nodes;
    if (n == 0) {
        fprintf(stderr, "Input graph has no nodes.\n");
        free_graph(g);
        return 1;
    }

    double *pr_a = xmalloc((size_t) n * sizeof(double));
    double *pr_b = xmalloc((size_t) n * sizeof(double));
    GpuTiming timing = {0, 0.0, 0.0, 0.0, 0.0};
    double *pr = NULL;
    if (strcmp(variant, "naive") == 0) {
        pr = pagerank_naive(g, damping, tol, max_iter, pr_a, pr_b, &timing);
    } else {
        pr = pagerank_persistent(g, damping, tol, max_iter, pr_a, pr_b, &timing);
    }

    double sum = 0.0;
    for (int i = 0; i < n; i++) sum += pr[i];
    printf("=== OpenMP Target PageRank ===\n");
    printf("File       : %s\n", filename);
    printf("Mode       : %s\n", directed ? "directed" : "undirected");
    printf("GPU variant: %s\n", variant);
    printf("Nodes      : %d\n", n);
    printf("Edges      : %d\n", g->n_edges);
    printf("Target devices : %d\n", target_devices);
    printf("Target device id : %d\n", device_id);
    printf("Target executed on device: %s\n", device_verified ? "YES" : "NO");
    printf("Device verified : %s\n", device_verified ? "YES" : "NO");
    printf("Load time  : %.6f s\n", load_t);
    printf("Iterations : %d\n", timing.iterations);
    printf("Target setup time : %.6f s\n", timing.setup_time);
    printf("Iteration/kernel time : %.6f s\n", timing.kernel_time);
    printf("Target teardown time : %.6f s\n", timing.teardown_time);
    printf("PR time    : %.6f s\n", timing.pr_time);
    printf("Total time : %.6f s\n", load_t + timing.pr_time);
    printf("PR sum     : %.10f\n", sum);

    FILE *fp = fopen(out_file, "w");
    if (!fp) {
        perror(out_file);
    } else {
        for (int i = 0; i < n; i++) {
            fprintf(fp, "%s %.15e\n", g->names[i], pr[i]);
        }
        fclose(fp);
        printf("Results saved: %s\n", out_file);
    }

    free(pr_a);
    free(pr_b);
    free_graph(g);
    return 0;
}
