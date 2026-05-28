/*
 * pagerank_mpi.c
 * MPI PageRank with destination-node block decomposition.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <mpi.h>

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
    while (*s) h = ((h << 5) + h) ^ (unsigned char)*s++;
    return h % SHT_SIZE;
}
static int sht_get_or_insert(const char *key, int *next_id) {
    unsigned h = str_hash(key);
    for (StrEntry *e = sht[h]; e; e = e->next) if (strcmp(e->key, key) == 0) return e->val;
    StrEntry *e = xmalloc(sizeof(*e));
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
        v->data = xrealloc(v->data, (size_t)v->cap * sizeof(int));
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
    double dangling_reduce;
    double diff_reduce;
    double allgatherv;
} MpiTiming;

typedef struct {
    int idx;
    double val;
} RankPair;

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

static CSRGraph *load_csv_root(const char *filename, int directed) {
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

    int N = next_id;
    int M = srcs.size;
    CSRGraph *g = xmalloc(sizeof(CSRGraph));
    g->n_nodes = N;
    g->n_edges = M;
    g->row_ptr = xcalloc((size_t)N + 1, sizeof(int));
    g->out_degree = xcalloc((size_t)N, sizeof(int));
    g->inv_out_degree = xcalloc((size_t)N, sizeof(double));
    g->col_idx = xmalloc((size_t)(M > 0 ? M : 1) * sizeof(int));
    g->names = xmalloc((size_t)N * sizeof(*g->names));

    for (int s = 0; s < SHT_SIZE; s++) {
        for (StrEntry *e = sht[s]; e; e = e->next) {
            strncpy(g->names[e->val], e->key, NAME_LEN - 1);
            g->names[e->val][NAME_LEN - 1] = '\0';
        }
    }

    int *in_cnt = xcalloc((size_t)N, sizeof(int));
    for (int i = 0; i < M; i++) {
        g->out_degree[srcs.data[i]]++;
        in_cnt[dsts.data[i]]++;
    }
    for (int i = 0; i < N; i++) g->row_ptr[i + 1] = g->row_ptr[i] + in_cnt[i];
    for (int i = 0; i < N; i++) g->inv_out_degree[i] = g->out_degree[i] ? 1.0 / (double) g->out_degree[i] : 0.0;

    int *pos = xcalloc((size_t)N, sizeof(int));
    for (int i = 0; i < M; i++) {
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

static void broadcast_graph(CSRGraph **g_ptr, int rank, MPI_Comm comm) {
    CSRGraph *g = *g_ptr;
    int N, M;
    if (rank == 0) { N = g->n_nodes; M = g->n_edges; }
    MPI_Bcast(&N, 1, MPI_INT, 0, comm);
    MPI_Bcast(&M, 1, MPI_INT, 0, comm);
    if (rank != 0) {
        g = xmalloc(sizeof(CSRGraph));
        g->n_nodes = N;
        g->n_edges = M;
        g->row_ptr = xmalloc(((size_t)N + 1) * sizeof(int));
        g->out_degree = xmalloc((size_t)N * sizeof(int));
        g->inv_out_degree = xmalloc((size_t)N * sizeof(double));
        g->col_idx = xmalloc((size_t)(M > 0 ? M : 1) * sizeof(int));
        g->names = xmalloc((size_t)N * sizeof(*g->names));
    }
    MPI_Bcast(g->row_ptr, N + 1, MPI_INT, 0, comm);
    MPI_Bcast(g->out_degree, N, MPI_INT, 0, comm);
    MPI_Bcast(g->inv_out_degree, N, MPI_DOUBLE, 0, comm);
    MPI_Bcast(g->col_idx, M, MPI_INT, 0, comm);
    MPI_Bcast(g->names, N * NAME_LEN, MPI_CHAR, 0, comm);
    *g_ptr = g;
}

static void free_graph(CSRGraph *g) {
    free(g->row_ptr);
    free(g->col_idx);
    free(g->out_degree);
    free(g->inv_out_degree);
    free(g->names);
    free(g);
}

static void owner_range(int N, int size, int rank, int *begin, int *end) {
    int q = N / size, r = N % size;
    *begin = rank * q + (rank < r ? rank : r);
    *end = *begin + q + (rank < r ? 1 : 0);
}

static void make_counts_displs(int N, int size, int *counts, int *displs) {
    for (int r = 0; r < size; r++) {
        int b, e;
        owner_range(N, size, r, &b, &e);
        counts[r] = e - b;
        displs[r] = b;
    }
}

static int rank_pair_desc(const void *a, const void *b) {
    const RankPair *ra = (const RankPair *) a;
    const RankPair *rb = (const RankPair *) b;
    return (ra->val < rb->val) - (ra->val > rb->val);
}

static void print_top_k(const CSRGraph *g, const double *pr, int k) {
    if (k > g->n_nodes) k = g->n_nodes;
    RankPair *pairs = malloc((size_t)g->n_nodes * sizeof(RankPair));
    if (!pairs) return;
    for (int i = 0; i < g->n_nodes; i++) {
        pairs[i].idx = i;
        pairs[i].val = pr[i];
    }
    qsort(pairs, g->n_nodes, sizeof(RankPair), rank_pair_desc);

    printf("\nTop-%d nodes:\n", k);
    printf("  %-6s  %-20s  %s\n", "Rank", "Node", "PageRank");
    printf("  ------  --------------------  --------------------\n");
    for (int i = 0; i < k; i++) {
        int idx = pairs[i].idx;
        printf("  %-6d  %-20s  %.10f\n", i + 1, g->names[idx], pr[idx]);
    }
    free(pairs);
}

static void save_results(const char *out_file, const CSRGraph *g, const double *pr) {
    FILE *fp = fopen(out_file, "w");
    if (!fp) {
        perror(out_file);
        return;
    }
    for (int i = 0; i < g->n_nodes; i++) {
        fprintf(fp, "%s %.15e\n", g->names[i], pr[i]);
    }
    fclose(fp);
    printf("Results saved: %s\n", out_file);
}

int main(int argc, char **argv) {
    MPI_Init(&argc, &argv);
    int rank, size;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);

    if (argc < 3) {
        if (rank == 0) {
            printf("Usage: %s <csv_file> <directed|undirected> [damping=0.85] [tol=1e-10] [max_iter=1000] [output=pagerank_mpi_output.txt]\n", argv[0]);
        }
        MPI_Finalize();
        return 1;
    }

    const char *filename = argv[1];
    int directed = (strcmp(argv[2], "directed") == 0);
    double damping = (argc > 3) ? atof(argv[3]) : 0.85;
    double tol = (argc > 4) ? atof(argv[4]) : 1e-10;
    int max_iter = (argc > 5) ? atoi(argv[5]) : 1000;
    const char *out_file = (argc > 6) ? argv[6] : "pagerank_mpi_output.txt";

    if (rank == 0) {
        printf("=== DD2356 MPI PageRank ===\n");
        printf("File      : %s\n", filename);
        printf("Mode      : %s\n", directed ? "directed" : "undirected");
        printf("MPI ranks : %d\n", size);
        printf("Damping   : %.4f\n", damping);
        printf("Tolerance : %.2e\n", tol);
        printf("Max iter  : %d\n\n", max_iter);
    }

    CSRGraph *g = NULL;

    MPI_Barrier(MPI_COMM_WORLD);
    double t_load0 = MPI_Wtime();
    if (rank == 0) g = load_csv_root(filename, directed);
    broadcast_graph(&g, rank, MPI_COMM_WORLD);
    double local_load_t = MPI_Wtime() - t_load0;
    double load_t = 0.0;
    MPI_Reduce(&local_load_t, &load_t, 1, MPI_DOUBLE, MPI_MAX, 0, MPI_COMM_WORLD);

    int N = g->n_nodes;
    int begin, end;
    owner_range(N, size, rank, &begin, &end);
    int local_nodes = end - begin;
    int local_inedges = g->row_ptr[end] - g->row_ptr[begin];

    int min_nodes = 0, max_nodes = 0, sum_nodes = 0;
    int min_inedges = 0, max_inedges = 0, sum_inedges = 0;
    MPI_Reduce(&local_nodes, &min_nodes, 1, MPI_INT, MPI_MIN, 0, MPI_COMM_WORLD);
    MPI_Reduce(&local_nodes, &max_nodes, 1, MPI_INT, MPI_MAX, 0, MPI_COMM_WORLD);
    MPI_Reduce(&local_nodes, &sum_nodes, 1, MPI_INT, MPI_SUM, 0, MPI_COMM_WORLD);
    MPI_Reduce(&local_inedges, &min_inedges, 1, MPI_INT, MPI_MIN, 0, MPI_COMM_WORLD);
    MPI_Reduce(&local_inedges, &max_inedges, 1, MPI_INT, MPI_MAX, 0, MPI_COMM_WORLD);
    MPI_Reduce(&local_inedges, &sum_inedges, 1, MPI_INT, MPI_SUM, 0, MPI_COMM_WORLD);

    if (rank == 0) {
        double avg_nodes = sum_nodes / (double) size;
        double avg_inedges = sum_inedges / (double) size;
        double imbalance = avg_inedges > 0.0 ? max_inedges / avg_inedges : 0.0;

        printf("Nodes     : %d\n", g->n_nodes);
        printf("Edges     : %d\n", g->n_edges);
        printf("Load time : %.4f s  (rank-0 load + broadcast, max rank)\n", load_t);
        printf("Block     : contiguous node ranges; rank 0 owns [%d, %d)\n\n",
               begin, end);
        printf("Work nodes : min=%d avg=%.2f max=%d\n",
               min_nodes, avg_nodes, max_nodes);
        printf("Work inedges : min=%d avg=%.2f max=%d imbalance=%.3f\n\n",
               min_inedges, avg_inedges, max_inedges, imbalance);
    }

    double *pr = malloc((size_t)N * sizeof(double));
    double *pr_new = malloc((size_t)N * sizeof(double));
    int *recvcounts = malloc((size_t)size * sizeof(int));
    int *displs = malloc((size_t)size * sizeof(int));
    if (!pr || !pr_new || !recvcounts || !displs) {
        fprintf(stderr, "Rank %d: allocation failed\n", rank);
        MPI_Abort(MPI_COMM_WORLD, 2);
    }
    make_counts_displs(N, size, recvcounts, displs);

    for (int i = 0; i < N; i++) pr[i] = 1.0 / N;

    double base = (1.0 - damping) / N;
    int iters = 0;
    MpiTiming timing = {0.0, 0.0, 0.0};
    MPI_Barrier(MPI_COMM_WORLD);
    double t0 = MPI_Wtime();
    for (int iter = 0; iter < max_iter; iter++) {
        double dangling_local = 0.0;
        for (int i = begin; i < end; i++) if (g->out_degree[i] == 0) dangling_local += pr[i];
        double dangling = 0.0;

        double tc = MPI_Wtime();
        MPI_Allreduce(&dangling_local, &dangling, 1, MPI_DOUBLE, MPI_SUM, MPI_COMM_WORLD);
        timing.dangling_reduce += MPI_Wtime() - tc;
        double dang = damping * dangling / N;

        for (int v = begin; v < end; v++) {
            double s = 0.0;
            for (int k = g->row_ptr[v]; k < g->row_ptr[v + 1]; k++) {
                int u = g->col_idx[k];
                s += pr[u] * g->inv_out_degree[u];
            }
            pr_new[v] = base + dang + damping * s;
        }

        double diff_local = 0.0;
        for (int i = begin; i < end; i++) diff_local += fabs(pr_new[i] - pr[i]);
        double diff = 0.0;

        tc = MPI_Wtime();
        MPI_Allreduce(&diff_local, &diff, 1, MPI_DOUBLE, MPI_SUM, MPI_COMM_WORLD);
        timing.diff_reduce += MPI_Wtime() - tc;

        tc = MPI_Wtime();
        MPI_Allgatherv(pr_new + begin, end - begin, MPI_DOUBLE,
                       pr, recvcounts, displs, MPI_DOUBLE, MPI_COMM_WORLD);
        timing.allgatherv += MPI_Wtime() - tc;

        iters = iter + 1;
        if (diff < tol) break;
    }
    double local_pr_t = MPI_Wtime() - t0;
    double local_comm_t = timing.dangling_reduce + timing.diff_reduce + timing.allgatherv;

    double pr_t = 0.0, comm_t = 0.0, dangling_t = 0.0, diff_t = 0.0, allgatherv_t = 0.0;
    MPI_Reduce(&local_pr_t, &pr_t, 1, MPI_DOUBLE, MPI_MAX, 0, MPI_COMM_WORLD);
    MPI_Reduce(&local_comm_t, &comm_t, 1, MPI_DOUBLE, MPI_MAX, 0, MPI_COMM_WORLD);
    MPI_Reduce(&timing.dangling_reduce, &dangling_t, 1, MPI_DOUBLE, MPI_MAX, 0, MPI_COMM_WORLD);
    MPI_Reduce(&timing.diff_reduce, &diff_t, 1, MPI_DOUBLE, MPI_MAX, 0, MPI_COMM_WORLD);
    MPI_Reduce(&timing.allgatherv, &allgatherv_t, 1, MPI_DOUBLE, MPI_MAX, 0, MPI_COMM_WORLD);

    double sum = 0.0;
    for (int i = 0; i < N; i++) sum += pr[i];
    double min_sum = 0.0, max_sum = 0.0;
    MPI_Reduce(&sum, &min_sum, 1, MPI_DOUBLE, MPI_MIN, 0, MPI_COMM_WORLD);
    MPI_Reduce(&sum, &max_sum, 1, MPI_DOUBLE, MPI_MAX, 0, MPI_COMM_WORLD);

    if (rank == 0) {
        printf("Iterations : %d\n", iters);
        printf("PR time    : %.6f s  (max across ranks)\n", pr_t);
        printf("Comm time  : %.6f s  (Allreduce + Allgatherv, max rank)\n", comm_t);
        printf("Dangling reduce time : %.6f s  (max rank)\n", dangling_t);
        printf("Diff reduce time     : %.6f s  (max rank)\n", diff_t);
        printf("Allgatherv time      : %.6f s  (max rank)\n", allgatherv_t);
        printf("Total time : %.6f s  (load + PR)\n", load_t + pr_t);
        printf("PR sum     : %.10f  (range across ranks: %.10f..%.10f)\n",
               sum, min_sum, max_sum);
        print_top_k(g, pr, 10);
        save_results(out_file, g, pr);
    }

    free(pr);
    free(pr_new);
    free(recvcounts);
    free(displs);
    free_graph(g);
    MPI_Finalize();
    return 0;
}
