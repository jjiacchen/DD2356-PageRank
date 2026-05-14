#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

gcc -O2 -o "$ROOT_DIR/serial/pagerank_serial" "$ROOT_DIR/serial/pagerank_serial.c" -lm
gcc -O2 -fopenmp -o "$ROOT_DIR/openmp/pagerank_openmp" "$ROOT_DIR/openmp/pagerank_openmp.c" -lm
gcc -O2 -fopenmp -o "$ROOT_DIR/openmp/pagerank_openmp_gpu" "$ROOT_DIR/openmp/pagerank_openmp_gpu.c" -lm
gcc -O2 -o "$ROOT_DIR/verify/verify" "$ROOT_DIR/verify/verify_correctness.c" -lm

if command -v mpicc >/dev/null 2>&1; then
  mpicc -O2 -o "$ROOT_DIR/mpi/pagerank_mpi" "$ROOT_DIR/mpi/pagerank_mpi.c" -lm
  mpicc -O2 -fopenmp -o "$ROOT_DIR/mpi/pagerank_hybrid" "$ROOT_DIR/mpi/pagerank_hybrid.c" -lm
else
  echo "mpicc not available; MPI/Hybrid binaries are skipped."
fi

echo "Build finished."
