# A-Level Requirement Audit

This audit compares the project evidence currently present in the repository
against the submitted proposal and the A-level task table. It is deliberately
strict: a working implementation is not counted as complete when the required
platform experiment or report evidence is missing.

## Proposal Commitments

The submitted proposal commits the group to:

- Serial baseline verification and profiling on all three systems.
- OpenMP scalability and overhead evaluation.
- MPI decomposition and communication analysis with strong/weak scaling.
- Hybrid MPI+OpenMP tuning under fixed total cores.
- At least two profiling-guided optimizations and an OpenMP GPU-offloading
  comparison against MPI+OpenMP.

It explicitly states that strong scaling uses multi-node MPI experiments on
Dardel and multi-rank experiments on the school cluster.

## Validated MPI Weak-Scaling Data

The final school-cluster and Dardel multi-node weak-scaling CSVs are valid for
reporting. Dardel job `20957663` ran on `main` with `nid001120` and
`nid001121`; every `P >= 2` step records both hosts.

| Platform | Ranks | Nodes | Edges | Edges/rank | PR time avg (s) | Comm fraction | Weak efficiency | Status |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| KTH cluster | 1 | 12,500 | 125,000 | 125,000 | 0.003310 | 0.0123 | 1.000000000 | PASS |
| KTH cluster | 2 | 25,000 | 250,000 | 125,000 | 0.005345 | 0.2442 | 0.619298836 | PASS |
| KTH cluster | 4 | 50,000 | 500,000 | 125,000 | 0.007542 | 0.4821 | 0.438951947 | PASS |
| KTH cluster | 8 | 100,000 | 1,000,000 | 125,000 | 0.011587 | 0.5887 | 0.285694560 | PASS |
| KTH cluster | 16 | 200,000 | 2,000,000 | 125,000 | 0.024371 | 0.6814 | 0.135833573 | PASS |
| Dardel (2 nodes) | 1 | 12,500 | 125,000 | 125,000 | 0.003778 | 0.0353 | 1.000000000 | PASS |
| Dardel (2 nodes) | 2 | 25,000 | 250,000 | 125,000 | 0.005837 | 0.3138 | 0.647216036 | PASS |
| Dardel (2 nodes) | 4 | 50,000 | 500,000 | 125,000 | 0.006134 | 0.3398 | 0.615898790 | PASS |
| Dardel (2 nodes) | 8 | 100,000 | 1,000,000 | 125,000 | 0.011932 | 0.5365 | 0.316600181 | PASS |
| Dardel (2 nodes) | 16 | 200,000 | 2,000,000 | 125,000 | 0.044137 | 0.5960 | 0.085592587 | PASS |

Validation checks:

- All five rank counts passed against the serial reference at tolerance
  `1e-6`.
- The required 16-rank case uses `weak_16rank_200000_2000000`.
- Dardel and KTH use the same regenerated graph instances: for every rank
  count, the reported minimum/average/maximum in-edge workloads are identical.
- Dardel `results/dardel_multinode_placement.csv` proves that the measured
  strong and weak cases at `P = 2, 4, 8, 16` execute across two compute nodes.
- The weak trend is internally consistent: constant edges per rank with
  increasing collective-communication fraction and decreasing efficiency.

## Evidence Matrix

| A-level requirement | Current evidence | Status | Missing evidence or action |
|---|---|---|---|
| Serial implementation and correctness | `serial/pagerank_serial.c`, `results/baseline_results.md` | Complete | None identified for this requirement. |
| Baseline profiling on 3 systems | Colab/KTH/Dardel timings and metrics in `results/baseline_results.md` and `results/serial_analysis.md` | Complete | Keep platform definitions consistent in final integrated report. |
| Approximate upper bound of speedup | Amdahl ceilings in `results/serial_analysis.md` | Complete | None identified. |
| OpenMP implementation and correctness | `openmp/pagerank_openmp.c`, `results/verification_matrix.md` | Complete in implementation | None for correctness. |
| OpenMP speedup and performance-metric comparison on 3 systems | Only local OpenMP scaling is recorded in `results/scaling_local.md`; Colab/KTH/Dardel table cells remain empty in `results/platform_comparison_master.md` | Missing | Run OpenMP scaling versus same-platform serial on Colab, KTH cluster, and Dardel; add overhead/scalability analysis. |
| MPI decomposition and communication model | `mpi/pagerank_mpi.c`, timing breakdown and model in `results/mpi_results.md` / `wang_report_section.tex` | Complete | None identified for implementation/model. |
| MPI strong and weak scaling on school cluster | Strong CSVs plus final reproducible weak CSV including 16 ranks | Complete | None identified for the measured 1--16 rank sequence. |
| MPI strong and weak scaling on multiple Dardel compute nodes | `main` job `20957663`; verified multi-node strong/weak CSVs plus `results/dardel_multinode_placement.csv` for `nid001120;nid001121` | Complete | None identified for the measured 1--16 rank sequence. |
| Hybrid MPI+OpenMP implementation and correctness | `mpi/pagerank_hybrid.c`, fixed-core CSVs, PASS verification | Complete in implementation | None for correctness. |
| Hybrid overhead analysis and best `(P,N)` on school cluster for a few total-core values | Fixed-total-16 sweeps exist for two datasets; report analyzes MPI communication | Partial | Run at least two additional total-worker budgets, e.g. 4 and 8 (or 8 and 32 if allocated), and explicitly model thread overhead plus MPI overhead. |
| Two profiling-guided optimizations | Reciprocal out-degree and dynamic scheduling; cluster ablation CSVs show before/after PR time | Partial to strong | Add selected before/after communication and parallel-efficiency evidence to the final integrated report. |
| OpenMP GPU offloading correctness and comparison with MPI+OpenMP | Prototype and correctness matrix exist; current GPU timing is local while Hybrid timing is from KTH | Partial | Confirm actual device execution and run GPU versus Hybrid comparison on a comparable platform/dataset. |
| Strong-scaling and weak-scaling report sections | Wang section includes KTH and formal multi-node Dardel MPI tables, placement evidence, and analysis | Complete for Wang's MPI scaling scope | None identified for MPI scaling. |

## Required Remaining Experiments for A-Level Evidence

High priority:

1. OpenMP speedup measurements on all three stated systems, with comparison to
   the serial baseline and a short overhead analysis (Minyi Zhu's scope).
2. Hybrid fixed-core search at multiple total-worker budgets on the school
   cluster, beyond the existing `P*N=16` sweep (Minyi Zhu's scope).

Before submission:

3. Add before/after parallel-efficiency metrics for the two optimizations.
4. Replace the current cross-platform GPU/Hybrid timing comparison with
   same-platform evidence and confirm that the target region actually runs on a
   GPU device rather than CPU fallback (Pengyu Wang's remaining scope).

## Current Reporting Caution

The formal Dardel MPI tables now refer to the two-node `main` job `20957663`
and satisfy the proposal's multi-node measurement wording for the measured
`1, 2, 4, 8, 16` rank sequence. Earlier single-node shared-allocation CSVs
remain useful diagnostics, but must remain clearly labeled as such.
