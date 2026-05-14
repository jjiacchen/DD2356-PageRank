/*
 * pagerank_mpi.c
 * MPI PageRank with edge partitioning by destination node range.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <mpi.h>

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
    CSRGraph *g = malloc(sizeof(CSRGraph));
    g->n_nodes = N;
    g->n_edges = M;
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

    free(srcs.data);
    free(dsts.data);
    free(in_cnt);
    free(pos);
    return g;
}

static void broadcast_graph(CSRGraph **g_ptr, int rank, MPI_Comm comm) {
    CSRGraph *g = *g_ptr;
    int N, M;
    if (rank == 0) { N = g->n_nodes; M = g->n_edges; }
    MPI_Bcast(&N, 1, MPI_INT, 0, comm);
    MPI_Bcast(&M, 1, MPI_INT, 0, comm);
    if (rank != 0) {
        g = malloc(sizeof(CSRGraph));
        g->n_nodes = N;
        g->n_edges = M;
        g->row_ptr = malloc((N + 1) * sizeof(int));
        g->out_degree = malloc(N * sizeof(int));
        g->inv_out_degree = malloc(N * sizeof(double));
        g->col_idx = malloc((M > 0 ? M : 1) * sizeof(int));
        g->names = malloc(N * NAME_LEN);
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

int main(int argc, char **argv) {
    MPI_Init(&argc, &argv);
    int rank, size;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);

    if (argc < 3) {
        if (rank == 0) {
            printf("Usage: %s <csv_file> <directed|undirected> [damping=0.85] [tol=1e-10] [max_iter=1000]\n", argv[0]);
        }
        MPI_Finalize();
        return 1;
    }

    const char *filename = argv[1];
    int directed = (strcmp(argv[2], "directed") == 0);
    double damping = (argc > 3) ? atof(argv[3]) : 0.85;
    double tol = (argc > 4) ? atof(argv[4]) : 1e-10;
    int max_iter = (argc > 5) ? atoi(argv[5]) : 1000;

    CSRGraph *g = NULL;
    if (rank == 0) g = load_csv_root(filename, directed);
    broadcast_graph(&g, rank, MPI_COMM_WORLD);

    int N = g->n_nodes;
    int begin, end;
    owner_range(N, size, rank, &begin, &end);

    double *pr = malloc(N * sizeof(double));
    double *pr_new = malloc(N * sizeof(double));
    for (int i = 0; i < N; i++) pr[i] = 1.0 / N;

    double base = (1.0 - damping) / N;
    int iters = 0;
    double t0 = MPI_Wtime();
    for (int iter = 0; iter < max_iter; iter++) {
        double dangling_local = 0.0;
        for (int i = begin; i < end; i++) if (g->out_degree[i] == 0) dangling_local += pr[i];
        double dangling = 0.0;
        MPI_Allreduce(&dangling_local, &dangling, 1, MPI_DOUBLE, MPI_SUM, MPI_COMM_WORLD);
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
        MPI_Allreduce(&diff_local, &diff, 1, MPI_DOUBLE, MPI_SUM, MPI_COMM_WORLD);

        int *recvcounts = malloc(size * sizeof(int));
        int *displs = malloc(size * sizeof(int));
        for (int r = 0; r < size; r++) {
            int b, e;
            owner_range(N, size, r, &b, &e);
            recvcounts[r] = e - b;
            displs[r] = b;
        }
        MPI_Allgatherv(pr_new + begin, end - begin, MPI_DOUBLE,
                       pr, recvcounts, displs, MPI_DOUBLE, MPI_COMM_WORLD);
        free(recvcounts);
        free(displs);

        iters = iter + 1;
        if (diff < tol) break;
    }
    double t1 = MPI_Wtime();

    if (rank == 0) {
        double sum = 0.0;
        for (int i = 0; i < N; i++) sum += pr[i];
        printf("=== MPI PageRank ===\n");
        printf("File      : %s\n", filename);
        printf("Mode      : %s\n", directed ? "directed" : "undirected");
        printf("Ranks     : %d\n", size);
        printf("Iterations : %d\n", iters);
        printf("PR time    : %.6f s\n", t1 - t0);
        printf("PR sum     : %.10f\n", sum);
        FILE *fp = fopen("pagerank_mpi_output.txt", "w");
        if (fp) {
            for (int i = 0; i < N; i++) fprintf(fp, "%s %.15e\n", g->names[i], pr[i]);
            fclose(fp);
            printf("Results saved: pagerank_mpi_output.txt\n");
        }
    }

    free(pr);
    free(pr_new);
    free_graph(g);
    MPI_Finalize();
    return 0;
}
