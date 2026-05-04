/*
 * verify_correctness.c
 * DD2356 Final Project – 正确性验证框架
 *
 * 对比两个 PageRank 输出文件（serial vs parallel），
 * 报告: 最大误差、L1误差、L2误差，以及 PASS/FAIL 判定。
 *
 * 编译:
 *   gcc -O2 -o verify verify_correctness.c -lm
 *
 * 运行:
 *   ./verify pagerank_serial_output.txt pagerank_parallel_output.txt [tol=1e-6]
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#define MAX_NODES 200000
#define NAME_LEN  64

typedef struct { char name[NAME_LEN]; double pr; } PREntry;

int pr_cmp_name(const void *a, const void *b) {
    return strcmp(((PREntry*)a)->name, ((PREntry*)b)->name);
}

PREntry *load_pr(const char *filename, int *n_out) {
    FILE *fp = fopen(filename, "r");
    if (!fp) { perror(filename); exit(1); }

    PREntry *arr = malloc(MAX_NODES * sizeof(PREntry));
    int n = 0;
    char line[128];
    while (fgets(line, sizeof(line), fp) && n < MAX_NODES) {
        line[strcspn(line, "\r\n")] = 0;
        if (!line[0]) continue;
        /* 格式: NodeName PR_value */
        char *sp = strrchr(line, ' ');
        if (!sp) continue;
        *sp = 0;
        strncpy(arr[n].name, line, NAME_LEN-1);
        arr[n].pr = atof(sp+1);
        n++;
    }
    fclose(fp);
    /* 按节点名排序，方便对比 */
    qsort(arr, n, sizeof(PREntry), pr_cmp_name);
    *n_out = n;
    return arr;
}

int main(int argc, char *argv[]) {
    if (argc < 3) {
        printf("Usage: %s <reference.txt> <candidate.txt> [tol=1e-6]\n", argv[0]);
        return 1;
    }
    double tol = (argc > 3) ? atof(argv[3]) : 1e-6;

    int nr, nc;
    PREntry *ref = load_pr(argv[1], &nr);
    PREntry *cnd = load_pr(argv[2], &nc);

    if (nr != nc) {
        fprintf(stderr, "ERROR: Node count mismatch (%d vs %d)\n", nr, nc);
        return 1;
    }

    double max_err = 0.0, l1 = 0.0, l2 = 0.0;
    char   max_node[NAME_LEN] = {0};
    int    mismatch_nodes = 0;

    for (int i = 0; i < nr; i++) {
        if (strcmp(ref[i].name, cnd[i].name) != 0) {
            fprintf(stderr, "Node name mismatch at index %d: %s vs %s\n",
                    i, ref[i].name, cnd[i].name);
            mismatch_nodes++;
            continue;
        }
        double diff = fabs(ref[i].pr - cnd[i].pr);
        l1 += diff;
        l2 += diff * diff;
        if (diff > max_err) {
            max_err = diff;
            strncpy(max_node, ref[i].name, NAME_LEN-1);
        }
    }
    l2 = sqrt(l2);

    printf("=== Correctness Verification ===\n");
    printf("Reference : %s  (%d nodes)\n", argv[1], nr);
    printf("Candidate : %s  (%d nodes)\n", argv[2], nc);
    printf("Tolerance : %.2e\n\n", tol);
    if (mismatch_nodes)
        printf("WARNING: %d node name mismatches!\n\n", mismatch_nodes);
    printf("Max |err| : %.6e  (node: %s)\n", max_err, max_node);
    printf("L1  error : %.6e\n", l1);
    printf("L2  error : %.6e\n", l2);

    if (max_err <= tol && mismatch_nodes == 0) {
        printf("\n[PASS] Max error within tolerance %.2e\n", tol);
        return 0;
    } else {
        printf("\n[FAIL] Max error %.2e exceeds tolerance %.2e\n", max_err, tol);
        return 1;
    }
}
