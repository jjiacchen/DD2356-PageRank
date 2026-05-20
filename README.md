# DD2356 Final Project – High-Performance PageRank
**Group 26**

## Structure
- `serial/`  – Serial C baseline + profiling scripts 
- `mpi/`     – MPI PageRank implementation + scaling script
- `verify/`  – Correctness verification framework 
- `data/`    – Course-provided graph datasets

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
