# Hotspot notes for polblogs serial run

- Expected dominant kernel: incoming-edge accumulation loop in pagerank().
- Secondary kernel: dangling mass reduction + L1 convergence reduction.
- These are the primary parallelization targets for OpenMP and MPI decomposition.

See:
- results/gprof_polblogs.txt
- results/perf_stat_polblogs.txt
