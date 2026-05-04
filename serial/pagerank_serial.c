/*
 * pagerank_serial.c
 * DD2356 Final Project – Serial Baseline PageRank
 *
 * 完全对齐课程 PageRank-master 数据集：
 *   CSV格式: node_a,val_a,node_b,val_b
 *   节点名可以是整数（polblogs）或字符串（dolphins, lesmis, karate）
 *
 * 编译:
 *   gcc -O2 -o pagerank_serial pagerank_serial.c -lm
 *
 * 运行:
 *   ./pagerank_serial <csv_file> directed   [damping=0.85] [tol=1e-10] [max_iter=1000]
 *   ./pagerank_serial <csv_file> undirected [damping=0.85] [tol=1e-10] [max_iter=1000]
 *
 * 示例:
 *   ./pagerank_serial data/polblogs.csv    directed
 *   ./pagerank_serial data/dolphins.csv    undirected
 *   ./pagerank_serial data/lesmisDir.csv   directed
 *   ./pagerank_serial data/karateDir.csv   directed
 *   ./pagerank_serial data/NCAA_football.csv directed
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>

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

/* ═══════════════════════════════════════════════════════════════════
 *  Serial PageRank – Power Iteration
 *
 *  PR(v) = (1-d)/N  +  d * Σ_{u→v}  PR(u) / out_degree(u)
 *  Dangling nodes（出度=0）rank 均匀分配给所有节点。
 * ═══════════════════════════════════════════════════════════════════ */
double *pagerank(const CSRGraph *g,
                 double damping, double tol, int max_iter,
                 int *iters_out)
{
    int N = g->n_nodes;
    double *pr     = malloc(N * sizeof(double));
    double *pr_new = malloc(N * sizeof(double));

    for (int i = 0; i < N; i++) pr[i] = 1.0 / N;

    double base = (1.0 - damping) / N;
    int iter;

    for (iter = 0; iter < max_iter; iter++) {

        /* dangling node 贡献 */
        double dangling = 0.0;
        for (int i = 0; i < N; i++)
            if (g->out_degree[i] == 0) dangling += pr[i];
        double dang = damping * dangling / N;

        /* 核心迭代：遍历每个节点的入边 */
        for (int v = 0; v < N; v++) {
            double s = 0.0;
            for (int k = g->row_ptr[v]; k < g->row_ptr[v+1]; k++) {
                int u = g->col_idx[k];
                s += pr[u] / (double)g->out_degree[u];
            }
            pr_new[v] = base + dang + damping * s;
        }

        /* L1 收敛检测 */
        double diff = 0.0;
        for (int i = 0; i < N; i++) diff += fabs(pr_new[i] - pr[i]);

        double *tmp = pr; pr = pr_new; pr_new = tmp;
        if (diff < tol) { iter++; break; }
    }

    free(pr_new);
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
    if (argc < 3) {
        printf("Usage: %s <csv_file> <directed|undirected>"
               " [damping=0.85] [tol=1e-10] [max_iter=1000]\n\n", argv[0]);
        printf("Examples:\n");
        printf("  %s data/polblogs.csv    directed\n", argv[0]);
        printf("  %s data/dolphins.csv    undirected\n", argv[0]);
        printf("  %s data/lesmisDir.csv   directed\n", argv[0]);
        printf("  %s data/NCAA_football.csv directed\n", argv[0]);
        return 1;
    }

    const char *filename = argv[1];
    int    directed = (strcmp(argv[2], "directed") == 0);
    double damping  = (argc > 3) ? atof(argv[3]) : 0.85;
    double tol      = (argc > 4) ? atof(argv[4]) : 1e-10;
    int    max_iter = (argc > 5) ? atoi(argv[5]) : 1000;

    printf("=== DD2356 Serial PageRank Baseline ===\n");
    printf("File      : %s\n", filename);
    printf("Mode      : %s\n", directed ? "directed" : "undirected");
    printf("Damping   : %.4f\n", damping);
    printf("Tolerance : %.2e\n", tol);
    printf("Max iter  : %d\n\n", max_iter);

    struct timespec t0, t1;

    /* 加载图 */
    clock_gettime(CLOCK_MONOTONIC, &t0);
    NodeMap nm = {0};
    CSRGraph *g = load_csv(filename, directed, &nm);
    clock_gettime(CLOCK_MONOTONIC, &t1);
    double load_t = (t1.tv_sec-t0.tv_sec) + (t1.tv_nsec-t0.tv_nsec)*1e-9;

    printf("Nodes     : %d\n", g->n_nodes);
    printf("Edges     : %d\n", g->n_edges);
    printf("Load time : %.4f s\n\n", load_t);

    /* 运行 PageRank */
    int iters = 0;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    double *pr = pagerank(g, damping, tol, max_iter, &iters);
    clock_gettime(CLOCK_MONOTONIC, &t1);
    double pr_t = (t1.tv_sec-t0.tv_sec) + (t1.tv_nsec-t0.tv_nsec)*1e-9;

    double sum = 0.0;
    for (int i = 0; i < g->n_nodes; i++) sum += pr[i];

    printf("Iterations : %d\n", iters);
    printf("PR time    : %.6f s\n", pr_t);
    printf("PR sum     : %.10f  (should be ~1.0)\n", sum);

    print_top_k(pr, &nm, 10);
    save_results("pagerank_serial_output.txt", pr, &nm);

    free(pr); free(nm.names); free_graph(g);
    return 0;
}
