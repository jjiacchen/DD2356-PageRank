# Platform Comparison Master Table

Use this file as the single source of truth for cross-platform performance comparison.

Platforms:
- `local` (this machine / WSL)
- `colab`
- `kth`
- `dardel`
- `cluster_cpu` (DD2356 school-cluster CPU session / pinned OpenMPI cores)
- `cluster_gpu` (DD2356 Small GPU server / NVIDIA H100 `MIG 1g.10gb`)

Variants:
- `serial`
- `openmp`
- `mpi`
- `hybrid`
- `gpu`

Main dataset:
- `polblogs.csv (directed)`

---

## 1) Main Comparison (polblogs)

| Variant | Platform | Config | Load time (s) | PR time (s) | Iterations | Speedup vs serial@same platform | Parallel efficiency |
|---|---|---|---:|---:|---:|---:|---:|
| serial | local | 1 thread | TBD | 0.001943 | 108 | 1.00 | 1.00 |
| serial | colab | 1 thread | 0.0211 | 0.017396 | 108 | 1.00 | 1.00 |
| serial | kth | 1 thread | 0.0016 | 0.002399 | 108 | 1.00 | 1.00 |
| serial | dardel | 1 thread | 0.0108 | 0.003452 | 108 | 1.00 | 1.00 |
| openmp | local | threads=1 | TBD | 0.001775 | 108 | 1.09 | 1.09 |
| openmp | local | threads=2 | TBD | 0.002522 | 108 | 0.77 | 0.39 |
| openmp | local | threads=4 | TBD | 0.002598 | 108 | 0.75 | 0.19 |
| openmp | local | threads=8 | TBD | 0.003797 | 108 | 0.51 | 0.06 |
| openmp | colab | threads=2 (best) | TBD | 0.003090 | 108 | 1.20 | 0.60 |
| openmp | kth | threads=? |  |  |  |  |  |
| openmp | dardel | threads=? |  |  |  |  |  |
| mpi | local | ranks=4 | 0.0010 | 0.004730 | 108 | 0.41 | 0.10 |
| mpi | colab | ranks=? |  |  |  |  |  |
| mpi | kth | ranks=16 |  | 0.002844 | 108 | 0.8435 | 0.0527 |
| mpi | dardel | ranks=16 | 0.0108 | 14.117646 | 108 | 0.000245 | 0.000015 |
| hybrid | local | ranks=? x threads=? |  |  |  |  |  |
| hybrid | colab | ranks=1 x threads=2 (best, P*N=2) | TBD | 0.003168 | 108 | 1.17 | 0.59 |
| hybrid | kth | ranks=16 x threads=1 |  | 0.002907 | 108 | 0.8253 | 0.0516 |
| hybrid | dardel | ranks=? x threads=? |  |  |  |  |  |
| gpu | local | omp-target fallback (diagnostic) | 0.0027 | 0.053566 | 108 | 0.04 | N/A |
| gpu | colab | omp-target |  |  |  |  |  |
| gpu | kth | omp-target |  |  |  |  |  |
| gpu | dardel | omp-target |  |  |  |  |  |

---

## 2) Full Dataset Runtime Matrix

Fill per platform and variant. Keep this table for appendix / detailed results.

| Dataset | Mode | Platform | Variant | Config | Nodes | Edges | PR time (s) | Iterations | PR sum | Correctness vs serial |
|---|---|---|---|---|---:|---:|---:|---:|---:|---|
| polblogs.csv | directed | local | serial | 1 thread | 1224 | 19090 | 0.001943 | 108 | 1.0000000000 | Reference |
| polblogs.csv | directed | local | openmp | threads=8 | 1224 | 19090 | 0.003797 | 108 | 1.0000000000 | PASS |
| polblogs.csv | directed | local | mpi | ranks=4 | 1224 | 19090 | 0.004730 | 108 | 1.0000000000 | PASS |
| polblogs.csv | directed | local | hybrid | ranks=2 x threads=4 | 1224 | 19090 |  |  |  | PASS/FAIL |
| polblogs.csv | directed | local | gpu | omp-target fallback (diagnostic) | 1224 | 19090 | 0.053566 | 108 | 1.0000000000 | PASS |
| karateDir.csv | directed | local | openmp/gpu | see verify matrix | 34 | 78 | TBD | 22 | 1.0000000000 | PASS |
| lesmisDir.csv | directed | local | openmp/gpu | see verify matrix | 77 | 254 | TBD | 36 | 1.0000000000 | PASS |
| dolphinsDir.csv | directed | local | openmp/gpu | see verify matrix | 62 | 159 | TBD | 29 | 1.0000000000 | PASS |
| NCAA_football.csv | directed | local | openmp/gpu | see verify matrix | 570 | 1537 | TBD | 24 | 1.0000000000 | PASS |
| dolphins.csv | undirected | local | openmp/gpu | see verify matrix | 62 | 636 | TBD | 86 | 1.0000000000 | PASS |
| karate.csv | undirected | local | openmp/gpu | see verify matrix | 34 | 312 | TBD | 60 | 1.0000000000 | PASS |
| lesmis.csv | undirected | local | openmp/gpu | see verify matrix | 77 | 1016 | TBD | 76 | 1.0000000000 | PASS |
| stateborders.csv | undirected | local | openmp/gpu | see verify matrix | 51 | 428 | TBD | 90 | 1.0000000000 | PASS |

---

## 3) Scaling Tables

### 3.1 OpenMP Strong Scaling (fixed dataset)
| Platform | Dataset | Threads | PR time (s) | Speedup vs 1 thread | Efficiency (= speedup / threads) |
|---|---|---:|---:|---:|---:|
| local | polblogs.csv | 1 | 0.001775 | 1.00 | 1.00 |
| local | polblogs.csv | 2 | 0.002522 | 0.70 | 0.35 |
| local | polblogs.csv | 4 | 0.002598 | 0.68 | 0.17 |
| local | polblogs.csv | 8 | 0.003797 | 0.47 | 0.06 |
| colab | polblogs.csv | 1 | 0.003715 | 1.000 | 1.000 |
| colab | polblogs.csv | 2 | 0.003090 | 1.202 | 0.601 |
| colab | polblogs.csv | 4 | 0.011389 | 0.326 | 0.082 |
| colab | synthetic_100k_1m.csv | 1 | 0.107972 | 1.000 | 1.000 |
| colab | synthetic_100k_1m.csv | 2 | 0.128534 | 0.840 | 0.420 |
| colab | synthetic_100k_1m.csv | 4 | 0.084794 | 1.273 | 0.318 |
| kth | polblogs.csv | 1 | 0.001484 | 1.00 | 1.00 |
| kth | polblogs.csv | 2 | 0.001889 | 0.785472 | 0.392736 |
| kth | polblogs.csv | 4 | 0.002927 | 0.506936 | 0.126734 |
| kth | polblogs.csv | 8 | 0.002461 | 0.602844 | 0.075356 |
| kth | polblogs.csv | 16 | 0.002844 | 0.521733 | 0.032608 |
| dardel | polblogs.csv | 1 |  | 1.00 | 1.00 |
| dardel | polblogs.csv | 2 |  |  |  |
| dardel | polblogs.csv | 4 |  |  |  |
| dardel | polblogs.csv | 8 |  |  |  |

### 3.2 MPI Strong Scaling (fixed dataset)
| Platform | Dataset | Ranks | PR time (s) | Speedup vs 1 rank | Efficiency (= speedup / ranks) |
|---|---|---:|---:|---:|---:|
| local | polblogs.csv | 1 | 0.001234 | 1.00 | 1.00 |
| local | polblogs.csv | 2 | 0.004863 | 0.253753 | 0.126876 |
| local | polblogs.csv | 4 | 0.004730 | 0.260888 | 0.065222 |
| kth | polblogs.csv | 1 |  | 1.00 | 1.00 |
| kth | polblogs.csv | 2 |  |  |  |
| kth | polblogs.csv | 4 |  |  |  |
| kth | polblogs.csv | 8 |  |  |  |
| dardel (2 nodes) | polblogs.csv | 1 | 0.002364 | 1.00 | 1.00 |
| dardel (2 nodes) | polblogs.csv | 2 | 0.003274 | 0.722008 | 0.361004 |
| dardel (2 nodes) | polblogs.csv | 4 | 0.003406 | 0.694110 | 0.173528 |
| dardel (2 nodes) | polblogs.csv | 8 | 0.003346 | 0.706557 | 0.088320 |
| dardel (2 nodes) | polblogs.csv | 16 | 0.003732 | 0.633474 | 0.039592 |

### 3.3 MPI Weak Scaling (scaled synthetic dataset)
| Platform | Dataset | Ranks | Nodes | Edges | Edges/rank | PR time (s) | Weak efficiency (= T1 / TP) | Status |
|---|---|---:|---:|---:|---:|---:|---:|---|
| kth | weak_1rank_12500_125000.csv | 1 | 12,500 | 125,000 | 125,000 | 0.003310 | 1.000000000 | PASS |
| kth | weak_2rank_25000_250000.csv | 2 | 25,000 | 250,000 | 125,000 | 0.005345 | 0.619298836 | PASS |
| kth | weak_4rank_50000_500000.csv | 4 | 50,000 | 500,000 | 125,000 | 0.007542 | 0.438951947 | PASS |
| kth | weak_8rank_100000_1000000.csv | 8 | 100,000 | 1,000,000 | 125,000 | 0.011587 | 0.285694560 | PASS |
| kth | weak_16rank_200000_2000000.csv | 16 | 200,000 | 2,000,000 | 125,000 | 0.024371 | 0.135833573 | PASS |
| dardel (2 nodes) | weak_1rank_12500_125000.csv | 1 | 12,500 | 125,000 | 125,000 | 0.003778 | 1.000000000 | PASS |
| dardel (2 nodes) | weak_2rank_25000_250000.csv | 2 | 25,000 | 250,000 | 125,000 | 0.005837 | 0.647216036 | PASS |
| dardel (2 nodes) | weak_4rank_50000_500000.csv | 4 | 50,000 | 500,000 | 125,000 | 0.006134 | 0.615898790 | PASS |
| dardel (2 nodes) | weak_8rank_100000_1000000.csv | 8 | 100,000 | 1,000,000 | 125,000 | 0.011932 | 0.316600181 | PASS |
| dardel (2 nodes) | weak_16rank_200000_2000000.csv | 16 | 200,000 | 2,000,000 | 125,000 | 0.044137 | 0.085592587 | PASS |

### 3.4 Hybrid Fixed-Core Search (P x N)
| Platform | Dataset | Total cores | (P ranks, N threads) | PR time (s) | Best? |
|---|---|---:|---|---:|---|
| colab (2 vCPU) | polblogs.csv | 2 | (1,2) | 0.003168 | best |
| colab (2 vCPU) | polblogs.csv | 2 | (2,1) | 0.005025 |  |
| colab (2 vCPU) | polblogs.csv | 4 | (1,4) | 0.023704 | oversubscribed |
| colab (2 vCPU) | polblogs.csv | 4 | (2,2) | 0.872550 | oversubscribed |
| colab (2 vCPU) | polblogs.csv | 4 | (4,1) | 0.010345 | oversubscribed |
| kth | polblogs.csv | 16 | (1,16) | 0.024310 |  |
| kth | polblogs.csv | 16 | (2,8) | 0.010850 |  |
| kth | polblogs.csv | 16 | (4,4) | 0.005325 |  |
| kth | polblogs.csv | 16 | (8,2) | 0.004281 |  |
| kth | polblogs.csv | 16 | (16,1) | 0.002907 | best |
| dardel | synthetic_100k_1m.csv | 16 | (1,16) | 0.033687 |  |
| dardel | synthetic_100k_1m.csv | 16 | (2,8) | 0.031593 |  |
| dardel | synthetic_100k_1m.csv | 16 | (4,4) | 0.033026 |  |
| dardel | synthetic_100k_1m.csv | 16 | (8,2) | 0.019036 | provisional |
| dardel | synthetic_100k_1m.csv | 16 | (16,1) | 17.275253 |  |

The Dardel hybrid rows are retained as provisional because the allocation was
created with `--cpus-per-task=1`, so Slurm emitted warnings when the hybrid job
steps requested more than one CPU per MPI rank. The school-cluster hybrid
measurements remain the main fixed-core evidence for final conclusions.

Colab provides only `2` vCPUs on a shared host (Intel Xeon @ 2.20 GHz), so it
contributes a controlled oversubscription contrast rather than a high-rank
scaling point. The `P*N = 2` rows are the meaningful measurements: `(1, 2)`
runs faster than `(2, 1)` because the within-process OpenMP path avoids the
Allreduce + Allgatherv overhead (comm fraction `1.8%` vs `77.3%`). The
`P*N = 4` rows are kept as oversubscription evidence: requesting four total
workers on two cores degrades PR time by `3.3x` for `(1, 4)`, `7.7x` for
`(4, 1)`, and catastrophically by `275x` for `(2, 2)` because two MPI ranks
each spawning two threads compete with the kernel scheduler on every barrier.
Mirror behaviour appears in the OpenMP-only column: T=4 on polblogs degrades
to `0.011389 s` (efficiency `0.082`), while the larger
`synthetic_100k_1m.csv` graph remains memory-bound enough that even
oversubscribed T=4 (`0.084794 s`) beats the noisier T=2 average (`0.128534 s`).
The Colab data therefore confirms two report claims: (a) intra-node OpenMP
beats fine-grained MPI when total workers equal physical cores, and (b) the
Hybrid model relies on `P*N <= physical_cores` to stay above the comm/sched
break-even.

### 3.5 Confirmed-Device GPU Comparison (same Small GPU server)

The GPU comparison uses `synthetic_100k_1m.csv (directed)` for all rows. GPU
target execution was required and confirmed; the Hybrid control uses the eight
CPU workers available alongside the Small GPU allocation.

| Implementation | Configuration | PR time avg (s) | Total time avg (s) | Speedup vs. serial | Device confirmed | Status |
|---|---|---:|---:|---:|---|---|
| serial | 1 CPU thread | 0.036452 | 0.036452 | 1.000000 | N/A | REFERENCE |
| gpu | naive mapping | 0.059829 | 0.257351 | 0.609268 | YES | PASS |
| gpu | persistent mapping | 0.033684 | 0.230779 | 1.082188 | YES | PASS |
| hybrid | (4,2), 8 CPU workers | 0.010364 | 0.218843 | 3.517107 | N/A | PASS |

Persistent GPU data mapping is `1.776212x` faster than the naive offload path,
while the same-server Hybrid control is `3.249995x` faster than persistent GPU
PageRank at this graph size.

### 3.6 Profiling-Guided Optimization Evidence (school-cluster CPU)

The formal optimization run uses `synthetic_100k_1m.csv (directed)` as the
main performance input. Each variant has its own `1x1` baseline for parallel
efficiency; each table row averages ten verified timed repetitions after one
warmup.

| Configuration | PR no-inv/static (s) | PR inv/dynamic (s) | Full speedup | Efficiency no-inv/static | Efficiency inv/dynamic | Efficiency delta | Status |
|---|---:|---:|---:|---:|---:|---:|---|
| `1x1` | 0.035842 | 0.032455 | 1.1043 | 1.0000 | 1.0000 | +0.0000 | PASS |
| `1x4` | 0.012826 | 0.010960 | 1.1702 | 0.6986 | 0.7403 | +0.0417 | PASS |
| `1x8` | 0.006531 | 0.006945 | 0.9403 | 0.6860 | 0.5841 | -0.1019 | PASS |
| `1x16` | 0.005576 | 0.005765 | 0.9672 | 0.4017 | 0.3518 | -0.0499 | PASS |
| `2x8` | 0.006187 | 0.005274 | 1.1732 | 0.3621 | 0.3846 | +0.0226 | PASS |
| `4x4` | 0.007609 | 0.007524 | 1.0113 | 0.2944 | 0.2696 | -0.0248 | PASS |

The controlled `skewed_100k_1m.csv` input exposes contiguous thread-load
imbalance. At `1x16`, switching from `inv_static` to `inv_dynamic` reduces
thread imbalance from `11.7988` to `1.2415` and update-kernel time from
`0.017573` s to `0.003117` s. On the regular graph, the same schedule does
not improve every end-to-end runtime, so efficiency decreases for the
thread-only `1x8` and `1x16` layouts.

---

## 4) Data Source Mapping

- Serial baseline data: `results/baseline_results.md`
- Local OpenMP scaling data: `results/scaling_local.md`
- Colab OpenMP scaling data: `results/openmp_scaling_colab.csv` (per-run logs under `results/openmp_scaling_colab/`)
- Colab Hybrid fixed-core data: `results/hybrid_fixedcore_colab_pn2_polblogs_directed.csv`, `results/hybrid_fixedcore_colab_pn4_polblogs_directed.csv` (P*N=4 oversubscribed)
- Correctness matrix (OpenMP/GPU): `results/verification_matrix.md`
- Serial hotspot context: `results/hotspot_notes.md`, `results/gprof_polblogs.txt`, `results/perf_stat_polblogs.txt`
- MPI local, KTH, and Dardel runs: `results/mpi_scaling_polblogs_directed.csv`, `results/mpi_scaling_cluster_polblogs_directed.csv`, `results/mpi_scaling_dardel_multinode_course_polblogs_directed.csv`, `results/mpi_weak_scaling_cluster_directed.csv`, `results/mpi_weak_scaling_dardel_multinode_directed.csv`
- Hybrid fixed-core runs: `mpi/profile_hybrid.sh` -> `results/hybrid_fixedcore_<platform>_<dataset>_<mode>.csv`
- School-cluster MPI/Hybrid runs: `run_mpi_cluster.sh` -> result CSV files to be generated on an MPI-enabled cluster
- Confirmed-device GPU correctness: `results/gpu_correctness_cluster_gpu.csv`
- Same-server GPU/Hybrid comparison: `results/gpu_offload_cluster_gpu_synthetic_100k_1m_directed.csv`, `results/hybrid_fixedcore_cluster_gpu_synthetic_100k_1m_directed.csv`, and `results/gpu_vs_hybrid_cluster_gpu_synthetic_100k_1m_directed.csv`
- GPU target evidence: `results/cluster_gpu_environment.log` and `results/cluster_gpu_device_probe.log`
- Formal optimization evidence: `results/optimization_ablation_cluster_optpe_synthetic_100k_1m_directed.csv`, `results/optimization_ablation_cluster_optpe_skewed_100k_1m_directed.csv`, `results/optimization_evidence_cluster.md`, `results/cluster_optimization_environment.log`, and `results/cluster_optimization_binding.log`
