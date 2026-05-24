#!/bin/bash
# profile_optimization_ablation.sh - before/after profiling for Hybrid MPI+OpenMP optimizations.
#
# Usage:
#   REPEAT=10 ./mpi/profile_optimization_ablation.sh data/synthetic/synthetic_100k_1m.csv directed "1x16 4x4"
#   REPEAT=30 ./mpi/profile_optimization_ablation.sh data/polblogs.csv directed "1x16 4x4"
#
# The default output prefix is "cluster_" because this script is meant for the
# final school-cluster optimization evidence. Override with OUTPUT_PREFIX="" for
# local exploratory runs.

set -e

GRAPH="${1:-data/synthetic/synthetic_100k_1m.csv}"
MODE="${2:-directed}"
COMBOS="${3:-1x16 4x4}"
REPEAT="${REPEAT:-10}"
VARIANTS="${VARIANTS:-no_inv_static inv_static no_inv_dynamic inv_dynamic}"
MPI_RUNNER="${MPI_RUNNER:-mpirun}"
MPI_NP_FLAG="${MPI_NP_FLAG:--np}"
MPI_CPUS_PER_TASK_FLAG="${MPI_CPUS_PER_TASK_FLAG:-}"
MPI_FLAGS="${MPI_FLAGS:-}"
TOL="${TOL:-1e-6}"
OUTPUT_PREFIX="${OUTPUT_PREFIX:-cluster_}"
PYTHON="${PYTHON:-python3}"
CC="${CC:-gcc}"
MPICC="${MPICC:-mpicc}"
OPENMP_CFLAGS="${OPENMP_CFLAGS:--fopenmp}"
OPENMP_LDFLAGS="${OPENMP_LDFLAGS:-$OPENMP_CFLAGS}"

SERIAL_BIN="./serial/pagerank_serial"
HYBRID_BIN="./mpi/pagerank_hybrid_ablation"
VERIFY_BIN="./verify/verify"

mkdir -p results

BASE_NAME="$(basename "$GRAPH" .csv)"
RUN_ID="${OUTPUT_PREFIX}${BASE_NAME}_${MODE}"
RAW_CSV="results/optimization_ablation_${RUN_ID}_raw.csv"
SUMMARY_CSV="results/optimization_ablation_${RUN_ID}.csv"
SERIAL_LOG="results/serial_ablation_${RUN_ID}.log"

variant_defines() {
    case "$1" in
        no_inv_static)  printf "%s" "-DPR_DISABLE_INV_OUT_DEG -DPR_UPDATE_SCHEDULE_STATIC" ;;
        inv_static)     printf "%s" "-DPR_UPDATE_SCHEDULE_STATIC" ;;
        no_inv_dynamic) printf "%s" "-DPR_DISABLE_INV_OUT_DEG" ;;
        inv_dynamic)    printf "%s" "" ;;
        *)
            echo "Unknown variant '$1'" >&2
            exit 1
            ;;
    esac
}

echo "========================================"
echo " DD2356 Hybrid Optimization Ablation"
echo "========================================"
echo "Graph        : $GRAPH ($MODE)"
echo "Combos       : $COMBOS"
echo "Variants     : $VARIANTS"
echo "Repeat       : $REPEAT"
echo "MPI runner   : $MPI_RUNNER $MPI_FLAGS $MPI_NP_FLAG <np>"
if [ -n "$MPI_CPUS_PER_TASK_FLAG" ]; then
    echo "CPU binding  : $MPI_CPUS_PER_TASK_FLAG <threads>"
fi
echo "Tolerance    : $TOL"
echo "Output       : $SUMMARY_CSV"
echo ""

echo "[build] serial baseline"
"$CC" -O2 -o "$SERIAL_BIN" serial/pagerank_serial.c -lm

echo "[build] verifier"
"$CC" -O2 -o "$VERIFY_BIN" verify/verify_correctness.c -lm

echo ""
echo "[reference] generating serial golden output"
"$SERIAL_BIN" "$GRAPH" "$MODE" > "$SERIAL_LOG"

echo "dataset,mode,variant,ranks,threads,total_workers,repeat,pr_time_s,total_time_s,comm_time_s,comm_fraction,dangling_reduce_s,diff_reduce_s,allgatherv_s,iterations,max_error,status,work_nodes_min,work_nodes_avg,work_nodes_max,work_inedges_min,work_inedges_avg,work_inedges_max,work_imbalance" > "$RAW_CSV"

for VARIANT in $VARIANTS; do
    DEFINES="$(variant_defines "$VARIANT")"
    echo ""
    echo "[build] hybrid variant=$VARIANT defines='$DEFINES'"
    # shellcheck disable=SC2086
    "$MPICC" -O2 $OPENMP_CFLAGS $DEFINES -o "$HYBRID_BIN" mpi/pagerank_hybrid.c $OPENMP_LDFLAGS -lm

    for COMBO in $COMBOS; do
        RANKS="${COMBO%x*}"
        THREADS="${COMBO#*x}"
        if [ -z "$RANKS" ] || [ -z "$THREADS" ] || [ "$RANKS" = "$COMBO" ]; then
            echo "Invalid combo '$COMBO' (expected RANKSxTHREADS)" >&2
            exit 1
        fi
        WORKERS=$((RANKS * THREADS))

        for REP in $(seq 1 "$REPEAT"); do
            HYBRID_LOG="results/ablation_${RUN_ID}_${VARIANT}_${COMBO}_r${REP}.log"
            VERIFY_LOG="results/verify_ablation_${RUN_ID}_${VARIANT}_${COMBO}_r${REP}.log"
            HYBRID_OUT="pagerank_hybrid_ablation_output_${RUN_ID}_${VARIANT}_${COMBO}_r${REP}.txt"

            echo ""
            echo "[run] variant=$VARIANT combo=$COMBO repeat=$REP/$REPEAT"
            CPU_ARGS=()
            if [ -n "$MPI_CPUS_PER_TASK_FLAG" ]; then
                CPU_ARGS=("$MPI_CPUS_PER_TASK_FLAG" "$THREADS")
            fi
            set +e
            # shellcheck disable=SC2086
            OMP_NUM_THREADS="$THREADS" OMP_PLACES="${OMP_PLACES:-cores}" OMP_PROC_BIND="${OMP_PROC_BIND:-close}" \
                "$MPI_RUNNER" $MPI_FLAGS "$MPI_NP_FLAG" "$RANKS" "${CPU_ARGS[@]}" \
                "$HYBRID_BIN" "$GRAPH" "$MODE" "$THREADS" 0.85 1e-10 1000 "$HYBRID_OUT" \
                > "$HYBRID_LOG" < /dev/null
            RUN_CODE=$?
            if [ "$RUN_CODE" -eq 0 ] && "$VERIFY_BIN" pagerank_serial_output.txt "$HYBRID_OUT" "$TOL" > "$VERIFY_LOG"; then
                STATUS="PASS"
            else
                STATUS="FAIL"
                if [ "$RUN_CODE" -ne 0 ]; then
                    echo "[FAIL] Hybrid run failed with exit code $RUN_CODE" > "$VERIFY_LOG"
                fi
            fi
            set -e

            ROW=$("$PYTHON" - "$HYBRID_LOG" "$VERIFY_LOG" "$BASE_NAME" "$MODE" "$VARIANT" "$RANKS" "$THREADS" "$WORKERS" "$REP" "$STATUS" <<'PYEOF'
import re
import sys

hybrid_log, verify_log, dataset, mode, variant, ranks, threads, workers, rep, status = sys.argv[1:]
text = open(hybrid_log, encoding="utf-8", errors="replace").read()
vtext = open(verify_log, encoding="utf-8", errors="replace").read()

def f(pattern, default="0"):
    m = re.search(pattern, text)
    return m.group(1) if m else default

def vf(pattern, default="nan"):
    m = re.search(pattern, vtext)
    return m.group(1) if m else default

pr_time = float(f(r"PR time\s*:\s*([0-9.eE+-]+)"))
total_time = float(f(r"Total time\s*:\s*([0-9.eE+-]+)"))
comm_time = float(f(r"Comm time\s*:\s*([0-9.eE+-]+)"))
dangling = float(f(r"Dangling reduce time\s*:\s*([0-9.eE+-]+)"))
diff = float(f(r"Diff reduce time\s*:\s*([0-9.eE+-]+)"))
allg = float(f(r"Allgatherv time\s*:\s*([0-9.eE+-]+)"))
iters = int(f(r"Iterations\s*:\s*([0-9]+)"))
max_error = vf(r"Max \|err\|\s*:\s*([0-9.eE+-]+)")
comm_fraction = comm_time / pr_time if pr_time > 0 else 0.0

nodes = re.search(r"Work nodes\s*:\s*min=([0-9]+)\s+avg=([0-9.eE+-]+)\s+max=([0-9]+)", text)
edges = re.search(r"Work inedges\s*:\s*min=([0-9]+)\s+avg=([0-9.eE+-]+)\s+max=([0-9]+)\s+imbalance=([0-9.eE+-]+)", text)
node_vals = nodes.groups() if nodes else ("0", "0", "0")
edge_vals = edges.groups() if edges else ("0", "0", "0", "0")

print(",".join([
    dataset, mode, variant, ranks, threads, workers, rep,
    f"{pr_time:.9f}", f"{total_time:.9f}", f"{comm_time:.9f}",
    f"{comm_fraction:.9f}", f"{dangling:.9f}", f"{diff:.9f}",
    f"{allg:.9f}", str(iters), max_error, status,
    node_vals[0], node_vals[1], node_vals[2],
    edge_vals[0], edge_vals[1], edge_vals[2], edge_vals[3],
]))
PYEOF
)

            echo "$ROW" >> "$RAW_CSV"
            PR_TIME=$(printf "%s\n" "$ROW" | awk -F, '{print $8}')
            COMM_FRAC=$(printf "%s\n" "$ROW" | awk -F, '{print $11}')
            MAX_ERR=$(printf "%s\n" "$ROW" | awk -F, '{print $16}')
            echo "  status=$STATUS, PR=$PR_TIME s, comm_frac=$COMM_FRAC, max_err=$MAX_ERR"
        done
    done
done

"$PYTHON" - "$RAW_CSV" "$SUMMARY_CSV" <<'PYEOF'
import csv
import math
import statistics
import sys
from collections import defaultdict

raw_csv, summary_csv = sys.argv[1:]
rows = []
with open(raw_csv, newline="") as f:
    rows.extend(csv.DictReader(f))

groups = defaultdict(list)
for row in rows:
    key = (
        row["dataset"], row["mode"], row["variant"],
        int(row["ranks"]), int(row["threads"]), int(row["total_workers"]),
    )
    groups[key].append(row)

avg_pr_by_combo = {}
for key, rs in groups.items():
    dataset, mode, variant, ranks, threads, workers = key
    avg_pr = statistics.mean(float(r["pr_time_s"]) for r in rs)
    avg_pr_by_combo[(dataset, mode, variant, ranks, threads, workers)] = avg_pr

variant_order = {
    "no_inv_static": 0,
    "inv_static": 1,
    "no_inv_dynamic": 2,
    "inv_dynamic": 3,
}

fieldnames = [
    "dataset", "mode", "variant", "ranks", "threads", "total_workers", "runs",
    "pr_time_min_s", "pr_time_avg_s", "pr_time_median_s",
    "total_time_avg_s", "comm_time_avg_s", "comm_fraction_avg",
    "dangling_reduce_avg_s", "diff_reduce_avg_s", "allgatherv_avg_s",
    "iterations", "max_error_max", "status",
    "work_nodes_min", "work_nodes_avg", "work_nodes_max",
    "work_inedges_min", "work_inedges_avg", "work_inedges_max",
    "work_imbalance", "speedup_vs_no_inv_static",
]

with open(summary_csv, "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    for key in sorted(groups, key=lambda k: (k[3], k[4], variant_order.get(k[2], 99))):
        dataset, mode, variant, ranks, threads, workers = key
        rs = groups[key]
        pr = [float(r["pr_time_s"]) for r in rs]
        total = [float(r["total_time_s"]) for r in rs]
        comm = [float(r["comm_time_s"]) for r in rs]
        comm_frac = [float(r["comm_fraction"]) for r in rs]
        dang = [float(r["dangling_reduce_s"]) for r in rs]
        diff = [float(r["diff_reduce_s"]) for r in rs]
        allg = [float(r["allgatherv_s"]) for r in rs]
        errs = [float(r["max_error"]) for r in rs if r["max_error"] != "nan"]
        avg_pr = statistics.mean(pr)
        base = avg_pr_by_combo.get((dataset, mode, "no_inv_static", ranks, threads, workers))
        speedup = base / avg_pr if base and avg_pr > 0 else 0.0
        status = "PASS" if all(r["status"] == "PASS" for r in rs) else "FAIL"
        writer.writerow({
            "dataset": dataset,
            "mode": mode,
            "variant": variant,
            "ranks": ranks,
            "threads": threads,
            "total_workers": workers,
            "runs": len(rs),
            "pr_time_min_s": f"{min(pr):.9f}",
            "pr_time_avg_s": f"{avg_pr:.9f}",
            "pr_time_median_s": f"{statistics.median(pr):.9f}",
            "total_time_avg_s": f"{statistics.mean(total):.9f}",
            "comm_time_avg_s": f"{statistics.mean(comm):.9f}",
            "comm_fraction_avg": f"{statistics.mean(comm_frac):.9f}",
            "dangling_reduce_avg_s": f"{statistics.mean(dang):.9f}",
            "diff_reduce_avg_s": f"{statistics.mean(diff):.9f}",
            "allgatherv_avg_s": f"{statistics.mean(allg):.9f}",
            "iterations": rs[0]["iterations"],
            "max_error_max": f"{max(errs) if errs else math.nan:.6e}",
            "status": status,
            "work_nodes_min": min(int(r["work_nodes_min"]) for r in rs),
            "work_nodes_avg": f"{statistics.mean(float(r['work_nodes_avg']) for r in rs):.2f}",
            "work_nodes_max": max(int(r["work_nodes_max"]) for r in rs),
            "work_inedges_min": min(int(r["work_inedges_min"]) for r in rs),
            "work_inedges_avg": f"{statistics.mean(float(r['work_inedges_avg']) for r in rs):.2f}",
            "work_inedges_max": max(int(r["work_inedges_max"]) for r in rs),
            "work_imbalance": f"{statistics.mean(float(r['work_imbalance']) for r in rs):.6f}",
            "speedup_vs_no_inv_static": f"{speedup:.9f}",
        })
PYEOF

echo ""
echo "[done] wrote $RAW_CSV"
echo "[done] wrote $SUMMARY_CSV"
