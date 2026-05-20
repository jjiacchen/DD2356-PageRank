#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL_SRC="$ROOT_DIR/serial/pagerank_serial.c"
SERIAL_BIN="$ROOT_DIR/serial/pagerank_serial"
OUT_DIR="$ROOT_DIR/references"

mkdir -p "$OUT_DIR"

gcc -O2 -o "$SERIAL_BIN" "$SERIAL_SRC" -lm

declare -a DATASETS=(
  "polblogs.csv directed"
  "karateDir.csv directed"
  "lesmisDir.csv directed"
  "dolphinsDir.csv directed"
  "NCAA_football.csv directed"
  "dolphins.csv undirected"
  "karate.csv undirected"
  "lesmis.csv undirected"
  "stateborders.csv undirected"
)

echo "Generating serial golden references in: $OUT_DIR"
for entry in "${DATASETS[@]}"; do
  csv="${entry%% *}"
  mode="${entry##* }"
  stem="${csv%.csv}"
  out_file="$OUT_DIR/${stem}_${mode}_serial.txt"
  printf "  - %-26s (%s)\n" "$csv" "$mode"
  (
    cd "$ROOT_DIR"
    "$SERIAL_BIN" "$ROOT_DIR/data/$csv" "$mode" >/tmp/pagerank_serial_run.log
    cp "$ROOT_DIR/pagerank_serial_output.txt" "$out_file"
  )
done

echo "Done. Generated ${#DATASETS[@]} reference files."
