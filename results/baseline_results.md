# Baseline Profiling Results – Serial PageRank
**DD2356 Group 26**: Jiachen Shi, Minyi Zhu, Pengyu Wang

---

## System Info

| 项目 | Colab | KTH集群 | Dardel |
|------|-------|---------|--------|
| OS | Ubuntu 22.04 | Ubuntu 22.04 | SUSE Linux |
| CPU | Intel Xeon @ 2.20GHz | Intel Xeon Platinum 8480C | AMD EPYC 7742 |
| 主频 | 2.20 GHz | 3.80 GHz (max) | 2.25 GHz (max) |
| 物理核心数 | 1 | 112 (2×56) | 128 (2×64) |
| 逻辑核心数 | 1 | 224 | 256 |
| 内存 | 12 GB | 2.0 TB | 250 GB |
| 编译器 | gcc 11.4.0 | gcc 12.3.0 | gcc 7.5.0 |

---

## Runtime Results – polblogs.csv（主测试集）
**directed · 1224 nodes · 19090 edges**

| 指标 | Colab | KTH集群 | Dardel |
|------|-------|---------|--------|
| Load time (s) | 0.0211 | 0.0016 | 0.0108 |
| PR time (s) | 0.017396 | 0.002399 | 0.003452 |
| Iterations | 108 | 108 | 108 |
| PR sum | 1.0000000000 ✓ | 1.0000000000 ✓ | 1.0000000000 ✓ |
| Time Min / 5次 (s) | 0.024317 | 0.005651 | 0.011150 |
| Time Max / 5次 (s) | 0.041574 | 0.007096 | 0.011631 |
| Time Avg / 5次 (s) | 0.032609 | 0.006052 | 0.011346 |
| vs Colab 加速比 | 1.0× | 5.4× | 2.9× |

---

## Runtime Results – 全数据集

| 数据集 | 模式 | Nodes | Edges | Iters | Colab PR(s) | KTH PR(s) | Dardel PR(s) |
|--------|------|-------|-------|-------|-------------|-----------|--------------|
| polblogs | directed | 1224 | 19090 | 108 | 0.017396 | 0.002399 | 0.003452 |
| karateDir | directed | 34 | 78 | 22 | 0.000010 | 0.000003 | 0.000005 |
| lesmisDir | directed | 77 | 254 | 36 | 0.000033 | 0.000014 | 0.000019 |
| dolphinsDir | directed | 62 | 159 | 29 | 0.000025 | 0.000010 | 0.000011 |
| NCAA_football | directed | 570 | 1537 | 24 | 0.000176 | 0.000064 | 0.000085 |
| dolphins | undirected | 62 | 636 | 86 | 0.000148 | 0.000062 | 0.000089 |
| karate | undirected | 34 | 312 | 60 | 0.000044 | 0.000022 | 0.000031 |
| lesmis | undirected | 77 | 1016 | 76 | 0.000174 | 0.000107 | 0.000122 |
| stateborders | undirected | 51 | 428 | 90 | 0.000114 | 0.000045 | 0.000064 |

---

## Runtime Results – synthetic_large_directed.csv（大图性能测试）
**directed · 100000 nodes · 2000000 edges · estimated hot working set 10.68 MiB**

| 指标 | Colab | KTH集群 | Dardel |
|------|-------|---------|--------|
| PR time (s) | 0.156453 | 0.040141 | 0.089340 |
| Iterations | 16 | 16 | 16 |
| MEdges/s | 204.5 | 797.2 | 358.2 |
| vs Colab 加速比 | 1.0× | 3.90× | 1.75× |

**说明**：

- 大图由 `scripts/generate_large_graph.py` 生成，三个平台使用相同规模：100000 nodes 和 2000000 directed edges。
- 该数据集用于性能和扩展性分析，不替代小图 correctness suite。
- 相比 `polblogs`，大图每次 PageRank 运行访问 `2,000,000 × 16 = 32M` 条边，计时更稳定，也更能反映 cache/DRAM 访存行为。
- KTH 在大图 serial 上仍然最快，主要来自更强的单核性能和内存层次表现；Dardel 快于 Colab，但单核 serial 表现弱于 KTH。

---

## Correctness Verification ✓

- 全部 9 个数据集，三个平台，PR sum = 1.0000000000 ✓
- 三平台 Top-10 节点排名完全一致 ✓
- Iterations 在三平台完全相同 ✓

---

## Key Observations（报告用）

1. **小图用于 correctness， 大图用于 performance**：课程数据集运行快、便于验证；`synthetic_large_directed` 更适合观察真实性能差异。
2. **KTH集群 serial 最快**：`polblogs` 上 KTH 比 Colab 快 5.4×，大图上快 3.90×。
3. **Dardel serial 快于 Colab，但弱于 KTH**：大图上 Dardel 比 Colab 快 1.75×，但单核 PR time 仍高于 KTH。
4. **小图 I/O 和计时噪声占比高**：`polblogs` load time 在 Colab 和 Dardel 上占比较高，parallel speedup 应优先看 PR time 而不是 end-to-end time。
5. **Iterations 三平台一致**：小图和大图的迭代次数在三个平台一致，说明 serial 结果可复现。
6. **Serial baseline 是 speedup 分母**：并行版本应分别和同平台 serial PR time 比较，不能跨平台混用分母。
