/*
 * pagerank_mpi.c
 * DD2356 Final Project - MPI PageRank
 *
 * 完全对齐课程 PageRank-master 数据集：
 *   CSV格式: node_a,val_a,node_b,val_b
 *   节点名可以是整数（polblogs）或字符串（dolphins, lesmis, karate）
 *
 * 编译:
 *   mpicc -O2 -o mpi/pagerank_mpi mpi/pagerank_mpi.c -lm
 *
 * 运行:
 *   mpirun -np 4 ./mpi/pagerank_mpi <csv_file> directed
 *   mpirun -np 4 ./mpi/pagerank_mpi <csv_file> undirected
 *
 * 示例:
 *   mpirun -np 4 ./mpi/pagerank_mpi data/polblogs.csv directed
 *   mpirun -np 4 ./mpi/pagerank_mpi data/dolphins.csv undirected
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>
#include <mpi.h>

/* ═══════════════════════════════════════════════════════════════════
 *  字符串节点ID映射（节点名 → 内部连续ID 0..N-1）
 * ═══════════════════════════════════════════════════════════════════ */
#define MAX_NODES 100000
#define NAME_LEN  64

typedef struct StrEntry {
    char key[NAME_LEN];
    int  val;
    struct StrEntry *next;
} StrEntry;

#define SHT_SIZE (1 << 17)
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
    strncpy(e->key, key, NAME_LEN-1);
    e->val = (*next_id)++;
    e->next = sht[h]; sht[h] = e;
    return e->val;
}

/* ═══════════════════════════════════════════════════════════════════
 *  节点名映射表（内部ID → 原始名称字符串）
 * ═══════════════════════════════════════════════════════════════════ */
typedef struct {
    char (*names)[NAME_LEN];  /* names[i] = 内部ID i 对应的节点名 */
    int   n;
} NodeMap;

/* ═══════════════════════════════════════════════════════════════════
 *  动态整数数组
 * ═══════════════════════════════════════════════════════════════════ */
typedef struct { int *data; int size; int cap; } IntVec;
static void iv_push(IntVec *v, int x) {
    if (v->size == v->cap) {
        v->cap = v->cap ? v->cap * 2 : 16;
        v->data = realloc(v->data, v->cap * sizeof(int));
    }
    v->data[v->size++] = x;
}

/* ═══════════════════════════════════════════════════════════════════
 *  CSR 图（按入边存储）
 * ═══════════════════════════════════════════════════════════════════ */
typedef struct {
    int  n_nodes, n_edges;
    int *row_ptr;    /* 入边范围: row_ptr[v]..row_ptr[v+1]-1 */
    int *col_idx;    /* 入边源节点列表                        */
    int *out_degree; /* 出度                                  */
} CSRGraph;

/* ═══════════════════════════════════════════════════════════════════
 *  解析一行 CSV，提取两端节点名
 *
 *  格式变体:
 *    "NodeA",0,"NodeB",0   (字符串节点带引号)
 *    123,0,456,0           (整数节点不带引号)
 * ═══════════════════════════════════════════════════════════════════ */
static int parse_line(const char *line, char *na, char *nb) {
    const char *p = line;

    /* 解析第一个节点名 */
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

    /* 跳过 val_a */
    while (*p && *p != ',') p++;
    if (*p != ',') return 0;
    p++;

    /* 解析第二个节点名 */
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
    if (!na[0] || !nb[0]) return 0;
    return 1;
}

/* ═══════════════════════════════════════════════════════════════════
 *  加载 CSV，构建 CSR 图
 * ═══════════════════════════════════════════════════════════════════ */
CSRGraph *load_csv(const char *filename, int directed, NodeMap *nm) {
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

        if (directed) {
            iv_push(&srcs, ia); iv_push(&dsts, ib);
        } else {
            iv_push(&srcs, ia); iv_push(&dsts, ib);
            iv_push(&srcs, ib); iv_push(&dsts, ia);
        }
    }
    fclose(fp);

    int N = next_id, M = srcs.size;

    /* 建立节点名映射 */
    nm->names = malloc(N * NAME_LEN);
    nm->n = N;
    for (int s = 0; s < SHT_SIZE; s++)
        for (StrEntry *e = sht[s]; e; e = e->next)
            strncpy(nm->names[e->val], e->key, NAME_LEN-1);

    /* 构建 CSR（入边） */
    CSRGraph *g   = malloc(sizeof(CSRGraph));
    g->n_nodes    = N; g->n_edges = M;
    g->out_degree = calloc(N, sizeof(int));
    g->row_ptr    = calloc(N+1, sizeof(int));
    g->col_idx    = malloc(M ? M * sizeof(int) : 1);

    int *in_cnt = calloc(N, sizeof(int));
    for (int i = 0; i < M; i++) {
        g->out_degree[srcs.data[i]]++;
        in_cnt[dsts.data[i]]++;
    }
    g->row_ptr[0] = 0;
    for (int i = 0; i < N; i++)
        g->row_ptr[i+1] = g->row_ptr[i] + in_cnt[i];

    int *pos = calloc(N, sizeof(int));
    for (int i = 0; i < M; i++) {
        int d = dsts.data[i];
        g->col_idx[g->row_ptr[d] + pos[d]++] = srcs.data[i];
    }

    free(srcs.data); free(dsts.data); free(in_cnt); free(pos);
    return g;
}

void free_graph(CSRGraph *g) {
    free(g->row_ptr); free(g->col_idx); free(g->out_degree); free(g);
}

static void block_range(int n, int rank, int size, int *start, int *end) {
    int base = n / size;
    int rem  = n % size;
    int cnt  = base + (rank < rem);
    *start   = rank * base + (rank < rem ? rank : rem);
    *end     = *start + cnt;
}

static void make_counts_displs(int n, int size, int *counts, int *displs) {
    int offset = 0;
    for (int r = 0; r < size; r++) {
        int start, end;
        block_range(n, r, size, &start, &end);
        counts[r] = end - start;
        displs[r] = offset;
        offset += counts[r];
    }
}

typedef struct {
    double dangling_reduce;
    double diff_reduce;
    double allgatherv;
} MpiTiming;

/* ═══════════════════════════════════════════════════════════════════
 *  MPI PageRank - Power Iteration
 *
 *  PR(v) = (1-d)/N  +  d * Σ_{u→v}  PR(u) / out_degree(u)
 *  Dangling nodes（出度=0）rank 均匀分配给所有节点。
 *
 *  Decomposition strategy:
 *    - Each MPI rank loads a full copy of the CSR graph and current PR vector.
 *    - Rank r computes only a contiguous block of destination nodes.
 *    - Each iteration uses:
 *        MPI_Allreduce for dangling mass
 *        MPI_Allreduce for global L1 difference
 *        MPI_Allgatherv for the next full PR vector
 * ═══════════════════════════════════════════════════════════════════ */
double *pagerank_mpi(const CSRGraph *g,
                     double damping, double tol, int max_iter,
                     int rank, int size, int *iters_out,
                     MpiTiming *timing)
{
    int N = g->n_nodes;
    double *pr     = malloc(N * sizeof(double));
    double *pr_new = malloc(N * sizeof(double));
    int    *counts = malloc(size * sizeof(int));
    int    *displs = malloc(size * sizeof(int));
    if (!pr || !pr_new || !counts || !displs) {
        fprintf(stderr, "Rank %d: allocation failed in pagerank_mpi\n", rank);
        MPI_Abort(MPI_COMM_WORLD, 2);
    }

    for (int i = 0; i < N; i++) pr[i] = 1.0 / N;

    int local_start, local_end;
    block_range(N, rank, size, &local_start, &local_end);
    int local_n = local_end - local_start;
    make_counts_displs(N, size, counts, displs);

    double base = (1.0 - damping) / N;
    timing->dangling_reduce = 0.0;
    timing->diff_reduce = 0.0;
    timing->allgatherv = 0.0;
    int iter;

    for (iter = 0; iter < max_iter; iter++) {

        /* dangling node contribution: local block first, then global sum */
        double local_dangling = 0.0, dangling = 0.0;
        for (int i = local_start; i < local_end; i++)
            if (g->out_degree[i] == 0) local_dangling += pr[i];

        double t_comm = MPI_Wtime();
        MPI_Allreduce(&local_dangling, &dangling, 1, MPI_DOUBLE,
                      MPI_SUM, MPI_COMM_WORLD);
        timing->dangling_reduce += MPI_Wtime() - t_comm;

        double dang = damping * dangling / N;

        /* local kernel: traverse incoming edges for this rank's node block */
        for (int v = local_start; v < local_end; v++) {
            double s = 0.0;
            for (int k = g->row_ptr[v]; k < g->row_ptr[v+1]; k++) {
                int u = g->col_idx[k];
                s += pr[u] / (double)g->out_degree[u];
            }
            pr_new[v] = base + dang + damping * s;
        }

        /* L1 convergence check */
        double local_diff = 0.0, diff = 0.0;
        for (int i = local_start; i < local_end; i++)
            local_diff += fabs(pr_new[i] - pr[i]);

        t_comm = MPI_Wtime();
        MPI_Allreduce(&local_diff, &diff, 1, MPI_DOUBLE,
                      MPI_SUM, MPI_COMM_WORLD);
        timing->diff_reduce += MPI_Wtime() - t_comm;

        t_comm = MPI_Wtime();
        MPI_Allgatherv(local_n ? pr_new + local_start : pr_new, local_n,
                       MPI_DOUBLE, pr, counts, displs, MPI_DOUBLE,
                       MPI_COMM_WORLD);
        timing->allgatherv += MPI_Wtime() - t_comm;

        if (diff < tol) { iter++; break; }
    }

    free(pr_new); free(counts); free(displs);
    *iters_out = iter;
    return pr;
}

/* ═══════════════════════════════════════════════════════════════════
 *  输出工具
 * ═══════════════════════════════════════════════════════════════════ */
typedef struct { int idx; double val; } RankPair;
static int rp_cmp(const void *a, const void *b) {
    double da = ((RankPair*)a)->val, db = ((RankPair*)b)->val;
    return (da < db) - (da > db);
}

void print_top_k(const double *pr, const NodeMap *nm, int K) {
    int N = nm->n;
    K = K > N ? N : K;
    RankPair *rp = malloc(N * sizeof(RankPair));
    for (int i = 0; i < N; i++) { rp[i].idx = i; rp[i].val = pr[i]; }
    qsort(rp, N, sizeof(RankPair), rp_cmp);
    printf("\nTop-%d nodes:\n", K);
    printf("  %-6s  %-20s  %s\n", "Rank", "Node", "PageRank");
    printf("  ------  --------------------  --------------------\n");
    for (int i = 0; i < K; i++)
        printf("  %-6d  %-20s  %.10f\n",
               i+1, nm->names[rp[i].idx], rp[i].val);
    free(rp);
}

/* 保存完整 PR 向量（供并行版本正确性验证使用） */
void save_results(const char *out_file, const double *pr, const NodeMap *nm) {
    FILE *fp = fopen(out_file, "w");
    if (!fp) { perror("save_results"); return; }
    /* 按内部ID输出（对比时保持一致顺序） */
    for (int i = 0; i < nm->n; i++)
        fprintf(fp, "%s %.15e\n", nm->names[i], pr[i]);
    fclose(fp);
    printf("Results saved: %s\n", out_file);
}

/* ═══════════════════════════════════════════════════════════════════
 *  Main
 * ═══════════════════════════════════════════════════════════════════ */
int main(int argc, char *argv[]) {
    MPI_Init(&argc, &argv);

    int rank, size;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);

    if (argc < 3) {
        if (rank == 0) {
            printf("Usage: %s <csv_file> <directed|undirected>"
                   " [damping=0.85] [tol=1e-10] [max_iter=1000]"
                   " [output=pagerank_mpi_output.txt]\n\n", argv[0]);
            printf("Examples:\n");
            printf("  mpirun -np 4 %s data/polblogs.csv directed\n", argv[0]);
            printf("  mpirun -np 4 %s data/dolphins.csv undirected\n", argv[0]);
        }
        MPI_Finalize();
        return 1;
    }

    const char *filename = argv[1];
    int    directed = (strcmp(argv[2], "directed") == 0);
    double damping  = (argc > 3) ? atof(argv[3]) : 0.85;
    double tol      = (argc > 4) ? atof(argv[4]) : 1e-10;
    int    max_iter = (argc > 5) ? atoi(argv[5]) : 1000;
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

    /* Each rank loads the graph. The initial MPI version prioritizes a simple
       communication model over distributed graph storage. */
    MPI_Barrier(MPI_COMM_WORLD);
    double t0 = MPI_Wtime();
    NodeMap nm = {0};
    CSRGraph *g = load_csv(filename, directed, &nm);
    double local_load_t = MPI_Wtime() - t0;
    double load_t = 0.0;
    MPI_Reduce(&local_load_t, &load_t, 1, MPI_DOUBLE, MPI_MAX, 0,
               MPI_COMM_WORLD);

    int local_stats[2] = {g->n_nodes, g->n_edges};
    int min_stats[2], max_stats[2];
    MPI_Allreduce(local_stats, min_stats, 2, MPI_INT, MPI_MIN, MPI_COMM_WORLD);
    MPI_Allreduce(local_stats, max_stats, 2, MPI_INT, MPI_MAX, MPI_COMM_WORLD);
    if (min_stats[0] != max_stats[0] || min_stats[1] != max_stats[1]) {
        fprintf(stderr, "Rank %d: inconsistent graph load (%d nodes, %d edges)\n",
                rank, g->n_nodes, g->n_edges);
        MPI_Abort(MPI_COMM_WORLD, 3);
    }

    int local_start, local_end;
    block_range(g->n_nodes, rank, size, &local_start, &local_end);
    int local_nodes = local_end - local_start;
    int local_in_edges = g->row_ptr[local_end] - g->row_ptr[local_start];

    int min_nodes = 0, max_nodes = 0, sum_nodes = 0;
    int min_in_edges = 0, max_in_edges = 0, sum_in_edges = 0;
    MPI_Reduce(&local_nodes, &min_nodes, 1, MPI_INT, MPI_MIN, 0,
               MPI_COMM_WORLD);
    MPI_Reduce(&local_nodes, &max_nodes, 1, MPI_INT, MPI_MAX, 0,
               MPI_COMM_WORLD);
    MPI_Reduce(&local_nodes, &sum_nodes, 1, MPI_INT, MPI_SUM, 0,
               MPI_COMM_WORLD);
    MPI_Reduce(&local_in_edges, &min_in_edges, 1, MPI_INT, MPI_MIN, 0,
               MPI_COMM_WORLD);
    MPI_Reduce(&local_in_edges, &max_in_edges, 1, MPI_INT, MPI_MAX, 0,
               MPI_COMM_WORLD);
    MPI_Reduce(&local_in_edges, &sum_in_edges, 1, MPI_INT, MPI_SUM, 0,
               MPI_COMM_WORLD);

    if (rank == 0) {
        double avg_nodes = sum_nodes / (double)size;
        double avg_in_edges = sum_in_edges / (double)size;
        double edge_imbalance = avg_in_edges > 0.0 ? max_in_edges / avg_in_edges : 0.0;

        printf("Nodes     : %d\n", g->n_nodes);
        printf("Edges     : %d\n", g->n_edges);
        printf("Load time : %.4f s  (max across ranks)\n", load_t);
        printf("Block     : contiguous node ranges; rank 0 owns [%d, %d)\n\n",
               local_start, local_end);
        printf("Work nodes : min=%d avg=%.2f max=%d\n",
               min_nodes, avg_nodes, max_nodes);
        printf("Work inedges : min=%d avg=%.2f max=%d imbalance=%.3f\n\n",
               min_in_edges, avg_in_edges, max_in_edges, edge_imbalance);
    }

    /* Run PageRank and report max timings across ranks. */
    int iters = 0;
    MpiTiming local_timing;
    MPI_Barrier(MPI_COMM_WORLD);
    t0 = MPI_Wtime();
    double *pr = pagerank_mpi(g, damping, tol, max_iter,
                              rank, size, &iters, &local_timing);
    double local_pr_t = MPI_Wtime() - t0;

    double local_comm_t = local_timing.dangling_reduce +
                          local_timing.diff_reduce +
                          local_timing.allgatherv;
    double pr_t = 0.0, comm_t = 0.0;
    double dangling_t = 0.0, diff_t = 0.0, allgatherv_t = 0.0;
    MPI_Reduce(&local_pr_t, &pr_t, 1, MPI_DOUBLE, MPI_MAX, 0,
               MPI_COMM_WORLD);
    MPI_Reduce(&local_comm_t, &comm_t, 1, MPI_DOUBLE, MPI_MAX, 0,
               MPI_COMM_WORLD);
    MPI_Reduce(&local_timing.dangling_reduce, &dangling_t, 1, MPI_DOUBLE,
               MPI_MAX, 0, MPI_COMM_WORLD);
    MPI_Reduce(&local_timing.diff_reduce, &diff_t, 1, MPI_DOUBLE,
               MPI_MAX, 0, MPI_COMM_WORLD);
    MPI_Reduce(&local_timing.allgatherv, &allgatherv_t, 1, MPI_DOUBLE,
               MPI_MAX, 0, MPI_COMM_WORLD);

    double sum = 0.0;
    for (int i = 0; i < g->n_nodes; i++) sum += pr[i];
    double max_sum = 0.0, min_sum = 0.0;
    MPI_Reduce(&sum, &max_sum, 1, MPI_DOUBLE, MPI_MAX, 0, MPI_COMM_WORLD);
    MPI_Reduce(&sum, &min_sum, 1, MPI_DOUBLE, MPI_MIN, 0, MPI_COMM_WORLD);

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

        print_top_k(pr, &nm, 10);
        save_results(out_file, pr, &nm);
    }

    free(pr); free(nm.names); free_graph(g);
    MPI_Finalize();
    return 0;
}
