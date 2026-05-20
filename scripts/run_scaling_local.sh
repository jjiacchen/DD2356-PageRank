#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT_DIR/results/scaling_local.md"
GRAPH="$ROOT_DIR/data/polblogs.csv"

mkdir -p "$ROOT_DIR/results"

{
  echo "# Local scaling results (polblogs, directed)"
  echo ""
  echo "| Variant | Config | PR time (s) |"
  echo "|---|---|---:|"
} >"$OUT"

if [[ -x "$ROOT_DIR/serial/pagerank_serial" ]]; then
  t=$("$ROOT_DIR/serial/pagerank_serial" "$GRAPH" directed | awk '/PR time/{print $4}')
  echo "| serial | 1 thread | ${t:-n/a} |" >>"$OUT"
fi

if [[ -x "$ROOT_DIR/openmp/pagerank_openmp" ]]; then
  for th in 1 2 4 8; do
    t=$("$ROOT_DIR/openmp/pagerank_openmp" "$GRAPH" directed "$th" | awk '/PR time/{print $4}')
    echo "| openmp | ${th} threads | ${t:-n/a} |" >>"$OUT"
  done
fi

if command -v mpirun >/dev/null 2>&1 && [[ -x "$ROOT_DIR/mpi/pagerank_mpi" ]]; then
  for np in 1 2 4; do
    t=$(mpirun -np "$np" "$ROOT_DIR/mpi/pagerank_mpi" "$GRAPH" directed | awk '/PR time/{print $4}' | tail -n 1)
    echo "| mpi | ${np} ranks | ${t:-n/a} |" >>"$OUT"
  done
fi

if command -v mpirun >/dev/null 2>&1 && [[ -x "$ROOT_DIR/mpi/pagerank_hybrid" ]]; then
  for cfg in "1 8" "2 4" "4 2"; do
    np="${cfg%% *}"
    th="${cfg##* }"
    t=$(mpirun -np "$np" "$ROOT_DIR/mpi/pagerank_hybrid" "$GRAPH" directed "$th" | awk '/PR time/{print $4}' | tail -n 1)
    echo "| hybrid | ${np} ranks x ${th} threads | ${t:-n/a} |" >>"$OUT"
  done
fi

echo "Wrote $OUT"
