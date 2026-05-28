#!/usr/bin/env bash
# Profile OpenMP target PageRank variants and verify them against serial output.
#
# Usage:
#   ./openmp/profile_gpu.sh [csv_file] [directed|undirected]
#
# Formal Dardel example:
#   PLATFORM=dardel_gpu REPEAT=5 PR_REQUIRE_DEVICE=1 \
#     ./openmp/profile_gpu.sh data/synthetic/synthetic_100k_1m.csv directed
# The DD2356 Jupyter Small GPU workflow selects its CUDA offload compiler via:
#   ./scripts/run_cluster_gpu_comparison.sh

set -euo pipefail

GRAPH="${1:-data/synthetic/synthetic_100k_1m.csv}"
MODE="${2:-directed}"
PLATFORM="${PLATFORM:-local}"
REPEAT="${REPEAT:-1}"
RUN_CORRECTNESS="${RUN_CORRECTNESS:-1}"
PR_REQUIRE_DEVICE="${PR_REQUIRE_DEVICE:-0}"
VARIANTS="${VARIANTS:-naive persistent}"
TOL="${TOL:-1e-6}"
PYTHON="${PYTHON:-python3}"
CC="${CC:-gcc}"
GPU_CC="${GPU_CC:-$CC}"
CFLAGS="${CFLAGS:--O2}"
GPU_OPENMP_CFLAGS="${GPU_OPENMP_CFLAGS:--fopenmp}"
GPU_OPENMP_LDFLAGS="${GPU_OPENMP_LDFLAGS:-$GPU_OPENMP_CFLAGS}"
RESULTS_DIR="${RESULTS_DIR:-results}"

SERIAL_BIN="./serial/pagerank_serial"
GPU_BIN="./openmp/pagerank_openmp_gpu"
VERIFY_BIN="./verify/verify"
BASE_NAME="$(basename "$GRAPH" .csv)"
RUN_ID="${PLATFORM}_${BASE_NAME}_${MODE}"
RAW_CSV="$RESULTS_DIR/gpu_offload_${RUN_ID}_raw.csv"
SUMMARY_CSV="$RESULTS_DIR/gpu_offload_${RUN_ID}.csv"
CORRECTNESS_CSV="$RESULTS_DIR/gpu_correctness_${PLATFORM}.csv"

DATASETS=(
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

mkdir -p "$RESULTS_DIR"

echo "========================================"
echo " DD2356 OpenMP Target GPU PageRank"
echo "========================================"
echo "Graph          : $GRAPH ($MODE)"
echo "Platform       : $PLATFORM"
echo "Variants       : $VARIANTS"
echo "Repeat         : $REPEAT"
echo "Require device : $PR_REQUIRE_DEVICE"
echo ""

echo "[build] serial baseline"
"$CC" $CFLAGS -o "$SERIAL_BIN" serial/pagerank_serial.c -lm
echo "[build] OpenMP target GPU version"
"$GPU_CC" $CFLAGS $GPU_OPENMP_CFLAGS -o "$GPU_BIN" openmp/pagerank_openmp_gpu.c $GPU_OPENMP_LDFLAGS -lm
echo "[build] verifier"
"$CC" $CFLAGS -o "$VERIFY_BIN" verify/verify_correctness.c -lm

parse_gpu_row() {
    "$PYTHON" - "$1" "$2" "$3" "$4" "$5" "$6" "$7" <<'PYEOF'
import re
import sys

log, verify_log, variant, dataset, mode, rep, status = sys.argv[1:]
text = open(log, encoding="utf-8", errors="replace").read()
vtext = open(verify_log, encoding="utf-8", errors="replace").read() if verify_log else ""

def take(pattern, default="0"):
    match = re.search(pattern, text)
    return match.group(1) if match else default

def verr(default="nan"):
    match = re.search(r"Max \|err\|\s*:\s*([0-9.eE+-]+)", vtext)
    return match.group(1) if match else default

print(",".join([
    "gpu", variant, dataset, mode, rep,
    take(r"Nodes\s*:\s*([0-9]+)"),
    take(r"Edges\s*:\s*([0-9]+)"),
    take(r"Iterations\s*:\s*([0-9]+)"),
    take(r"PR time\s*:\s*([0-9.eE+-]+)"),
    take(r"Total time\s*:\s*([0-9.eE+-]+)"),
    take(r"Target setup time\s*:\s*([0-9.eE+-]+)"),
    take(r"Iteration/kernel time\s*:\s*([0-9.eE+-]+)"),
    take(r"Target teardown time\s*:\s*([0-9.eE+-]+)"),
    take(r"Target devices\s*:\s*([0-9]+)"),
    take(r"Target device id\s*:\s*(-?[0-9]+)", "-1"),
    take(r"Target executed on device:\s*(YES|NO)", "NO"),
    verr(), status,
]))
PYEOF
}

parse_serial_row() {
    "$PYTHON" - "$1" "$2" "$3" "$4" <<'PYEOF'
import re
import sys

log, dataset, mode, rep = sys.argv[1:]
text = open(log, encoding="utf-8", errors="replace").read()
def take(pattern, default="0"):
    match = re.search(pattern, text)
    return match.group(1) if match else default
print(",".join([
    "serial", "serial", dataset, mode, rep,
    take(r"Nodes\s*:\s*([0-9]+)"),
    take(r"Edges\s*:\s*([0-9]+)"),
    take(r"Iterations\s*:\s*([0-9]+)"),
    take(r"PR time\s*:\s*([0-9.eE+-]+)"),
    take(r"PR time\s*:\s*([0-9.eE+-]+)"),
    "0", "0", "0", "0", "-1", "N/A", "0", "REFERENCE",
]))
PYEOF
}

FAILED=0
if [ "$RUN_CORRECTNESS" = "1" ]; then
    echo "dataset,mode,variant,nodes,edges,iterations,device_count,target_device_id,executed_on_device,max_error,status" > "$CORRECTNESS_CSV"
    for entry in "${DATASETS[@]}"; do
        csv="${entry%% *}"
        mode="${entry##* }"
        stem="${csv%.csv}"
        serial_log="$RESULTS_DIR/serial_gpu_correctness_${PLATFORM}_${stem}_${mode}.log"
        gpu_log="$RESULTS_DIR/gpu_correctness_${PLATFORM}_${stem}_${mode}.log"
        gpu_out="$RESULTS_DIR/gpu_correctness_${PLATFORM}_${stem}_${mode}.txt"
        verify_log="$RESULTS_DIR/verify_gpu_correctness_${PLATFORM}_${stem}_${mode}.log"
        echo "[correctness] $csv ($mode)"
        "$SERIAL_BIN" "data/$csv" "$mode" > "$serial_log"
        rm -f "$gpu_out"
        set +e
        PR_REQUIRE_DEVICE="$PR_REQUIRE_DEVICE" "$GPU_BIN" "data/$csv" "$mode" \
            0.85 1e-10 1000 "$gpu_out" persistent > "$gpu_log" 2>&1
        run_code=$?
        if [ "$run_code" -eq 0 ] && "$VERIFY_BIN" pagerank_serial_output.txt "$gpu_out" "$TOL" > "$verify_log" 2>&1; then
            status="PASS"
        else
            status="FAIL"
            FAILED=1
            if [ "$run_code" -ne 0 ]; then
                printf "GPU run failed with exit code %s\n" "$run_code" > "$verify_log"
            fi
        fi
        set -e
        "$PYTHON" - "$gpu_log" "$verify_log" "$csv" "$mode" "$status" >> "$CORRECTNESS_CSV" <<'PYEOF'
import re
import sys
log, verify_log, dataset, mode, status = sys.argv[1:]
text = open(log, encoding="utf-8", errors="replace").read()
vtext = open(verify_log, encoding="utf-8", errors="replace").read()
def take(pattern, default="0"):
    m = re.search(pattern, text)
    return m.group(1) if m else default
m = re.search(r"Max \|err\|\s*:\s*([0-9.eE+-]+)", vtext)
err = m.group(1) if m else "nan"
print(",".join([
    dataset, mode, "persistent",
    take(r"Nodes\s*:\s*([0-9]+)"), take(r"Edges\s*:\s*([0-9]+)"),
    take(r"Iterations\s*:\s*([0-9]+)"), take(r"Target devices\s*:\s*([0-9]+)"),
    take(r"Target device id\s*:\s*(-?[0-9]+)", "-1"),
    take(r"Target executed on device:\s*(YES|NO)", "NO"), err, status,
]))
PYEOF
        echo "  status=$status"
    done
    echo "[done] wrote $CORRECTNESS_CSV"
fi

echo "implementation,variant,dataset,mode,repeat,nodes,edges,iterations,pr_time_s,total_time_s,target_setup_time_s,kernel_time_s,target_teardown_time_s,device_count,target_device_id,executed_on_device,max_error,status" > "$RAW_CSV"

echo "[timing] serial baseline"
for rep in $(seq 1 "$REPEAT"); do
    log="$RESULTS_DIR/serial_gpu_${RUN_ID}_r${rep}.log"
    "$SERIAL_BIN" "$GRAPH" "$MODE" > "$log"
    parse_serial_row "$log" "$BASE_NAME" "$MODE" "$rep" >> "$RAW_CSV"
done

# Generate the reference that every GPU timing run must match.
"$SERIAL_BIN" "$GRAPH" "$MODE" > "$RESULTS_DIR/serial_gpu_${RUN_ID}_reference.log"

for variant in $VARIANTS; do
    for rep in $(seq 1 "$REPEAT"); do
        log="$RESULTS_DIR/gpu_${RUN_ID}_${variant}_r${rep}.log"
        out="$RESULTS_DIR/gpu_output_${RUN_ID}_${variant}_r${rep}.txt"
        verify_log="$RESULTS_DIR/verify_gpu_${RUN_ID}_${variant}_r${rep}.log"
        rm -f "$out"
        echo "[timing] variant=$variant repeat=$rep/$REPEAT"
        set +e
        PR_REQUIRE_DEVICE="$PR_REQUIRE_DEVICE" "$GPU_BIN" "$GRAPH" "$MODE" \
            0.85 1e-10 1000 "$out" "$variant" > "$log" 2>&1
        run_code=$?
        if [ "$run_code" -eq 0 ] && "$VERIFY_BIN" pagerank_serial_output.txt "$out" "$TOL" > "$verify_log" 2>&1; then
            status="PASS"
        else
            status="FAIL"
            FAILED=1
            if [ "$run_code" -ne 0 ]; then
                printf "GPU run failed with exit code %s\n" "$run_code" > "$verify_log"
            fi
        fi
        set -e
        row="$(parse_gpu_row "$log" "$verify_log" "$variant" "$BASE_NAME" "$MODE" "$rep" "$status")"
        echo "$row" >> "$RAW_CSV"
        printf "  %s\n" "$row"
    done
done

"$PYTHON" - "$RAW_CSV" "$SUMMARY_CSV" <<'PYEOF'
import csv
import math
import statistics
import sys
from collections import OrderedDict

raw_path, out_path = sys.argv[1:]
with open(raw_path, newline="") as stream:
    raw = list(csv.DictReader(stream))
groups = OrderedDict()
for row in raw:
    groups.setdefault((row["implementation"], row["variant"]), []).append(row)
naive = groups.get(("gpu", "naive"), [])
naive_avg = statistics.mean(float(row["pr_time_s"]) for row in naive) if naive else None
fields = [
    "implementation", "variant", "dataset", "mode", "nodes", "edges", "runs",
    "iterations", "pr_time_min_s", "pr_time_avg_s", "pr_time_median_s",
    "total_time_avg_s", "target_setup_avg_s", "kernel_time_avg_s",
    "target_teardown_avg_s", "device_count", "target_device_id",
    "executed_on_device", "max_error_max", "status", "speedup_vs_naive",
]
with open(out_path, "w", newline="") as stream:
    writer = csv.DictWriter(stream, fieldnames=fields)
    writer.writeheader()
    for (implementation, variant), rows in groups.items():
        pr = [float(r["pr_time_s"]) for r in rows]
        errors = [float(r["max_error"]) for r in rows if r["max_error"] not in ("nan", "0")]
        status = "REFERENCE" if implementation == "serial" else (
            "PASS" if all(r["status"] == "PASS" for r in rows) else "FAIL"
        )
        avg = statistics.mean(pr)
        writer.writerow({
            "implementation": implementation,
            "variant": variant,
            "dataset": rows[0]["dataset"],
            "mode": rows[0]["mode"],
            "nodes": rows[0]["nodes"],
            "edges": rows[0]["edges"],
            "runs": len(rows),
            "iterations": rows[0]["iterations"],
            "pr_time_min_s": f"{min(pr):.9f}",
            "pr_time_avg_s": f"{avg:.9f}",
            "pr_time_median_s": f"{statistics.median(pr):.9f}",
            "total_time_avg_s": f"{statistics.mean(float(r['total_time_s']) for r in rows):.9f}",
            "target_setup_avg_s": f"{statistics.mean(float(r['target_setup_time_s']) for r in rows):.9f}",
            "kernel_time_avg_s": f"{statistics.mean(float(r['kernel_time_s']) for r in rows):.9f}",
            "target_teardown_avg_s": f"{statistics.mean(float(r['target_teardown_time_s']) for r in rows):.9f}",
            "device_count": rows[0]["device_count"],
            "target_device_id": rows[0]["target_device_id"],
            "executed_on_device": rows[0]["executed_on_device"],
            "max_error_max": f"{max(errors):.6e}" if errors else "N/A",
            "status": status,
            "speedup_vs_naive": f"{naive_avg / avg:.9f}" if naive_avg else "N/A",
        })
PYEOF

echo "[done] wrote $RAW_CSV"
echo "[done] wrote $SUMMARY_CSV"

if [ "$FAILED" -ne 0 ]; then
    echo "One or more GPU verification runs failed." >&2
    exit 1
fi
