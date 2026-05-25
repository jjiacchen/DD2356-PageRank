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
- MPI strong scaling has been measured on the school cluster and across two
  Dardel `main` compute nodes with explicit placement records.
- Reproducible MPI weak scaling has been measured on both platforms through
  the required 16-rank `200k nodes / 2M edges` case; the formal Dardel run
  spans `nid001120` and `nid001121` for every multi-rank row.
- Hybrid fixed-core sweeps have been measured on the school cluster for
  `P*N=16`.

## 5) Bottleneck-driven optimizations + GPU offload validation (completed)

- Optimization A: precomputed reciprocal out-degree (`inv_out_degree`) to avoid repeated divides in hot loops.
- Optimization B: OpenMP sparse loop scheduling (`dynamic,256`) for irregular incoming-edge workloads.
- GPU/offload comparison path: `openmp/pagerank_openmp_gpu.c`.
- GPU profiling compares naive remapping with persistent device data regions.
- A confirmed-device run on the DD2356 Small GPU server (NVIDIA H100
  `MIG 1g.10gb`) passes all nine course datasets and all timed GPU repetitions.
- On `synthetic_100k_1m.csv`, persistent GPU offload is `1.776212x` faster
  than naive GPU offload; the same-server Hybrid `4x2` control remains faster.

## 6) Consolidation assets (completed)

- Build automation: `scripts/build_all.sh`.
- Local scaling: `scripts/run_scaling_local.sh` -> `results/scaling_local.md`.
- Next-step execution guide: `results/next_steps_execution.md`.
- README updated with end-to-end workflow and MPI/hybrid commands.

## Remaining A-level runtime actions

1. Measure OpenMP scaling against serial on Colab, KTH, and Dardel
   (Minyi Zhu's OpenMP-analysis scope).
2. Repeat the school-cluster Hybrid fixed-core search for additional total
   worker budgets beyond `P*N=16` (Minyi Zhu's hybrid-analysis scope).

See `results/a_grade_requirements_audit.md` for the evidence matrix and scope
cautions.
