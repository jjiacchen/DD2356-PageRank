cat > baseline_results.md << 'MDEOF'
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

## Correctness Verification ✓

- 全部 9 个数据集，三个平台，PR sum = 1.0000000000 ✓
- 三平台 Top-10 节点排名完全一致 ✓
- Iterations 在三平台完全相同 ✓

---

## Key Observations（报告用）

1. **KTH集群最快**：主频 3.80GHz 最高，serial 单核跑主频决定一切
2. **Dardel load time 偏高**：Lustre 分布式文件系统延迟高，正常现象
3. **小图 I/O 是瓶颈**：小图 load time >> PR time，并行化收益有限
4. **Iterations 三平台一致**：算法正确，结果可重现
5. **Serial baseline 是 speedup 分母**：polblogs PR time 各平台 0.0174 / 0.0024 / 0.0035s
MDEOF
