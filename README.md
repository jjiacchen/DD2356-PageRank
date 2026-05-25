# DD2356 Final Project – High-Performance PageRank
**Group 26**

## Structure
- `serial/`  – Serial C baseline + profiling scripts 
- `openmp/`  – OpenMP CPU implementation + OpenMP target GPU paths
- `mpi/`     – MPI and Hybrid MPI+OpenMP implementations
- `verify/`  – Correctness verification framework 
- `data/`    – Course-provided graph datasets
- `scripts/` – Build, reference generation, profiling, scaling and verification helpers
- `references/` – Golden serial outputs for all datasets
- `tools/`   – Synthetic graph generation and MPI/GPU result plotting helpers

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

## Hybrid Fixed-Core Profile
```bash
./mpi/profile_hybrid.sh data/polblogs.csv directed "1x4 2x2 4x1"
```

The Hybrid profiler builds the serial baseline, Hybrid MPI+OpenMP binary, and verifier; then it writes `results/hybrid_fixedcore_*.csv`. On Open MPI wrappers that default to Apple clang, use:
```bash
CC=gcc-15 OMPI_CC=/opt/homebrew/bin/gcc-15 ./mpi/profile_hybrid.sh data/polblogs.csv directed "1x4 2x2 4x1"
```

## Hybrid Optimization Ablation
```bash
REPEAT=10 OUTPUT_PREFIX=cluster_ ./mpi/profile_optimization_ablation.sh data/synthetic/synthetic_100k_1m.csv directed "1x16 4x4"
REPEAT=30 OUTPUT_PREFIX=cluster_ ./mpi/profile_optimization_ablation.sh data/polblogs.csv directed "1x16 4x4"
```

The ablation profiler compares four Hybrid MPI+OpenMP variants:
`no_inv_static`, `inv_static`, `no_inv_dynamic`, and `inv_dynamic`. It writes
`results/optimization_ablation_<dataset>_<mode>.csv` plus the raw repeat-level
CSV. On Open MPI wrappers that default to Apple clang, use the same compiler
override as the fixed-core Hybrid profiler:
```bash
CC=gcc-15 OMPI_CC=/opt/homebrew/bin/gcc-15 REPEAT=10 OUTPUT_PREFIX=cluster_ ./mpi/profile_optimization_ablation.sh data/synthetic/synthetic_100k_1m.csv directed "1x16 4x4"
```

## Wang MPI Workflow Before Cluster Runs
```bash
# 1. Check correctness across all course datasets
./mpi/test_mpi_all.sh

# 2. Run fixed-core Hybrid smoke/profile combos
CC=gcc-15 OMPI_CC=/opt/homebrew/bin/gcc-15 ./mpi/profile_hybrid.sh data/polblogs.csv directed "1x4 2x2 4x1"

# 3. Generate larger synthetic graphs for meaningful strong scaling
python3 tools/generate_graph.py --preset all

# 4. Generate weak-scaling graphs up to the required 16-rank case
python3 tools/generate_graph.py --preset weak

# 5. Run a local or cluster strong-scaling profile
REPEAT=3 ./mpi/profile_mpi.sh data/synthetic/synthetic_10k_100k.csv directed "1 2 4"

# 6. Run true weak scaling (each rank count uses a different graph size)
PLATFORM=cluster REPEAT=5 ./mpi/profile_mpi_weak.sh directed "1 2 4 8 16"

# 7. Generate result figures from summary CSV files
python3 tools/plot_mpi_results.py results/mpi_scaling_synthetic_10k_100k_directed.csv --out-dir results/figures
```

The plotting script requires Pillow. If the default Python does not have it, use the bundled Codex runtime Python shown by the app or run the plotting step on a machine with Pillow installed.

## Dardel GPU Offloading Profile
The GPU executable accepts a final `naive` or `persistent` variant argument.
The persistent variant keeps the CSR graph and PageRank buffers resident in
target memory across the iteration loop. Formal GPU runs set
`PR_REQUIRE_DEVICE=1`, which rejects an OpenMP host fallback.

```bash
# Local correctness smoke; target execution may legitimately fall back to CPU.
CC=gcc-15 GPU_CC=gcc-15 REPEAT=1 RUN_CORRECTNESS=1 \
  ./openmp/profile_gpu.sh data/karateDir.csv directed

# Dardel AMD GPU node: confirmed-device GPU results plus an 8x2 Hybrid control.
sbatch scripts/run_dardel_gpu_comparison.sh

# After downloading formal CSV files, create report figures locally.
python3 tools/plot_gpu_results.py \
  results/gpu_vs_hybrid_dardel_gpu_synthetic_100k_1m_directed.csv \
  results/gpu_offload_dardel_gpu_synthetic_100k_1m_directed.csv \
  --out-dir results/figures/dardel_gpu
```

The Dardel GPU runner follows PDC's AMD GPU environment:
`PDC/24.11`, `rocm/6.3.3`, and `craype-accel-amd-gfx90a`. It also saves a
`CRAY_ACC_DEBUG=3` probe log as evidence that target regions execute on a
device.

If the Dardel course allocation cannot access its GPU partition, use the
DD2356 JupyterHub `Small GPU` server. It exposes a shared NVIDIA MIG GPU and
up to eight CPU cores. The runner below first tests whether `nvc` or GCC
NVPTX can execute an OpenMP target region on the GPU; it refuses to collect
formal timings if the target falls back to the CPU. Since the server has only
eight CPUs, its same-node Hybrid control is `4x2`. The runner disables the
x86 CET and stack-protector flags for GCC NVPTX compilation because those
host hardening mechanisms are unsupported in the offload target code.

```bash
git clone --branch codex/wang-dardel-experiments \
  https://github.com/jjiacchen/DD2356-PageRank.git
cd DD2356-PageRank
REPEAT=5 ./scripts/run_cluster_gpu_comparison.sh
```

On success, download `wang_cluster_gpu_results.tar.gz` from JupyterLab and
extract it locally before running `tools/plot_gpu_results.py` with the
`cluster_gpu` CSV filenames.

## Cluster Submission
```bash
# Generic SLURM
sbatch run_mpi.sh

# Dardel
GRAPH=data/synthetic/synthetic_100k_1m.csv MODE=directed RANKS="1 2 4 8 16 32" sbatch run_mpi_dardel.sh

# School cluster
GRAPH=data/synthetic/synthetic_100k_1m.csv MODE=directed RANKS="1 2 4 8 16 32" sbatch run_mpi_cluster.sh

# School cluster / Jupiter web terminal weak scaling.
# Regenerate preset inputs first so the cluster and Dardel measurements use
# identical synthetic graphs.
python3 tools/generate_graph.py --preset weak
PLATFORM=cluster GENERATE_WEAK_GRAPHS=0 REPEAT=5 ./mpi/profile_mpi_weak.sh directed "1 2 4 8 16"

# Dardel weak scaling from an allocated job shell
PLATFORM=dardel MPI_RUNNER=srun MPI_NP_FLAG=-n REPEAT=5 ./mpi/profile_mpi_weak.sh directed "1 2 4 8 16"
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

## MPI / Hybrid (cluster)
```bash
mpirun -np 4 mpi/pagerank_mpi data/polblogs.csv directed
OMP_NUM_THREADS=4 mpirun -np 2 mpi/pagerank_hybrid data/polblogs.csv directed 4
```
