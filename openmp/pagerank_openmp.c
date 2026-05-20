/*
 * pagerank_openmp.c
 * OpenMP implementation aligned with serial baseline.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>
#include <omp.h>

#define MAX_NODES 100000
#define NAME_LEN  64
#define SHT_SIZE (1 << 17)

typedef struct StrEntry {
    char key[NAME_LEN];
    int  val;
    struct StrEntry *next;
} StrEntry;

static StrEntry *sht[SHT_SIZE];
static StrEntry  sht_pool[MAX_NODES];
static int       sht_used = 0;

static void sht_clear(void) { memset(sht, 0, sizeof(sht)); sht_used = 0; }

static unsigned str_hash(const char *s) {
    unsigned h = 5381;
    while (*s) h = ((h << 5) + h) ^ (unsigned char)*s++;
    return h % SHT_SIZE;
}

static int sht_get_or_insert(const char *key, int *next_id) {
    unsigned h = str_hash(key);
    for (StrEntry *e = sht[h]; e; e = e->next)
        if (strcmp(e->key, key) == 0) return e->val;
    StrEntry *e = &sht_pool[sht_used++];
    strncpy(e->key, key, NAME_LEN - 1);
    e->key[NAME_LEN - 1] = '\0';
    e->val = (*next_id)++;
    e->next = sht[h];
    sht[h] = e;
    return e->val;
}

typedef struct {
    char (*names)[NAME_LEN];
    int n;
} NodeMap;

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

static CSRGraph *load_csv(const char *filename, int directed, NodeMap *nm) {
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
        iv_push(&srcs, ia);
        iv_push(&dsts, ib);
        if (!directed) {
            iv_push(&srcs, ib);
            iv_push(&dsts, ia);
        }
    }
    fclose(fp);

    int N = next_id, M = srcs.size;
    nm->names = malloc(N * NAME_LEN);
    nm->n = N;

    for (int s = 0; s < SHT_SIZE; s++) {
        for (StrEntry *e = sht[s]; e; e = e->next) {
            strncpy(nm->names[e->val], e->key, NAME_LEN - 1);
            nm->names[e->val][NAME_LEN - 1] = '\0';
        }
    }

    CSRGraph *g = malloc(sizeof(CSRGraph));
    g->n_nodes = N;
    g->n_edges = M;
    g->out_degree = calloc(N, sizeof(int));
    g->inv_out_degree = calloc(N, sizeof(double));
    g->row_ptr = calloc(N + 1, sizeof(int));
    g->col_idx = malloc((M > 0 ? M : 1) * sizeof(int));

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

    free(srcs.data);
    free(dsts.data);
    free(in_cnt);
    free(pos);
    return g;
}

static void free_graph(CSRGraph *g) {
    free(g->row_ptr);
    free(g->col_idx);
    free(g->out_degree);
    free(g->inv_out_degree);
    free(g);
}

static double *pagerank_openmp(const CSRGraph *g,
                               double damping, double tol, int max_iter,
                               int *iters_out)
{
    int N = g->n_nodes;
    double *pr = malloc(N * sizeof(double));
    double *pr_new = malloc(N * sizeof(double));
    for (int i = 0; i < N; i++) pr[i] = 1.0 / N;

    const double base = (1.0 - damping) / N;
    int iter = 0;
    for (iter = 0; iter < max_iter; iter++) {
        double dangling = 0.0;
#pragma omp parallel for reduction(+:dangling) schedule(static)
        for (int i = 0; i < N; i++) {
            if (g->out_degree[i] == 0) dangling += pr[i];
        }
        const double dang = damping * dangling / N;

#pragma omp parallel for schedule(dynamic, 256)
        for (int v = 0; v < N; v++) {
            double s = 0.0;
            for (int k = g->row_ptr[v]; k < g->row_ptr[v + 1]; k++) {
                int u = g->col_idx[k];
                s += pr[u] * g->inv_out_degree[u];
            }
            pr_new[v] = base + dang + damping * s;
        }

        double diff = 0.0;
#pragma omp parallel for reduction(+:diff) schedule(static)
        for (int i = 0; i < N; i++) diff += fabs(pr_new[i] - pr[i]);

        double *tmp = pr; pr = pr_new; pr_new = tmp;
        if (diff < tol) { iter++; break; }
    }
    free(pr_new);
    *iters_out = iter;
    return pr;
}

typedef struct { int idx; double val; } RankPair;
static int rp_cmp(const void *a, const void *b) {
    double da = ((const RankPair *)a)->val;
    double db = ((const RankPair *)b)->val;
    return (da < db) - (da > db);
}

static void print_top_k(const double *pr, const NodeMap *nm, int K) {
    int N = nm->n;
    if (K > N) K = N;
    RankPair *rp = malloc(N * sizeof(RankPair));
    for (int i = 0; i < N; i++) { rp[i].idx = i; rp[i].val = pr[i]; }
    qsort(rp, N, sizeof(RankPair), rp_cmp);
    printf("\nTop-%d nodes:\n", K);
    printf("  %-6s  %-20s  %s\n", "Rank", "Node", "PageRank");
    printf("  ------  --------------------  --------------------\n");
    for (int i = 0; i < K; i++) {
        printf("  %-6d  %-20s  %.10f\n", i + 1, nm->names[rp[i].idx], rp[i].val);
    }
    free(rp);
}

static void save_results(const char *out_file, const double *pr, const NodeMap *nm) {
    FILE *fp = fopen(out_file, "w");
    if (!fp) { perror("save_results"); return; }
    for (int i = 0; i < nm->n; i++) fprintf(fp, "%s %.15e\n", nm->names[i], pr[i]);
    fclose(fp);
    printf("Results saved: %s\n", out_file);
}

int main(int argc, char *argv[]) {
    if (argc < 3) {
        printf("Usage: %s <csv_file> <directed|undirected> [threads=8] [damping=0.85] [tol=1e-10] [max_iter=1000]\n", argv[0]);
        return 1;
    }

    const char *filename = argv[1];
    int directed = (strcmp(argv[2], "directed") == 0);
    int threads = (argc > 3) ? atoi(argv[3]) : 8;
    double damping = (argc > 4) ? atof(argv[4]) : 0.85;
    double tol = (argc > 5) ? atof(argv[5]) : 1e-10;
    int max_iter = (argc > 6) ? atoi(argv[6]) : 1000;

    omp_set_num_threads(threads);

    printf("=== OpenMP PageRank ===\n");
    printf("File      : %s\n", filename);
    printf("Mode      : %s\n", directed ? "directed" : "undirected");
    printf("Threads   : %d\n", threads);
    printf("Damping   : %.4f\n", damping);
    printf("Tolerance : %.2e\n", tol);
    printf("Max iter  : %d\n\n", max_iter);

    struct timespec t0, t1;
    NodeMap nm = {0};
    clock_gettime(CLOCK_MONOTONIC, &t0);
    CSRGraph *g = load_csv(filename, directed, &nm);
    clock_gettime(CLOCK_MONOTONIC, &t1);
    double load_t = (t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) * 1e-9;

    printf("Nodes     : %d\n", g->n_nodes);
    printf("Edges     : %d\n", g->n_edges);
    printf("Load time : %.4f s\n\n", load_t);

    int iters = 0;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    double *pr = pagerank_openmp(g, damping, tol, max_iter, &iters);
    clock_gettime(CLOCK_MONOTONIC, &t1);
    double pr_t = (t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) * 1e-9;

    double sum = 0.0;
    for (int i = 0; i < g->n_nodes; i++) sum += pr[i];
    printf("Iterations : %d\n", iters);
    printf("PR time    : %.6f s\n", pr_t);
    printf("PR sum     : %.10f  (should be ~1.0)\n", sum);

    print_top_k(pr, &nm, 10);
    save_results("pagerank_openmp_output.txt", pr, &nm);

    free(pr);
    free(nm.names);
    free_graph(g);
    return 0;
}
