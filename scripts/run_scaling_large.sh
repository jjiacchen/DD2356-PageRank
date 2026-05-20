#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GRAPH="${GRAPH:-$ROOT_DIR/data/synthetic_large_directed.csv}"
MODE="${MODE:-directed}"
NODES="${LARGE_NODES:-100000}"
EDGES="${LARGE_EDGES:-2000000}"
THREADS="${THREADS:-1 2 4 8}"
OUT="${OUT:-$ROOT_DIR/results/scaling_large.md}"
RUN_OPENMP="${RUN_OPENMP:-1}"

mkdir -p "$ROOT_DIR/results"

if [[ ! -f "$GRAPH" ]]; then
  echo "Large graph not found; generating $GRAPH"
  "$ROOT_DIR/scripts/generate_large_graph.py" --output "$GRAPH" --nodes "$NODES" --edges "$EDGES"
fi

if [[ ! -x "$ROOT_DIR/serial/pagerank_serial" ]]; then
  echo "Serial binary missing. Run scripts/build_all.sh first."
  exit 1
fi

if [[ "$RUN_OPENMP" != "0" && ! -x "$ROOT_DIR/openmp/pagerank_openmp" ]]; then
  echo "OpenMP binary missing. Run scripts/build_all.sh first, or set RUN_OPENMP=0 for serial-only timing."
  exit 1
fi

{
  echo "# Large-graph scaling results"
  echo ""
  echo "- Graph: \`$GRAPH\`"
  echo "- Mode: \`$MODE\`"
  echo "- Generator config if this script created the graph: nodes=$NODES, edges=$EDGES"
  echo "- Purpose: performance/scalability, not correctness smoke testing"
  echo ""
  echo "| Variant | Config | PR time (s) | Iterations |"
  echo "|---|---|---:|---:|"
} >"$OUT"

serial_log="$(mktemp)"
"$ROOT_DIR/serial/pagerank_serial" "$GRAPH" "$MODE" >"$serial_log"
serial_t="$(awk '/PR time/{print $4}' "$serial_log")"
serial_iter="$(awk '/Iterations/{print $3}' "$serial_log")"
echo "| serial | 1 thread | ${serial_t:-n/a} | ${serial_iter:-n/a} |" >>"$OUT"

if [[ "$RUN_OPENMP" != "0" ]]; then
  for th in $THREADS; do
    omp_log="$(mktemp)"
    "$ROOT_DIR/openmp/pagerank_openmp" "$GRAPH" "$MODE" "$th" >"$omp_log"
    omp_t="$(awk '/PR time/{print $4}' "$omp_log")"
    omp_iter="$(awk '/Iterations/{print $3}' "$omp_log")"
    echo "| openmp | ${th} threads | ${omp_t:-n/a} | ${omp_iter:-n/a} |" >>"$OUT"
    rm -f "$omp_log"
  done
fi

rm -f "$serial_log"
echo "Wrote $OUT"
