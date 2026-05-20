# MPI PageRank Results and Analysis
**DD2356 Group 26 - Pengyu Wang**

---

## Scope

Pengyu Wang's part focuses on the MPI implementation, communication analysis, cluster scaling experiments, and the data/figure pipeline needed before running on Dardel and the school cluster.

The current implementation is a first distributed-memory baseline. It is intentionally conservative: each rank loads the same graph, while the PageRank update is decomposed across ranks by destination node ranges. This makes correctness easy to verify and exposes the main MPI communication bottleneck before moving to more complex distributed graph storage.

---

## MPI Decomposition Strategy

The graph is stored in CSR format by incoming edges, inherited from the serial baseline:

```text
row_ptr[v]..row_ptr[v+1]-1 gives all incoming sources u for node v
```

The MPI version uses contiguous node-block decomposition:

```text
rank r computes v in [start_r, end_r)
```

Each rank keeps:

- The full CSR graph.
- The full current PageRank vector `pr`.
- A local block of newly computed entries `pr_new[start_r:end_r]`.

At every iteration:

1. Each rank computes dangling mass from its local node block.
2. `MPI_Allreduce` sums the global dangling mass.
3. Each rank computes PageRank updates for its local destination nodes.
4. Each rank computes local L1 convergence difference.
5. `MPI_Allreduce` sums the global L1 difference.
6. `MPI_Allgatherv` assembles the next full PageRank vector on all ranks.

Only rank 0 prints the top-k output and saves the candidate vector for correctness checking.

---

## Communication and Scalability Model

For each iteration with `P` MPI ranks, `N` nodes, and `M` edges:

- Local computation is approximately `O(M/P)` if in-edge workload is balanced.
- Dangling mass synchronization costs one scalar `MPI_Allreduce`.
- Convergence synchronization costs one scalar `MPI_Allreduce`.
- PageRank vector synchronization costs one `MPI_Allgatherv` of `N` doubles.

A simple model is:

```text
T_iter(P) ~= T_compute(M/P) + 2*T_allreduce_scalar(P) + T_allgatherv_vector(N,P)
```

Expected behavior:

- Small graphs may have negative scaling because collective latency is larger than useful local computation.
- Larger synthetic graphs should improve the compute/communication ratio.
- Contiguous node blocks may have in-edge load imbalance, so the MPI code reports min/avg/max local in-edge workload and `max/avg` imbalance.

The implementation now reports:

- Total PageRank time.
- Total communication time.
- Dangling `Allreduce` time.
- Diff `Allreduce` time.
- `Allgatherv` time.
- Node and in-edge workload balance across ranks.

---

## Correctness Methodology

Correctness is checked against the serial baseline:

1. Run `serial/pagerank_serial` to produce `pagerank_serial_output.txt`.
2. Run `mpi/pagerank_mpi` to produce a candidate output.
3. Run `verify/verify` with tolerance `1e-6`.

The automated script runs this across all course datasets:

```bash
./mpi/test_mpi_all.sh
```

It writes:

```text
results/mpi_correctness_summary.csv
```

The pre-cluster local smoke tests passed on:

| Dataset | Mode | Ranks | Result |
|---------|------|-------|--------|
| polblogs | directed | 1, 2, 4 | PASS |
| NCAA_football | directed | 4 | PASS |
| dolphins | undirected | 4 | PASS |

---

## Experiment Plan for Dardel and School Cluster

### Strong Scaling

Fixed graph, increasing MPI ranks:

```bash
GRAPH=data/polblogs.csv MODE=directed RANKS="1 2 4 8 16 32" sbatch run_mpi_dardel.sh
```

For a more meaningful scaling curve, use synthetic larger graphs:

```bash
python3 tools/generate_graph.py --preset all
GRAPH=data/synthetic/synthetic_100k_1m.csv MODE=directed RANKS="1 2 4 8 16 32" sbatch run_mpi_dardel.sh
```

### Weak Scaling

Use one graph size per approximate process count:

| Ranks | Suggested graph |
|-------|-----------------|
| 1 | `data/synthetic/synthetic_10k_100k.csv` |
| 4 | `data/synthetic/synthetic_50k_500k.csv` |
| 8 or 16 | `data/synthetic/synthetic_100k_1m.csv` |

Set `SCALING_MODE=weak` when submitting weak-scaling runs so the CSV and figures are labeled correctly.

---

## Dardel Results

Dardel experiments were run on one shared node with `salloc -t 03:00:00 -A edu26.DD2356 -p shared --nodes=1 --ntasks=16 --cpus-per-task=1`. Correctness passed for all 9 course datasets with `P = 1, 2, 4, 8, 16` MPI ranks and tolerance `1e-6`.

### Synthetic Strong Scaling

| Dataset | Ranks | Runs | PR time avg (s) | Comm fraction | Speedup | Efficiency | Work imbalance | Status |
|---------|-------|------|-----------------|---------------|---------|------------|----------------|--------|
| synthetic_100k_1m | 1 | 5 | 0.034357 | 0.0146 | 1.000000 | 1.000000 | 1.000 | PASS |
| synthetic_100k_1m | 2 | 5 | 8.728022 | 0.9963 | 0.003936 | 0.001968 | 1.035 | PASS |
| synthetic_100k_1m | 4 | 5 | 12.569529 | 0.9985 | 0.002733 | 0.000683 | 1.044 | PASS |
| synthetic_100k_1m | 8 | 5 | 12.952756 | 0.9992 | 0.002653 | 0.000332 | 1.047 | PASS |
| synthetic_100k_1m | 16 | 5 | 18.218429 | 0.9996 | 0.001886 | 0.000118 | 1.051 | PASS |

### Course Dataset Comparison

| Dataset | Ranks | Runs | PR time avg (s) | Comm fraction | Speedup | Efficiency | Work imbalance | Status |
|---------|-------|------|-----------------|---------------|---------|------------|----------------|--------|
| polblogs | 1 | 5 | 0.003410 | 0.0305 | 1.000000 | 1.000000 | 1.000 | PASS |
| polblogs | 2 | 5 | 7.930667 | 0.9996 | 0.000430 | 0.000215 | 1.887 | PASS |
| polblogs | 4 | 5 | 7.924683 | 0.9998 | 0.000430 | 0.000108 | 3.129 | PASS |
| polblogs | 8 | 5 | 10.368678 | 1.0000 | 0.000329 | 0.000041 | 4.412 | PASS |
| polblogs | 16 | 5 | 14.060021 | 1.0000 | 0.000243 | 0.000015 | 4.536 | PASS |

### Analysis

The current replicated-vector MPI strategy is correct but does not scale on this Dardel shared-node run. At `P > 1`, almost all PageRank time is spent in collective communication, especially the full-vector `MPI_Allgatherv` and synchronization waits inside scalar reductions. The synthetic graph has balanced node blocks and only mild in-edge imbalance (`max/avg` around 1.05), so the dominant bottleneck is communication rather than computational load imbalance. The course graph `polblogs` is both smaller and more imbalanced, which makes the communication overhead even more visible.

This result motivates the next optimization step: avoid full-vector synchronization every iteration, or switch to a communication-reduced graph partitioning strategy where ranks exchange only boundary contributions instead of all PageRank entries.

---

## Figure Pipeline

After running `mpi/profile_mpi.sh` or a cluster job, generate figures with:

```bash
python3 tools/plot_mpi_results.py results/mpi_scaling_<name>.csv --out-dir results/figures
```

Generated figures:

- `results/figures/mpi_speedup.png`
- `results/figures/mpi_efficiency.png`
- `results/figures/mpi_runtime_breakdown.png`
- `results/figures/mpi_comm_fraction.png`
- `results/figures/mpi_workload_balance.png`

These plots were regenerated from the Dardel CSV files after the run.

---

## Pre-Dardel Checklist

- [x] MPI implementation with node-block decomposition.
- [x] Correctness automation for all course datasets.
- [x] Profiling automation with repeat runs and summary CSVs.
- [x] Communication timing split by collective operation.
- [x] Workload-balance statistics.
- [x] Synthetic graph generator.
- [x] Dardel and school-cluster submission scripts.
- [x] Plotting pipeline for speedup, efficiency, runtime breakdown, communication fraction, and workload balance.
- [x] Hybrid fixed-core profiling script.
- [x] Final Dardel measurements.
- [ ] Final school-cluster measurements.
- [ ] Final Hybrid fixed-core measurements on Dardel or school cluster.
- [x] Replace local smoke-test figures with Dardel figures.
