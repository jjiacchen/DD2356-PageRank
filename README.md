# DD2356 Final Project – High-Performance PageRank
**Group 26**

## Structure
- `serial/`  – Serial C baseline + profiling scripts 
- `openmp/`  – OpenMP CPU implementation + OpenMP target offload prototype
- `mpi/`     – MPI and Hybrid MPI+OpenMP implementations
- `verify/`  – Correctness verification framework 
- `data/`    – Course-provided graph datasets
- `scripts/` – Build, reference generation, profiling, scaling and verification helpers
- `references/` – Golden serial outputs for all datasets
- `tools/`   – Local synthetic graph generation and MPI result plotting helpers

## Build & Run
```bash
gcc -O2 -o serial/pagerank_serial serial/pagerank_serial.c -lm
./serial/pagerank_serial data/polblogs.csv directed
./serial/pagerank_serial data/dolphins.csv undirected
```

## MPI Build & Run
```bash
mpicc -O2 -o mpi/pagerank_mpi mpi/pagerank_mpi.c -lm
mpirun -np 4 ./mpi/pagerank_mpi data/polblogs.csv directed
```

## MPI Scaling Profile
```bash
./mpi/profile_mpi.sh data/polblogs.csv directed "1 2 4 8"
```

The MPI profiler builds serial/MPI/verifier binaries, generates the serial golden output, runs each MPI rank count, verifies correctness, and writes `results/mpi_scaling_*.csv`.

Useful options:
```bash
REPEAT=5 ./mpi/profile_mpi.sh data/polblogs.csv directed "1 2 4 8"
MPI_RUNNER=srun MPI_NP_FLAG=-n ./mpi/profile_mpi.sh data/polblogs.csv directed "1 2 4"
```

## Wang MPI Workflow Before Cluster Runs
```bash
# 1. Check correctness across all course datasets
./mpi/test_mpi_all.sh

# 2. Generate larger synthetic graphs for meaningful scaling
python3 tools/generate_graph.py --preset all

# 3. Run a local or cluster scaling profile
REPEAT=3 ./mpi/profile_mpi.sh data/synthetic/synthetic_10k_100k.csv directed "1 2 4"

# 4. Generate result figures from summary CSV files
python3 tools/plot_mpi_results.py results/mpi_scaling_synthetic_10k_100k_directed.csv --out-dir results/figures
```

The plotting script requires Pillow. If the default Python does not have it, use the bundled Codex runtime Python shown by the app or run the plotting step on a machine with Pillow installed.

## Cluster Submission
```bash
# Generic SLURM
sbatch run_mpi.sh

# Dardel
GRAPH=data/synthetic/synthetic_100k_1m.csv MODE=directed RANKS="1 2 4 8 16 32" sbatch run_mpi_dardel.sh

# School cluster
GRAPH=data/synthetic/synthetic_100k_1m.csv MODE=directed RANKS="1 2 4 8 16 32" sbatch run_mpi_cluster.sh
```

If the cluster requires modules, pass them explicitly:
```bash
MODULES="gcc openmpi" sbatch run_mpi_cluster.sh
```

## Correctness Verification
```bash
gcc -O2 -o verify/verify verify/verify_correctness.c -lm
./verify/verify pagerank_serial_output.txt pagerank_parallel_output.txt
```

## One-command Workflow
```bash
./scripts/build_all.sh
./scripts/generate_references.sh
./scripts/profile_hotspots.sh
./scripts/run_verify_suite.sh
./scripts/run_scaling_local.sh
```

## Large-Graph Performance Dataset
The course graphs stay as the default correctness suite. For scalability
experiments, generate a deterministic large directed graph:

```bash
./scripts/generate_large_graph.py
./scripts/run_scaling_large.sh
```

For a serial-only baseline on any platform, disable the OpenMP section:

```bash
RUN_OPENMP=0 ./scripts/run_scaling_large.sh
```

Default large graph: `100000` nodes, `2000000` directed edges, written to
`data/synthetic_large_directed.csv`. The estimated PageRank hot working set is
about `10.68 MiB`, so it exercises cache/DRAM behavior better than the small
course graphs. Run the large-graph scaling script on Colab, KTH and Dardel for
platform comparisons. Generated large CSV/reference/result files are ignored by git.

## MPI / Hybrid (cluster)
```bash
mpirun -np 4 mpi/pagerank_mpi data/polblogs.csv directed
OMP_NUM_THREADS=4 mpirun -np 2 mpi/pagerank_hybrid data/polblogs.csv directed 4
```
