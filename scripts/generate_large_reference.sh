#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GRAPH="${GRAPH:-$ROOT_DIR/data/synthetic_large_directed.csv}"
MODE="${MODE:-directed}"
NODES="${LARGE_NODES:-100000}"
EDGES="${LARGE_EDGES:-2000000}"
OUT="${OUT:-$ROOT_DIR/references/synthetic_large_directed_serial.txt}"

if [[ ! -f "$GRAPH" ]]; then
  "$ROOT_DIR/scripts/generate_large_graph.py" --output "$GRAPH" --nodes "$NODES" --edges "$EDGES"
fi

if [[ ! -x "$ROOT_DIR/serial/pagerank_serial" ]]; then
  echo "Serial binary missing. Run scripts/build_all.sh first."
  exit 1
fi

mkdir -p "$(dirname "$OUT")"
(
  cd "$ROOT_DIR"
  "$ROOT_DIR/serial/pagerank_serial" "$GRAPH" "$MODE" >/tmp/pagerank_large_serial_run.log
  cp "$ROOT_DIR/pagerank_serial_output.txt" "$OUT"
)

echo "Wrote $OUT"
