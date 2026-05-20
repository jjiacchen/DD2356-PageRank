# Baseline Profiling Results – Serial PageRank
**DD2356 Group 26**: Jiachen Shi, Minyi Zhu, Pengyu Wang

---

## System Info

| 项目 | Colab | KTH集群 | Dardel |
|------|-------|---------|--------|
| OS | Ubuntu 22.04 | Ubuntu 22.04 | Linux |
| CPU | Intel Xeon @ 2.20GHz | Intel Xeon Platinum 8480C @ 3.8GHz | AMD EPYC 7742 |
| 物理核心数 | 1 | 112 (2 socket × 56 core) | 128 cores/node |
| 逻辑核心数 | 1 | 224 (× 2 threads) | 256/node |
| L3 Cache | — | 210 MiB | 256 MiB |
| 内存 | 12 GB | 2.0 TB | 256 GB/node |
| NUMA nodes | — | 2 | 2 |
| 编译器 | gcc 11.4.0 (-O2) | gcc 12.3.0 (-O2) | TBD |

---

## Runtime Results per Dataset

### polblogs.csv (directed · 1224 nodes · 19090 edges) ← 主测试集

| 指标 | Colab | KTH集群 | Dardel |
|------|-------|---------|--------|
| Load time (s) | 0.0211 | 0.0016 | TBD |
| PR time (s) | 0.017396 | 0.002399 | TBD |
| Iterations | 108 | 108 | TBD |
| PR sum | 1.0000000000 ✓ | 1.0000000000 ✓ | TBD |
| Time Min / 5次 (s) | 0.024317 | 0.005651 | TBD |
| Time Max / 5次 (s) | 0.041574 | 0.007096 | TBD |
| Time Avg / 5次 (s) | 0.032609 | 0.006052 | TBD |
| **KTH vs Colab 加速比** | 1.0× | **5.4×** | TBD |

### karateDir.csv (directed · 34 nodes · 78 edges)

| 指标 | Colab | KTH集群 | Dardel |
|------|-------|---------|--------|
| Load time (s) | 0.0110 | 0.0005 | TBD |
| PR time (s) | 0.000010 | 0.000003 | TBD |
| Iterations | 22 | 22 | TBD |
| PR sum | 1.0000000000 ✓ | 1.0000000000 ✓ | TBD |

### lesmisDir.csv (directed · 77 nodes · 254 edges)

| 指标 | Colab | KTH集群 | Dardel |
|------|-------|---------|--------|
| Load time (s) | 0.0020 | 0.0005 | TBD |
| PR time (s) | 0.000033 | 0.000014 | TBD |
| Iterations | 36 | 36 | TBD |
| PR sum | 1.0000000000 ✓ | 1.0000000000 ✓ | TBD |

### dolphinsDir.csv (directed · 62 nodes · 159 edges)

| 指标 | Colab | KTH集群 | Dardel |
|------|-------|---------|--------|
| Load time (s) | 0.0025 | 0.0005 | TBD |
| PR time (s) | 0.000025 | 0.000010 | TBD |
| Iterations | 29 | 29 | TBD |
| PR sum | 1.0000000000 ✓ | 1.0000000000 ✓ | TBD |

### NCAA_football.csv (directed · 570 nodes · 1537 edges)

| 指标 | Colab | KTH集群 | Dardel |
|------|-------|---------|--------|
| Load time (s) | 0.0015 | 0.0007 | TBD |
| PR time (s) | 0.000176 | 0.000064 | TBD |
| Iterations | 24 | 24 | TBD |
| PR sum | 1.0000000000 ✓ | 1.0000000000 ✓ | TBD |

### dolphins.csv (undirected · 62 nodes · 636 edges)

| 指标 | Colab | KTH集群 | Dardel |
|------|-------|---------|--------|
| Load time (s) | 0.0019 | 0.0005 | TBD |
| PR time (s) | 0.000148 | 0.000062 | TBD |
| Iterations | 86 | 86 | TBD |
| PR sum | 1.0000000000 ✓ | 1.0000000000 ✓ | TBD |

### karate.csv (undirected · 34 nodes · 312 edges)

| 指标 | Colab | KTH集群 | Dardel |
|------|-------|---------|--------|
| Load time (s) | 0.0031 | 0.0005 | TBD |
| PR time (s) | 0.000044 | 0.000022 | TBD |
| Iterations | 60 | 60 | TBD |
| PR sum | 1.0000000000 ✓ | 1.0000000000 ✓ | TBD |

### lesmis.csv (undirected · 77 nodes · 1016 edges)

| 指标 | Colab | KTH集群 | Dardel |
|------|-------|---------|--------|
| Load time (s) | 0.0012 | 0.0006 | TBD |
| PR time (s) | 0.000174 | 0.000107 | TBD |
| Iterations | 76 | 76 | TBD |
| PR sum | 1.0000000000 ✓ | 1.0000000000 ✓ | TBD |

### stateborders.csv (undirected · 51 nodes · 428 edges)

| 指标 | Colab | KTH集群 | Dardel |
|------|-------|---------|--------|
| Load time (s) | 0.0014 | 0.0005 | TBD |
| PR time (s) | 0.000114 | 0.000045 | TBD |
| Iterations | 90 | 90 | TBD |
| PR sum | 1.0000000000 ✓ | 1.0000000000 ✓ | TBD |

---

## Correctness Verification

- 全部 9 个数据集，两个平台，PR sum = 1.0000000000 ✓
- 两平台 Top-10 节点排名完全一致 ✓
- Iterations 在两平台完全相同（收敛行为与硬件无关）✓
- `pagerank_serial_output.txt` 作为后续 OpenMP / MPI 版本的黄金参考

---

## Cross-Platform Performance Comparison（报告分析用）

### polblogs PR time 对比

| 平台 | PR time (s) | 相对 Colab |
|------|------------|-----------|
| Colab (Xeon 2.20GHz, 1核) | 0.017396 | 1.0× (baseline) |
| KTH集群 (Xeon 8480C, 3.8GHz) | 0.002399 | **7.3× faster** |
| Dardel (EPYC 7742) | TBD | TBD |

### 性能差异原因分析

| 因素 | Colab | KTH集群 | 影响 |
|------|-------|---------|------|
| CPU主频 | 2.20 GHz | 3.80 GHz | +73% 主频优势 |
| L3 Cache | 小 | 210 MiB | 大缓存减少 cache miss |
| 内存带宽 | 低 | 高（2TB系统）| 稀疏图访问受益明显 |
| 收敛迭代 | 108次 | 108次 | 相同（算法一致）|

### 关键观察

1. **Load time 差异显著**：polblogs 从 0.021s → 0.0016s（13× 提升），说明 KTH 磁盘 I/O 更快
2. **PR time 差异**：7.3× 提升主要来自更高主频 + 更大 L3 cache
3. **小图上 load time >> PR time**：I/O 是小图的主要瓶颈，并行化 PR 计算对小图意义不大
4. **Iterations 完全一致**：验证了两平台算法实现的一致性，结果可信

---

## TODO
- [ ] 在 Dardel 上提交 SLURM job，填入 TBD 列
- [ ] OpenMP 并行化后用 `verify` 工具与此 serial baseline 对比正确性
- [ ] MPI 并行化后同样做正确性对比
