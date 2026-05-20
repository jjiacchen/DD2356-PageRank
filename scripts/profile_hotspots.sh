#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL_SRC="$ROOT_DIR/serial/pagerank_serial.c"
SERIAL_BIN="$ROOT_DIR/serial/pagerank_serial"
PROF_BIN="$ROOT_DIR/serial/pagerank_serial_pg"
OUT_DIR="$ROOT_DIR/results"

mkdir -p "$OUT_DIR"

gcc -O2 -o "$SERIAL_BIN" "$SERIAL_SRC" -lm
gcc -O2 -pg -o "$PROF_BIN" "$SERIAL_SRC" -lm

GRAPH="$ROOT_DIR/data/polblogs.csv"
MODE="directed"

echo "[1/3] Running gprof build..."
(
  cd "$ROOT_DIR"
  "$PROF_BIN" "$GRAPH" "$MODE" >/tmp/pagerank_gprof.log
)
if [[ -f "$ROOT_DIR/gmon.out" ]]; then
  gprof "$PROF_BIN" "$ROOT_DIR/gmon.out" >"$OUT_DIR/gprof_polblogs.txt"
else
  echo "gmon.out not generated on this host." >"$OUT_DIR/gprof_polblogs.txt"
fi

if command -v perf >/dev/null 2>&1; then
  echo "[2/3] Running perf stat..."
  set +e
  perf stat -e cycles,instructions,cache-misses,branches,branch-misses \
    "$SERIAL_BIN" "$GRAPH" "$MODE" \
    >"$OUT_DIR/perf_polblogs_stdout.txt" 2>"$OUT_DIR/perf_stat_polblogs.txt"
  rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    echo "perf failed on this host (likely permissions)." >>"$OUT_DIR/perf_stat_polblogs.txt"
  fi
else
  echo "perf not available on this machine." >"$OUT_DIR/perf_stat_polblogs.txt"
fi

echo "[3/3] Producing short hotspot memo..."
{
  echo "# Hotspot notes for polblogs serial run"
  echo ""
  echo "- Expected dominant kernel: incoming-edge accumulation loop in pagerank()."
  echo "- Secondary kernel: dangling mass reduction + L1 convergence reduction."
  echo "- These are the primary parallelization targets for OpenMP and MPI decomposition."
  echo ""
  echo "See:"
  echo "- results/gprof_polblogs.txt"
  echo "- results/perf_stat_polblogs.txt"
} >"$OUT_DIR/hotspot_notes.md"

echo "Profiling outputs written under: $OUT_DIR"
