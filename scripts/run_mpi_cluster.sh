#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GRAPH="${1:-$ROOT_DIR/data/polblogs.csv}"
MODE="${2:-directed}"

if ! command -v mpirun >/dev/null 2>&1; then
  echo "mpirun not found. Run this script on a cluster node with MPI runtime."
  exit 1
fi

if [[ ! -x "$ROOT_DIR/mpi/pagerank_mpi" || ! -x "$ROOT_DIR/mpi/pagerank_hybrid" ]]; then
  echo "MPI binaries missing. Build first with scripts/build_all.sh on MPI-enabled environment."
  exit 1
fi

OUT="$ROOT_DIR/results/scaling_cluster.md"
mkdir -p "$ROOT_DIR/results"
{
  echo "# Cluster scaling results"
  echo ""
  echo "| Variant | Config | PR time (s) |"
  echo "|---|---|---:|"
} >"$OUT"

# Strong scaling: same graph, increasing ranks.
for np in 1 2 4 8 16; do
  t=$(mpirun -np "$np" "$ROOT_DIR/mpi/pagerank_mpi" "$GRAPH" "$MODE" | awk '/PR time/{print $4}' | tail -n 1)
  echo "| mpi-strong | ${np} ranks | ${t:-n/a} |" >>"$OUT"
done

# Hybrid search under fixed total workers = 16.
declare -a HYBRID_CFGS=("1 16" "2 8" "4 4" "8 2" "16 1")
for cfg in "${HYBRID_CFGS[@]}"; do
  np="${cfg%% *}"
  th="${cfg##* }"
  t=$(OMP_NUM_THREADS="$th" mpirun -np "$np" \
    "$ROOT_DIR/mpi/pagerank_hybrid" "$GRAPH" "$MODE" "$th" | awk '/PR time/{print $4}' | tail -n 1)
  echo "| hybrid-fixed16 | ${np} ranks x ${th} threads | ${t:-n/a} |" >>"$OUT"
done

echo "Wrote $OUT"
