#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERIFY_BIN="$ROOT_DIR/verify/verify"
SERIAL_BIN="$ROOT_DIR/serial/pagerank_serial"
OMP_BIN="$ROOT_DIR/openmp/pagerank_openmp"
GPU_BIN="$ROOT_DIR/openmp/pagerank_openmp_gpu"
REF_DIR="$ROOT_DIR/references"
OUT="$ROOT_DIR/results/verification_matrix.md"

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

mkdir -p "$ROOT_DIR/results"
{
  echo "# Verification matrix"
  echo ""
  echo "| Dataset | Mode | OpenMP vs serial | GPU vs serial |"
  echo "|---|---|---|---|"
} >"$OUT"

for entry in "${DATASETS[@]}"; do
  csv="${entry%% *}"
  mode="${entry##* }"
  stem="${csv%.csv}"
  ref="$REF_DIR/${stem}_${mode}_serial.txt"

  (
    cd "$ROOT_DIR"
    "$OMP_BIN" "$ROOT_DIR/data/$csv" "$mode" 8 >/tmp/omp_run.log
  )
  omp_out="$ROOT_DIR/pagerank_openmp_output.txt"
  if "$VERIFY_BIN" "$ref" "$omp_out" 1e-8 >/tmp/verify_omp.log 2>&1; then
    omp_stat="PASS"
  else
    omp_stat="FAIL"
  fi

  if [[ -x "$GPU_BIN" ]]; then
    (
      cd "$ROOT_DIR"
      "$GPU_BIN" "$ROOT_DIR/data/$csv" "$mode" >/tmp/gpu_run.log
    )
    gpu_out="$ROOT_DIR/pagerank_gpu_output.txt"
    if "$VERIFY_BIN" "$ref" "$gpu_out" 1e-8 >/tmp/verify_gpu.log 2>&1; then
      gpu_stat="PASS"
    else
      gpu_stat="FAIL"
    fi
  else
    gpu_stat="N/A"
  fi

  echo "| $csv | $mode | $omp_stat | $gpu_stat |" >>"$OUT"
done

echo "Wrote $OUT"
