# Serial PageRank - Quantitative Analysis

Generated from `results/baseline_results.md`, `results/perf_stat_polblogs_*.txt` and the large-graph profiling files under `results/`.

Turns the raw W1 baseline into per-edge throughput, an arithmetic-intensity view, a cache-residency table, microarchitecture deltas and an Amdahl ceiling. These are the references the parallel implementations (W2 OpenMP, W3 MPI, W4 Hybrid, W5 optimization, W6 GPU) are compared against.

---

## 1. Per-edge throughput (MEdges/s)

`MEdges/s = iters * edges / PR_time / 1e6`. A memory-bound kernel shows a roughly *dataset-independent* per-edge rate on a given platform - the value is therefore the right per-core ceiling to compare parallel runs against.

| Dataset | Mode | N | M | Iters | Colab MEdges/s | KTH MEdges/s | Dardel MEdges/s |
|---|---|---:|---:|---:|---:|---:|---:|
| polblogs | directed | 1224 | 19090 | 108 | 118.5 | 859.4 | 597.3 |
| karateDir | directed | 34 | 78 | 22 | 171.6 | 572.0 | 343.2 |
| lesmisDir | directed | 77 | 254 | 36 | 277.1 | 653.1 | 481.3 |
| dolphinsDir | directed | 62 | 159 | 29 | 184.4 | 461.1 | 419.2 |
| NCAA_football | directed | 570 | 1537 | 24 | 209.6 | 576.4 | 434.0 |
| dolphins | undirected | 62 | 636 | 86 | 369.6 | 882.2 | 614.6 |
| karate | undirected | 34 | 312 | 60 | 425.5 | 850.9 | 603.9 |
| lesmis | undirected | 77 | 1016 | 76 | 443.8 | 721.6 | 632.9 |
| stateborders | undirected | 51 | 428 | 90 | 337.9 | 856.0 | 601.9 |

_Use as the speedup denominator: any parallel implementation should be compared by `MEdges/s_parallel / MEdges/s_serial` on the same platform._

## 2. Roofline / arithmetic intensity

Hot inner loop `s += pr[u] * inv_out_degree[u]`:

- FLOPs per edge: **2** (1 mul + 1 add)
- Bytes per edge: **20** (`col_idx` 4 B + `pr[u]` 8 B random + `inv_out_degree[u]` 8 B random)
- Arithmetic intensity: **0.100 FLOP/Byte**

Modern CPU ridge point is roughly 5-10 FLOP/Byte, so this kernel sits deep in the **memory-bound** region of the roofline.

**Optimization implication**: budget should go to reducing memory traffic and improving cache reuse (NUMA pinning, neighbour reordering, blocking, prefetch) - *not* to arithmetic vectorization or unrolling.

## 3. Working-set vs cache hierarchy

Hot data per iteration: `3*N*8 B (pr/pr_new/inv_deg) + 2*N*4 B (row_ptr/out_deg) + M*4 B (col_idx)`.

| Dataset | N | M | Working set | Likely resident |
|---|---:|---:|---:|---|
| polblogs | 1224 | 19090 | 112.8 KB | L2 (~1 MB) |
| karateDir | 34 | 78 | 1.4 KB | L1 (~32 KB) |
| lesmisDir | 77 | 254 | 3.4 KB | L1 (~32 KB) |
| dolphinsDir | 62 | 159 | 2.6 KB | L1 (~32 KB) |
| NCAA_football | 570 | 1537 | 23.8 KB | L1 (~32 KB) |
| dolphins | 62 | 636 | 4.4 KB | L1 (~32 KB) |
| karate | 34 | 312 | 2.3 KB | L1 (~32 KB) |
| lesmis | 77 | 1016 | 6.4 KB | L1 (~32 KB) |
| stateborders | 51 | 428 | 3.3 KB | L1 (~32 KB) |

**Caveat**: all course-provided datasets fit comfortably in L1/L2. The per-edge throughput table above is therefore **cache-resident** speed, *not* the DRAM-bandwidth ceiling. A larger graph (e.g. web-Stanford ~280k nodes, or a synthetic ER/Barabasi at >10 MB working set) is needed to expose the real ceiling for parallel scaling.

## 4. Microarchitecture comparison (perf stat, polblogs)

| Platform | CPU | Eff. GHz | IPC | L1 miss / kinstr | Cache-miss / ref | Scope |
|---|---|---:|---:|---:|---:|---|
| Colab | Intel Xeon @ 2.20GHz | - | - | - | - | _no perf data_ |
| KTH | Intel Xeon Platinum 8480C | 3.76 | 3.31 | 2.1 | 64.66% | all (kernel+user) |
| Dardel | AMD EPYC 7742 | 1.84 | 2.67 | 12.4 | 0.03% | user-only (:u) |

**Reading the table**

- IPC > 2 on all platforms with measured data -> no front-end stall; back-end (memory) stalls dominate, consistent with the roofline view.
- L1-miss-per-kinstr difference between KTH and Dardel is the main reason single-core wall times differ more than frequency alone explains.
- KTH and Dardel perf were collected with **different counter scopes** (see *Scope* column). For an apples-to-apples comparison both should be re-collected with the same `:u` setting. Sub-1% impact on IPC for a user-space dominated benchmark like this, but worth fixing before the final report.

_Sanity check (polblogs on KTH): kernel touches ~43.3 MB total -> effective bandwidth **18.07 GB/s** (vs ~300 GB/s DDR5 peak per socket on the 8480C - far below peak because the access pattern is random-read into `pr[u]`)._

## 5. Amdahl serial-residual (polblogs)

Wall-clock = `load_csv + PR + save_results`. W2-W4 only parallelise the PR kernel. The PR fraction therefore caps the wall-clock speedup.

| Platform | Load (s) | PR (s) | PR fraction | Amdahl ceiling (PR-only parallel) |
|---|---:|---:|---:|---:|
| Colab | 0.0211 | 0.0174 | 45.2% | 1.82x |
| KTH | 0.0016 | 0.0024 | 60.0% | 2.50x |
| Dardel | 0.0108 | 0.0035 | 24.2% | 1.32x |

**Implication**: on the polblogs-sized graphs the load fraction caps wall-clock speedup well below the per-kernel speedup. Report `speedup_PR` (kernel-only) and `speedup_wall` (end-to-end) separately. A larger graph drops `load fraction` below 5% and decouples the two.

## 6. Large-graph serial validation

The synthetic large graph uses the same CSV format as the course datasets, but increases the hot working set to **10.68 MiB**. It is generated by `scripts/generate_large_graph.py` with 100000 nodes, 2000000 directed edges and seed 26. The generator first creates a directed ring so every node is present with nonzero degree, then adds reproducible random and hub-biased edges to create mild degree skew.

| Dataset | Mode | N | M | Iters | Colab PR(s) | KTH PR(s) | Dardel PR(s) |
|---|---|---:|---:|---:|---:|---:|---:|
| synthetic_large_directed | directed | 100000 | 2000000 | 16 | 0.156453 | 0.040141 | 0.089340 |

| Platform | MEdges/s | Speedup vs Colab |
|---|---:|---:|
| Colab | 204.5 | 1.00x |
| KTH | 797.2 | 3.90x |
| Dardel | 358.2 | 1.75x |

This is the better denominator for scalability experiments because each PageRank run touches `2,000,000 * 16 = 32M` directed edge visits. The course graphs remain the correctness suite; the large graph is the performance suite.

## 7. Large-graph gprof hotspot summary

| Platform | pagerank | load_csv | sht_get_or_insert | iv_push | Notes |
|---|---:|---:|---:|---:|---|
| Colab | 92.27% | 4.00% | 3.47% | 0.27% | `pagerank` still dominates despite larger CSV load |
| KTH | 87.50% | 4.55% | 6.82% | 1.14% | Faster kernel; hash insertion visible during one-time load |
| Dardel | 90.87% | 2.17% | 5.22% | 0.87% | `rp_cmp` appears at 0.87% from Top-10 sorting |

**Reading**: the large graph does not move the hotspot away from the PageRank kernel. CSV parsing and node-name hashing become measurable because the graph has 2M edges, but they are one-time setup costs. Optimizing `load_csv` would not improve iterative PageRank scaling.

## 8. Large-graph perf stat summary

| Platform | Eff. GHz | IPC | L1 miss / kinstr | Cache-miss / ref | LLC misses | Scope |
|---|---:|---:|---:|---:|---:|---|
| Colab | - | - | - | - | - | `perf` not available |
| KTH | 3.79 | 1.67 | 168.5 | 1.382% | 513608 | all (kernel+user) |
| Dardel | 1.90 | 1.67 | 185.1 | 71.352% | not supported | user-only (:u) |

**Reading**

- IPC drops from the small-graph values (KTH `3.31`, Dardel `2.67`) to about `1.67` on the large graph. This is the expected sign that the benchmark is no longer just a cache-resident tiny workload.
- L1 misses per thousand instructions rise sharply on the large graph, consistent with random reads of `pr[u]` and `inv_out_degree[u]` in the incoming-edge loop.
- KTH and Dardel cache counters should not be compared only by `cache-miss / ref`: the event scope and hardware event definitions differ. The robust cross-platform conclusion is the lower IPC plus high L1 miss pressure on both measured systems.
- Colab cannot provide perf counters in the current environment, so Colab contributes timing and gprof hotspot data only.

**Optimization implication**: the large-graph data strengthens the memory-bound conclusion. Next optimizations should target memory traffic and locality: precompute per-node contribution (`contrib[u] = pr[u] * inv_out_degree[u]`), graph/node reordering, better cache reuse, NUMA/thread pinning for parallel runs, and reduced MPI synchronization.

## 9. Noise floor (5-run spread on polblogs)

| Platform | Min (s) | Max (s) | Avg (s) | Spread (Max-Min)/Avg |
|---|---:|---:|---:|---:|
| Colab | 0.024317 | 0.041574 | 0.032609 | 52.9% |
| KTH | 0.005651 | 0.007096 | 0.006052 | 23.9% |
| Dardel | 0.011150 | 0.011631 | 0.011346 | 4.2% |

_Treat parallel speedups below ~2x the platform's spread as noise, not signal. Quote both mean and (min, max) when reporting scaling._

---

## What this enables in W2-W6

| Asset | Used by |
|---|---|
| Per-edge MEdges/s (sec.1)     | Speedup denominator for OpenMP/MPI/Hybrid/GPU |
| Arithmetic intensity (sec.2)  | Justifies optimization picks in W5 |
| Working-set table (sec.3)     | Decides which datasets need a larger graph |
| Microarch deltas (sec.4)      | Explains non-linear speedup across platforms |
| Amdahl ceiling (sec.5)        | Sets upper bound for wall-clock speedup |
| Large-graph validation (sec.6-8) | Performance baseline and memory-bound evidence |
| Noise floor (sec.9)           | Significance threshold for scaling plots |

## Sources

- Baseline timings: `results/baseline_results.md`
- Colab perf:  `results/perf_stat_polblogs_colab.txt`
- KTH perf:  `results/perf_stat_polblogs_kth.txt`
- Dardel perf:  `results/perf_stat_polblogs_dardel.txt`
- Large graph timings: `results/scaling_large_colab.md`, `results/scaling_large_kth.md`, `results/scaling_large_dardel.md`
- Large graph gprof: `results/gprof_large_colab.txt`, `results/gprof_large_kth.txt`, `results/gprof_large_dardel.txt`
- Large graph perf: `results/perf_stat_large_colab.txt`, `results/perf_stat_large_kth.txt`, `results/perf_stat_large_dardel.txt`

Small-graph sections can be regenerated with: `python3 scripts/analyze_serial.py`. Large-graph sections are summarized from the platform-specific profiling files listed above.
