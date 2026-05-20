# Next-step execution checklist

This file maps directly to proposal milestones and the implemented scripts.

## W2 OpenMP

- Build: `scripts/build_all.sh`
- Run one dataset: `openmp/pagerank_openmp data/polblogs.csv directed 8`
- Verify against golden: `verify/verify references/polblogs_directed_serial.txt pagerank_openmp_output.txt 1e-8`
- Batch verify all datasets: `scripts/run_verify_suite.sh`
- Local scaling table: `scripts/run_scaling_local.sh`

## W3 MPI

- Build (on cluster with MPI toolchain): `scripts/build_all.sh`
- Run: `mpirun -np 4 mpi/pagerank_mpi data/polblogs.csv directed`
- Verify: `verify/verify references/polblogs_directed_serial.txt pagerank_mpi_output.txt 1e-8`

## W4 Hybrid MPI + OpenMP

- Run fixed-core search examples:
  - `OMP_NUM_THREADS=8 mpirun -np 1 mpi/pagerank_hybrid data/polblogs.csv directed 8`
  - `OMP_NUM_THREADS=4 mpirun -np 2 mpi/pagerank_hybrid data/polblogs.csv directed 4`
  - `OMP_NUM_THREADS=2 mpirun -np 4 mpi/pagerank_hybrid data/polblogs.csv directed 2`
- Verify each result with `verify/verify`.
- Automated fixed-core profile:
  - `./mpi/profile_hybrid.sh data/polblogs.csv directed "1x8 2x4 4x2 8x1"`
  - On local Open MPI + Apple clang wrappers: `CC=gcc-15 OMPI_CC=/opt/homebrew/bin/gcc-15 ./mpi/profile_hybrid.sh data/polblogs.csv directed "1x4 2x2 4x1"`

## W5 Optimization + GPU offload

- Optimization 1 (implemented): cached reciprocal out-degree (`inv_out_degree`) to remove repeated divisions in kernels.
- Optimization 2 (implemented): OpenMP loop scheduling tuned (`dynamic,256` on sparse incoming loop) for better load balance.
- GPU prototype run: `openmp/pagerank_openmp_gpu data/polblogs.csv directed`
- Compare with CPU outputs via `verify/verify`.

## W6 Consolidation

- Baselines: `results/baseline_results.md`
- Hotspots: `results/gprof_polblogs.txt`, `results/perf_stat_polblogs.txt`, `results/hotspot_notes.md`
- Verification matrix: `results/verification_matrix.md`
- Scaling table: `results/scaling_local.md`
