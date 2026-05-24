# PageRank project implementation progress

This report implements the attached execution plan and records what is now in the repository.

## 1) Golden references (completed)

- Added `scripts/generate_references.sh`.
- Generates fixed-parameter serial references for all 9 datasets into `references/`.
- Output naming: `<dataset>_<mode>_serial.txt`.

## 2) Hotspot profiling (completed)

- Added `scripts/profile_hotspots.sh`.
- Produces:
  - `results/gprof_polblogs.txt`
  - `results/perf_stat_polblogs.txt`
  - `results/hotspot_notes.md`
- Host note: on current WSL host, `perf` kernel tools are missing, captured in output file.

## 3) OpenMP implementation + verification (completed)

- Added `openmp/pagerank_openmp.c`.
- Added `scripts/run_verify_suite.sh` to verify all datasets.
- Verification summary written to `results/verification_matrix.md`.
- Current status: OpenMP vs serial is PASS on all datasets.

## 4) MPI + Hybrid implementation and measured runs

- Added `mpi/pagerank_mpi.c`.
- Added `mpi/pagerank_hybrid.c`.
- Added cluster runner `scripts/run_mpi_cluster.sh`.
- Build wiring added in `scripts/build_all.sh`.
- MPI strong scaling has been measured on Dardel and the school cluster.
- Reproducible MPI weak scaling has been measured on both platforms through
  the required 16-rank `200k nodes / 2M edges` case.
- Hybrid fixed-core sweeps have been measured on the school cluster for
  `P*N=16`.

## 5) Bottleneck-driven optimizations + GPU offload prototype (completed in code)

- Optimization A: precomputed reciprocal out-degree (`inv_out_degree`) to avoid repeated divides in hot loops.
- Optimization B: OpenMP sparse loop scheduling (`dynamic,256`) for irregular incoming-edge workloads.
- GPU/offload comparison path: `openmp/pagerank_openmp_gpu.c`.
- Current verification matrix shows GPU output also matches serial on all datasets.

## 6) Consolidation assets (completed)

- Build automation: `scripts/build_all.sh`.
- Local scaling: `scripts/run_scaling_local.sh` -> `results/scaling_local.md`.
- Next-step execution guide: `results/next_steps_execution.md`.
- README updated with end-to-end workflow and MPI/hybrid commands.

## Remaining A-level runtime actions

1. Run MPI strong/weak scaling across multiple Dardel compute nodes; current
   Dardel results are single-node measurements.
2. Measure OpenMP scaling against serial on Colab, KTH, and Dardel.
3. Repeat the school-cluster Hybrid fixed-core search for additional total
   worker budgets beyond `P*N=16`.
4. Obtain a confirmed-device GPU timing comparison against Hybrid on a
   comparable platform and dataset.

See `results/a_grade_requirements_audit.md` for the evidence matrix and scope
cautions.
