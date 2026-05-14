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

## Build & Run
```bash
gcc -O2 -o serial/pagerank_serial serial/pagerank_serial.c -lm
./serial/pagerank_serial data/polblogs.csv directed
./serial/pagerank_serial data/dolphins.csv undirected
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

## MPI / Hybrid (cluster)
```bash
mpirun -np 4 mpi/pagerank_mpi data/polblogs.csv directed
OMP_NUM_THREADS=4 mpirun -np 2 mpi/pagerank_hybrid data/polblogs.csv directed 4
```
