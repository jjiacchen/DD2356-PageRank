#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -z "${CC+x}" ]; then
  CC="gcc"
  AUTO_CC=1
else
  AUTO_CC=0
fi
MPICC="${MPICC:-mpicc}"
CFLAGS="${CFLAGS:--O2}"
OPENMP_CFLAGS="${OPENMP_CFLAGS:--fopenmp}"
OPENMP_LDFLAGS="${OPENMP_LDFLAGS:-$OPENMP_CFLAGS}"
GPU_CC="${GPU_CC:-$CC}"
GPU_OPENMP_CFLAGS="${GPU_OPENMP_CFLAGS:-$OPENMP_CFLAGS}"
GPU_OPENMP_LDFLAGS="${GPU_OPENMP_LDFLAGS:-$GPU_OPENMP_CFLAGS}"
MPI_WRAPPER_CC="${MPI_WRAPPER_CC:-${OMPI_CC:-}}"
BUILD_GPU="${BUILD_GPU:-1}"

supports_openmp_with_flags() {
  local compiler="$1"
  local omp_cflags="$2"
  local omp_ldflags="$3"
  local tmp_src tmp_bin
  tmp_src="$(mktemp /tmp/openmp-check.XXXXXX.c)"
  tmp_bin="$(mktemp /tmp/openmp-check.XXXXXX)"
  printf '#include <omp.h>\nint main(void){return omp_get_max_threads() < 1;}\n' > "$tmp_src"
  if "$compiler" $omp_cflags "$tmp_src" -o "$tmp_bin" $omp_ldflags >/dev/null 2>&1; then
    rm -f "$tmp_src" "$tmp_bin"
    return 0
  fi
  rm -f "$tmp_src" "$tmp_bin"
  return 1
}

supports_openmp() {
  supports_openmp_with_flags "$1" "$OPENMP_CFLAGS" "$OPENMP_LDFLAGS"
}

supports_mpi_openmp() {
  local tmp_src tmp_bin
  tmp_src="$(mktemp /tmp/mpi-openmp-check.XXXXXX.c)"
  tmp_bin="$(mktemp /tmp/mpi-openmp-check.XXXXXX)"
  printf '#include <mpi.h>\n#include <omp.h>\nint main(int argc,char **argv){MPI_Init(&argc,&argv); int n=omp_get_max_threads(); MPI_Finalize(); return n < 1;}\n' > "$tmp_src"
  if [ -n "$MPI_WRAPPER_CC" ]; then
    if OMPI_CC="$MPI_WRAPPER_CC" "$MPICC" $OPENMP_CFLAGS "$tmp_src" -o "$tmp_bin" $OPENMP_LDFLAGS >/dev/null 2>&1; then
      rm -f "$tmp_src" "$tmp_bin"
      return 0
    fi
  else
    if "$MPICC" $OPENMP_CFLAGS "$tmp_src" -o "$tmp_bin" $OPENMP_LDFLAGS >/dev/null 2>&1; then
      rm -f "$tmp_src" "$tmp_bin"
      return 0
    fi
  fi
  rm -f "$tmp_src" "$tmp_bin"
  return 1
}

if [ "$AUTO_CC" -eq 1 ] && ! supports_openmp "$CC"; then
  if command -v gcc-15 >/dev/null 2>&1 && supports_openmp gcc-15; then
    CC="gcc-15"
  fi
fi

if command -v "$MPICC" >/dev/null 2>&1 && [ -z "$MPI_WRAPPER_CC" ] && ! supports_mpi_openmp; then
  if command -v gcc-15 >/dev/null 2>&1; then
    MPI_WRAPPER_CC="$(command -v gcc-15)"
  fi
fi

"$CC" $CFLAGS -o "$ROOT_DIR/serial/pagerank_serial" "$ROOT_DIR/serial/pagerank_serial.c" -lm
"$CC" $CFLAGS -o "$ROOT_DIR/verify/verify" "$ROOT_DIR/verify/verify_correctness.c" -lm

if supports_openmp "$CC"; then
  "$CC" $CFLAGS $OPENMP_CFLAGS -o "$ROOT_DIR/openmp/pagerank_openmp" "$ROOT_DIR/openmp/pagerank_openmp.c" $OPENMP_LDFLAGS -lm
  if [ "$BUILD_GPU" = "1" ]; then
    if supports_openmp_with_flags "$GPU_CC" "$GPU_OPENMP_CFLAGS" "$GPU_OPENMP_LDFLAGS"; then
      "$GPU_CC" $CFLAGS $GPU_OPENMP_CFLAGS -o "$ROOT_DIR/openmp/pagerank_openmp_gpu" "$ROOT_DIR/openmp/pagerank_openmp_gpu.c" $GPU_OPENMP_LDFLAGS -lm
    else
      echo "GPU OpenMP compiler unavailable for GPU_CC=$GPU_CC; GPU binary is skipped."
    fi
  else
    echo "BUILD_GPU=0; OpenMP target GPU binary is skipped."
  fi
else
  echo "OpenMP compiler unavailable for CC=$CC; OpenMP/GPU binaries are skipped."
fi

if command -v "$MPICC" >/dev/null 2>&1; then
  "$MPICC" $CFLAGS -o "$ROOT_DIR/mpi/pagerank_mpi" "$ROOT_DIR/mpi/pagerank_mpi.c" -lm
  if supports_mpi_openmp; then
    if [ -n "$MPI_WRAPPER_CC" ]; then
      OMPI_CC="$MPI_WRAPPER_CC" "$MPICC" $CFLAGS $OPENMP_CFLAGS -o "$ROOT_DIR/mpi/pagerank_hybrid" "$ROOT_DIR/mpi/pagerank_hybrid.c" $OPENMP_LDFLAGS -lm
    else
      "$MPICC" $CFLAGS $OPENMP_CFLAGS -o "$ROOT_DIR/mpi/pagerank_hybrid" "$ROOT_DIR/mpi/pagerank_hybrid.c" $OPENMP_LDFLAGS -lm
    fi
  else
    echo "MPI OpenMP compiler unavailable; Hybrid binary is skipped."
  fi
else
  echo "mpicc not available; MPI/Hybrid binaries are skipped."
fi

echo "Build finished."
