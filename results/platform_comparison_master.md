# Platform Comparison Master Table

Use this file as the single source of truth for cross-platform performance comparison.

Platforms:
- `local` (this machine / WSL)
- `colab`
- `kth`
- `dardel`

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
| openmp | colab | threads=? |  |  |  |  |  |
| openmp | kth | threads=? |  |  |  |  |  |
| openmp | dardel | threads=? |  |  |  |  |  |
| mpi | local | ranks=4 | 0.0010 | 0.004730 | 108 | 0.41 | 0.10 |
| mpi | colab | ranks=? |  |  |  |  |  |
| mpi | kth | ranks=? |  |  |  |  |  |
| mpi | dardel | ranks=16 | 0.0108 | 14.060021 | 108 | 0.000246 | 0.000015 |
| hybrid | local | ranks=? x threads=? |  |  |  |  |  |
| hybrid | colab | ranks=? x threads=? |  |  |  |  |  |
| hybrid | kth | ranks=? x threads=? |  |  |  |  |  |
| hybrid | dardel | ranks=? x threads=? |  |  |  |  |  |
| gpu | local | omp-target | 0.0027 | 0.053566 | 108 | 0.04 | N/A |
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
| polblogs.csv | directed | local | gpu | omp-target | 1224 | 19090 | 0.053566 | 108 | 1.0000000000 | PASS |
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
| kth | polblogs.csv | 1 |  | 1.00 | 1.00 |
| kth | polblogs.csv | 2 |  |  |  |
| kth | polblogs.csv | 4 |  |  |  |
| kth | polblogs.csv | 8 |  |  |  |
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
| dardel | polblogs.csv | 1 | 0.003410 | 1.00 | 1.00 |
| dardel | polblogs.csv | 2 | 7.930667 | 0.000430 | 0.000215 |
| dardel | polblogs.csv | 4 | 7.924683 | 0.000430 | 0.000108 |
| dardel | polblogs.csv | 8 | 10.368678 | 0.000329 | 0.000041 |
| dardel | polblogs.csv | 16 | 14.060021 | 0.000243 | 0.000015 |

### 3.3 Hybrid Fixed-Core Search (P x N)
| Platform | Dataset | Total cores | (P ranks, N threads) | PR time (s) | Best? |
|---|---|---:|---|---:|---|
| kth | polblogs.csv | 16 | (1,16) |  |  |
| kth | polblogs.csv | 16 | (2,8) |  |  |
| kth | polblogs.csv | 16 | (4,4) |  |  |
| kth | polblogs.csv | 16 | (8,2) |  |  |
| kth | polblogs.csv | 16 | (16,1) |  |  |
| dardel | polblogs.csv | 16 | (1,16) |  |  |
| dardel | polblogs.csv | 16 | (2,8) |  |  |
| dardel | polblogs.csv | 16 | (4,4) |  |  |
| dardel | polblogs.csv | 16 | (8,2) |  |  |
| dardel | polblogs.csv | 16 | (16,1) |  |  |

---

## 4) Data Source Mapping

- Serial baseline data: `results/baseline_results.md`
- Local OpenMP scaling data: `results/scaling_local.md`
- Correctness matrix (OpenMP/GPU): `results/verification_matrix.md`
- Serial hotspot context: `results/hotspot_notes.md`, `results/gprof_polblogs.txt`, `results/perf_stat_polblogs.txt`
- MPI local and Dardel runs: `results/mpi_scaling_polblogs_directed.csv`, `results/mpi_scaling_dardel_course_polblogs_directed.csv`
- Hybrid fixed-core runs: `mpi/profile_hybrid.sh` -> `results/hybrid_fixedcore_<dataset>_<mode>.csv`
- School-cluster MPI/Hybrid runs: `run_mpi_cluster.sh` -> result CSV files to be generated on an MPI-enabled cluster
