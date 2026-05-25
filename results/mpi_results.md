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

Weak scaling must increase the graph size with the number of MPI ranks. The
required 16-rank experiment is now supported by removing the old 100k-node
static allocation limit in the serial, MPI, and Hybrid readers.

```bash
python3 tools/generate_graph.py --preset weak
PLATFORM=cluster GENERATE_WEAK_GRAPHS=0 REPEAT=5 ./mpi/profile_mpi_weak.sh directed "1 2 4 8 16"
PLATFORM=dardel MPI_RUNNER=srun MPI_NP_FLAG=-n REPEAT=5 ./mpi/profile_mpi_weak.sh directed "1 2 4 8 16"
```

Default weak-scaling workload:

| Ranks | Graph | Target nodes | Target edges | Nodes/rank | Edges/rank |
|-------|-------|-------------:|-------------:|-----------:|-----------:|
| 1 | `weak_1rank_12500_125000.csv` | 12,500 | 125,000 | 12,500 | 125,000 |
| 2 | `weak_2rank_25000_250000.csv` | 25,000 | 250,000 | 12,500 | 125,000 |
| 4 | `weak_4rank_50000_500000.csv` | 50,000 | 500,000 | 12,500 | 125,000 |
| 8 | `weak_8rank_100000_1000000.csv` | 100,000 | 1,000,000 | 12,500 | 125,000 |
| 16 | `weak_16rank_200000_2000000.csv` | 200,000 | 2,000,000 | 12,500 | 125,000 |

The weak-scaling script writes `results/mpi_weak_scaling_<platform>_directed.csv`
and reports weak efficiency as `T_1 / T_P`.

---

## Dardel Results

The formal Dardel scaling experiment was submitted as Slurm job `20957663` on
the `main` partition with two compute nodes, `nid001120` and `nid001121`.
For `P = 1`, the profiler ran the reference MPI case on one node; for every
`P = 2, 4, 8, 16` row it explicitly balanced ranks across both nodes and
recorded the hostnames in `results/dardel_multinode_placement.csv`. All
strong- and weak-scaling runs passed verification at tolerance `1e-6`.

The earlier `results/mpi_scaling_dardel_*` and
`results/mpi_weak_scaling_dardel_directed.csv` files are retained as
single-node shared-allocation diagnostics only. The tables below use the
multi-node formal results.

### Synthetic Strong Scaling

| Dataset | Ranks | Runs | PR time avg (s) | Comm fraction | Speedup | Efficiency | Work imbalance | Status |
|---------|-------|------|-----------------|---------------|---------|------------|----------------|--------|
| synthetic_100k_1m | 1 | 5 | 0.036330 | 0.0395 | 1.000000 | 1.000000 | 1.000 | PASS |
| synthetic_100k_1m | 2 | 5 | 0.020386 | 0.1462 | 1.782080 | 0.891040 | 1.035 | PASS |
| synthetic_100k_1m | 4 | 5 | 0.012707 | 0.3017 | 2.859025 | 0.714756 | 1.044 | PASS |
| synthetic_100k_1m | 8 | 5 | 0.012205 | 0.5257 | 2.976714 | 0.372089 | 1.047 | PASS |
| synthetic_100k_1m | 16 | 5 | 0.014107 | 0.7600 | 2.575258 | 0.160954 | 1.051 | PASS |

### Course Dataset Comparison

| Dataset | Ranks | Runs | PR time avg (s) | Comm fraction | Speedup | Efficiency | Work imbalance | Status |
|---------|-------|------|-----------------|---------------|---------|------------|----------------|--------|
| polblogs | 1 | 5 | 0.002364 | 0.0463 | 1.000000 | 1.000000 | 1.000 | PASS |
| polblogs | 2 | 5 | 0.003274 | 0.9144 | 0.722008 | 0.361004 | 1.887 | PASS |
| polblogs | 4 | 5 | 0.003406 | 0.9637 | 0.694110 | 0.173528 | 3.129 | PASS |
| polblogs | 8 | 5 | 0.003346 | 0.9805 | 0.706557 | 0.088320 | 4.412 | PASS |
| polblogs | 16 | 5 | 0.003732 | 0.9896 | 0.633474 | 0.039592 | 4.536 | PASS |

### Analysis

The multi-node experiment distinguishes useful computation from communication
overhead. The balanced synthetic graph scales to `2.98x` at `P = 8`, before
communication fraction rises to `0.7600` at `P = 16` and performance falls to
`2.58x`. The small, irregular `polblogs` graph never benefits from added
ranks: its communication fraction already reaches `0.9144` at `P = 2` and
`0.9896` at `P = 16`. Since synthetic in-edge imbalance remains at most
`1.051`, the high-rank loss is driven primarily by collectives rather than
load imbalance.

This result motivates the next optimization step: avoid full-vector synchronization every iteration, or switch to a communication-reduced graph partitioning strategy where ranks exchange only boundary contributions instead of all PageRank entries.

### Required Weak Scaling Results

Weak scaling was run with fixed per-rank work of 12,500 nodes and 125,000 edges.
The 16-rank Dardel row uses the required 200k-node / 2M-edge graph, not
`synthetic_100k_1m.csv`.

| Platform | Dataset | Ranks | Runs | PR time avg (s) | Comm fraction | Weak efficiency | Edges/rank | Work imbalance | Status |
|----------|---------|------:|-----:|----------------:|--------------:|----------------:|-----------:|---------------:|--------|
| dardel (2 nodes) | weak_1rank_12500_125000 | 1 | 5 | 0.003778 | 0.0353 | 1.000000000 | 125,000 | 1.000 | PASS |
| dardel (2 nodes) | weak_2rank_25000_250000 | 2 | 5 | 0.005837 | 0.3138 | 0.647216036 | 125,000 | 1.033 | PASS |
| dardel (2 nodes) | weak_4rank_50000_500000 | 4 | 5 | 0.006134 | 0.3398 | 0.615898790 | 125,000 | 1.044 | PASS |
| dardel (2 nodes) | weak_8rank_100000_1000000 | 8 | 5 | 0.011932 | 0.5365 | 0.316600181 | 125,000 | 1.044 | PASS |
| dardel (2 nodes) | weak_16rank_200000_2000000 | 16 | 5 | 0.044137 | 0.5960 | 0.085592587 | 125,000 | 1.051 | PASS |
| cluster | weak_1rank_12500_125000 | 1 | 5 | 0.003310 | 0.0123 | 1.000000000 | 125,000 | 1.000 | PASS |
| cluster | weak_2rank_25000_250000 | 2 | 5 | 0.005345 | 0.2442 | 0.619298836 | 125,000 | 1.033 | PASS |
| cluster | weak_4rank_50000_500000 | 4 | 5 | 0.007542 | 0.4821 | 0.438951947 | 125,000 | 1.044 | PASS |
| cluster | weak_8rank_100000_1000000 | 8 | 5 | 0.011587 | 0.5887 | 0.285694560 | 125,000 | 1.044 | PASS |
| cluster | weak_16rank_200000_2000000 | 16 | 5 | 0.024371 | 0.6814 | 0.135833573 | 125,000 | 1.051 | PASS |

The multi-node weak-scaling efficiency declines for the same reason as the
high-rank strong-scaling result: even though the per-rank edge count remains
fixed, each iteration communicates a growing global PageRank vector. For the
16-rank case, `MPI_Allgatherv` alone averages `0.020449` s out of `0.044137`
s PR time. The measured communication fraction is `59.60%`, while the work
imbalance remains only `1.051`.

On the school cluster the same reproducibly generated graphs scale more
smoothly, but communication still becomes dominant: weak efficiency falls to
0.135834 and communication reaches 68.14% at 16 ranks. The Dardel and cluster
rows use identical graph instances, as confirmed by equal per-rank in-edge
work distributions for each rank count.

---

## Figure Pipeline

After running `mpi/profile_mpi.sh` or a cluster job, generate figures with:

```bash
python3 tools/plot_mpi_results.py results/mpi_scaling_<name>.csv --out-dir results/figures
```

Formal Dardel multi-node figures:

- `results/figures/dardel_multinode_strong/mpi_speedup.png`
- `results/figures/dardel_multinode_strong/mpi_runtime_breakdown.png`
- `results/figures/dardel_multinode_weak/mpi_weak_efficiency.png`

School-cluster comparison figure:

- `results/figures/cluster_weak/mpi_weak_efficiency.png`

These plots were regenerated from the formal Dardel multi-node and
school-cluster CSV files after the final reproducible weak-scaling runs.

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
- [x] Single-node Dardel diagnostics retained separately from formal tables.
- [x] Multi-node Dardel strong/weak measurements, with hostname placement evidence.
- [x] Final school-cluster MPI strong/weak measurements.
- [x] Final Hybrid fixed-core measurements on the school cluster.
- [x] Replace local smoke-test figures with Dardel figures.
