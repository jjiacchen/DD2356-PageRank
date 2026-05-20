/*
 * pagerank_openmp_gpu.c
 * OpenMP target offload prototype for comparison with CPU paths.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <omp.h>

#define MAX_NODES 100000
#define NAME_LEN 64
#define SHT_SIZE (1 << 17)

typedef struct StrEntry {
    char key[NAME_LEN];
    int val;
    struct StrEntry *next;
} StrEntry;

static StrEntry *sht[SHT_SIZE];
static StrEntry sht_pool[MAX_NODES];
static int sht_used = 0;
static void sht_clear(void) { memset(sht, 0, sizeof(sht)); sht_used = 0; }
static unsigned str_hash(const char *s) {
    unsigned h = 5381;
    while (*s) h = ((h << 5) + h) ^ (unsigned char)*s++;
    return h % SHT_SIZE;
}
static int sht_get_or_insert(const char *key, int *next_id) {
    unsigned h = str_hash(key);
    for (StrEntry *e = sht[h]; e; e = e->next) if (strcmp(e->key, key) == 0) return e->val;
    StrEntry *e = &sht_pool[sht_used++];
    strncpy(e->key, key, NAME_LEN - 1);
    e->key[NAME_LEN - 1] = '\0';
    e->val = (*next_id)++;
    e->next = sht[h];
    sht[h] = e;
    return e->val;
}

typedef struct { int *data; int size; int cap; } IntVec;
static void iv_push(IntVec *v, int x) {
    if (v->size == v->cap) {
        v->cap = v->cap ? v->cap * 2 : 16;
        v->data = realloc(v->data, v->cap * sizeof(int));
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
    if (!fp) { perror(filename); exit(1); }
    sht_clear();
    int next_id = 0;
    IntVec srcs = {0}, dsts = {0};
    char line[512], na[NAME_LEN], nb[NAME_LEN];
    while (fgets(line, sizeof(line), fp)) {
        line[strcspn(line, "\r\n")] = 0;
        if (!line[0]) continue;
        if (!parse_line(line, na, nb)) continue;
        int ia = sht_get_or_insert(na, &next_id);
        int ib = sht_get_or_insert(nb, &next_id);
        iv_push(&srcs, ia); iv_push(&dsts, ib);
        if (!directed) { iv_push(&srcs, ib); iv_push(&dsts, ia); }
    }
    fclose(fp);

    int N = next_id, M = srcs.size;
    CSRGraph *g = malloc(sizeof(CSRGraph));
    g->n_nodes = N; g->n_edges = M;
    g->row_ptr = calloc(N + 1, sizeof(int));
    g->out_degree = calloc(N, sizeof(int));
    g->inv_out_degree = calloc(N, sizeof(double));
    g->col_idx = malloc((M > 0 ? M : 1) * sizeof(int));
    g->names = malloc(N * NAME_LEN);

    for (int s = 0; s < SHT_SIZE; s++) {
        for (StrEntry *e = sht[s]; e; e = e->next) {
            strncpy(g->names[e->val], e->key, NAME_LEN - 1);
            g->names[e->val][NAME_LEN - 1] = '\0';
        }
    }

    int *in_cnt = calloc(N, sizeof(int));
    for (int i = 0; i < M; i++) {
        g->out_degree[srcs.data[i]]++;
        in_cnt[dsts.data[i]]++;
    }
    for (int i = 0; i < N; i++) g->row_ptr[i + 1] = g->row_ptr[i] + in_cnt[i];
    for (int i = 0; i < N; i++) g->inv_out_degree[i] = g->out_degree[i] ? 1.0 / (double) g->out_degree[i] : 0.0;
    int *pos = calloc(N, sizeof(int));
    for (int i = 0; i < M; i++) {
        int d = dsts.data[i];
        g->col_idx[g->row_ptr[d] + pos[d]++] = srcs.data[i];
    }

    free(srcs.data); free(dsts.data); free(in_cnt); free(pos);
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

int main(int argc, char **argv) {
    if (argc < 3) {
        printf("Usage: %s <csv_file> <directed|undirected> [damping=0.85] [tol=1e-10] [max_iter=1000] [output=pagerank_gpu_output.txt]\n", argv[0]);
        return 1;
    }
    const char *filename = argv[1];
    int directed = (strcmp(argv[2], "directed") == 0);
    double damping = (argc > 3) ? atof(argv[3]) : 0.85;
    double tol = (argc > 4) ? atof(argv[4]) : 1e-10;
    int max_iter = (argc > 5) ? atoi(argv[5]) : 1000;
    const char *out_file = (argc > 6) ? argv[6] : "pagerank_gpu_output.txt";

    double t_load0 = omp_get_wtime();
    CSRGraph *g = load_csv(filename, directed);
    double load_t = omp_get_wtime() - t_load0;
    int N = g->n_nodes;

    double *pr = malloc(N * sizeof(double));
    double *pr_new = malloc(N * sizeof(double));
    for (int i = 0; i < N; i++) pr[i] = 1.0 / N;

    double base = (1.0 - damping) / N;
    int iters = 0;

    double t_pr0 = omp_get_wtime();
    for (int iter = 0; iter < max_iter; iter++) {
        double dangling = 0.0;
#pragma omp target teams distribute parallel for map(to:pr[0:N], g->out_degree[0:N]) reduction(+:dangling)
        for (int i = 0; i < N; i++) if (g->out_degree[i] == 0) dangling += pr[i];

        double dang = damping * dangling / N;
#pragma omp target teams distribute parallel for map(to:pr[0:N], g->row_ptr[0:N+1], g->col_idx[0:g->n_edges], g->inv_out_degree[0:N]) map(from:pr_new[0:N])
        for (int v = 0; v < N; v++) {
            double s = 0.0;
            for (int k = g->row_ptr[v]; k < g->row_ptr[v + 1]; k++) {
                int u = g->col_idx[k];
                s += pr[u] * g->inv_out_degree[u];
            }
            pr_new[v] = base + dang + damping * s;
        }

        double diff = 0.0;
#pragma omp parallel for reduction(+:diff)
        for (int i = 0; i < N; i++) diff += fabs(pr_new[i] - pr[i]);

        double *tmp = pr; pr = pr_new; pr_new = tmp;
        iters = iter + 1;
        if (diff < tol) break;
    }
    double pr_t = omp_get_wtime() - t_pr0;

    double sum = 0.0;
    for (int i = 0; i < N; i++) sum += pr[i];
    printf("=== OpenMP Target PageRank ===\n");
    printf("File       : %s\n", filename);
    printf("Mode       : %s\n", directed ? "directed" : "undirected");
    printf("Nodes      : %d\n", N);
    printf("Edges      : %d\n", g->n_edges);
    printf("Load time  : %.6f s\n", load_t);
    printf("Iterations : %d\n", iters);
    printf("PR time    : %.6f s\n", pr_t);
    printf("Total time : %.6f s\n", load_t + pr_t);
    printf("PR sum     : %.10f\n", sum);

    FILE *fp = fopen(out_file, "w");
    if (fp) {
        for (int i = 0; i < N; i++) fprintf(fp, "%s %.15e\n", g->names[i], pr[i]);
        fclose(fp);
        printf("Results saved: %s\n", out_file);
    }

    free(pr);
    free(pr_new);
    free_graph(g);
    return 0;
}
