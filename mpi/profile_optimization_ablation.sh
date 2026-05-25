#!/usr/bin/env bash
# profile_optimization_ablation.sh - before/after profiling for Hybrid MPI+OpenMP optimizations.
#
# Formal cluster usage is driven by scripts/run_cluster_optimization_evidence.sh.
# For a quick local check:
#   OUTPUT_PREFIX=smoke_ REPEAT=1 THREAD_WORK_PROFILE=1 REQUIRE_1X1_BASELINE=1 \
#     ./mpi/profile_optimization_ablation.sh data/synthetic/synthetic_1k_10k.csv directed "1x1 1x2"

set -euo pipefail

GRAPH="${1:-data/synthetic/synthetic_100k_1m.csv}"
MODE="${2:-directed}"
COMBOS="${3:-1x16 4x4}"
REPEAT="${REPEAT:-10}"
WARMUP="${WARMUP:-0}"
VARIANTS="${VARIANTS:-no_inv_static inv_static no_inv_dynamic inv_dynamic}"
MPI_RUNNER="${MPI_RUNNER:-mpirun}"
MPI_NP_FLAG="${MPI_NP_FLAG:--np}"
MPI_CPUS_PER_TASK_FLAG="${MPI_CPUS_PER_TASK_FLAG:-}"
MPI_BIND_BY_THREADS="${MPI_BIND_BY_THREADS:-0}"
MPI_FLAGS="${MPI_FLAGS:-}"
THREAD_WORK_PROFILE="${THREAD_WORK_PROFILE:-0}"
REQUIRE_1X1_BASELINE="${REQUIRE_1X1_BASELINE:-0}"
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

if [ "$REQUIRE_1X1_BASELINE" = "1" ]; then
    HAS_BASELINE=0
    for COMBO in $COMBOS; do
        if [ "$COMBO" = "1x1" ]; then
            HAS_BASELINE=1
        fi
    done
    if [ "$HAS_BASELINE" -ne 1 ]; then
        echo "Formal efficiency mode requires a 1x1 combo baseline." >&2
        exit 1
    fi
fi

echo "========================================"
echo " DD2356 Hybrid Optimization Ablation"
echo "========================================"
echo "Graph          : $GRAPH ($MODE)"
echo "Combos         : $COMBOS"
echo "Variants       : $VARIANTS"
echo "Repeat         : $REPEAT"
echo "Warmup         : $WARMUP"
echo "Thread profile : $THREAD_WORK_PROFILE"
echo "MPI runner     : $MPI_RUNNER $MPI_FLAGS $MPI_NP_FLAG <np>"
if [ "$MPI_BIND_BY_THREADS" = "1" ]; then
    echo "CPU binding    : --bind-to core --map-by slot:PE=<threads>"
elif [ -n "$MPI_CPUS_PER_TASK_FLAG" ]; then
    echo "CPU binding    : $MPI_CPUS_PER_TASK_FLAG <threads>"
fi
echo "Tolerance      : $TOL"
echo "Output         : $SUMMARY_CSV"
echo ""

echo "[build] serial baseline"
"$CC" -O2 -o "$SERIAL_BIN" serial/pagerank_serial.c -lm

echo "[build] verifier"
"$CC" -O2 -o "$VERIFY_BIN" verify/verify_correctness.c -lm

echo ""
echo "[reference] generating serial golden output"
"$SERIAL_BIN" "$GRAPH" "$MODE" > "$SERIAL_LOG"

echo "dataset,mode,variant,ranks,threads,total_workers,repeat,pr_time_s,total_time_s,comm_time_s,comm_fraction,dangling_reduce_s,diff_reduce_s,allgatherv_s,update_time_s,iterations,max_error,status,work_nodes_min,work_nodes_avg,work_nodes_max,work_inedges_min,work_inedges_avg,work_inedges_max,work_imbalance,thread_inedges_min,thread_inedges_avg,thread_inedges_max,thread_imbalance,thread_workers" > "$RAW_CSV"

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

        run_hybrid() {
            local probe_enabled="$1"
            local output_path="$2"
            if [ "$MPI_BIND_BY_THREADS" = "1" ]; then
                # shellcheck disable=SC2086
                PR_PROFILE_THREAD_WORK="$probe_enabled" OMP_NUM_THREADS="$THREADS" OMP_PLACES="${OMP_PLACES:-cores}" OMP_PROC_BIND="${OMP_PROC_BIND:-close}" \
                    "$MPI_RUNNER" $MPI_FLAGS --bind-to core --map-by "slot:PE=${THREADS}" "$MPI_NP_FLAG" "$RANKS" \
                    "$HYBRID_BIN" "$GRAPH" "$MODE" "$THREADS" 0.85 1e-10 1000 "$output_path"
            elif [ -n "$MPI_CPUS_PER_TASK_FLAG" ]; then
                # shellcheck disable=SC2086
                PR_PROFILE_THREAD_WORK="$probe_enabled" OMP_NUM_THREADS="$THREADS" OMP_PLACES="${OMP_PLACES:-cores}" OMP_PROC_BIND="${OMP_PROC_BIND:-close}" \
                    "$MPI_RUNNER" $MPI_FLAGS "$MPI_NP_FLAG" "$RANKS" "$MPI_CPUS_PER_TASK_FLAG" "$THREADS" \
                    "$HYBRID_BIN" "$GRAPH" "$MODE" "$THREADS" 0.85 1e-10 1000 "$output_path"
            else
                # shellcheck disable=SC2086
                PR_PROFILE_THREAD_WORK="$probe_enabled" OMP_NUM_THREADS="$THREADS" OMP_PLACES="${OMP_PLACES:-cores}" OMP_PROC_BIND="${OMP_PROC_BIND:-close}" \
                    "$MPI_RUNNER" $MPI_FLAGS "$MPI_NP_FLAG" "$RANKS" \
                    "$HYBRID_BIN" "$GRAPH" "$MODE" "$THREADS" 0.85 1e-10 1000 "$output_path"
            fi
        }

        if [ "$WARMUP" -gt 0 ]; then
            for WARM in $(seq 1 "$WARMUP"); do
                WARM_LOG="results/ablation_${RUN_ID}_${VARIANT}_${COMBO}_warmup${WARM}.log"
                WARM_OUT="pagerank_hybrid_ablation_output_${RUN_ID}_${VARIANT}_${COMBO}_warmup${WARM}.txt"
                echo "[warmup] variant=$VARIANT combo=$COMBO run=$WARM/$WARMUP"
                run_hybrid 0 "$WARM_OUT" > "$WARM_LOG" < /dev/null
            done
        fi

        for REP in $(seq 1 "$REPEAT"); do
            HYBRID_LOG="results/ablation_${RUN_ID}_${VARIANT}_${COMBO}_r${REP}.log"
            VERIFY_LOG="results/verify_ablation_${RUN_ID}_${VARIANT}_${COMBO}_r${REP}.log"
            HYBRID_OUT="pagerank_hybrid_ablation_output_${RUN_ID}_${VARIANT}_${COMBO}_r${REP}.txt"

            echo ""
            echo "[run] variant=$VARIANT combo=$COMBO repeat=$REP/$REPEAT"
            set +e
            run_hybrid "$THREAD_WORK_PROFILE" "$HYBRID_OUT" > "$HYBRID_LOG" < /dev/null
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
    match = re.search(pattern, text)
    return match.group(1) if match else default

def vf(pattern, default="nan"):
    match = re.search(pattern, vtext)
    return match.group(1) if match else default

pr_time = float(f(r"PR time\s*:\s*([0-9.eE+-]+)"))
total_time = float(f(r"Total time\s*:\s*([0-9.eE+-]+)"))
comm_time = float(f(r"Comm time\s*:\s*([0-9.eE+-]+)"))
dangling = float(f(r"Dangling reduce time\s*:\s*([0-9.eE+-]+)"))
diff = float(f(r"Diff reduce time\s*:\s*([0-9.eE+-]+)"))
allg = float(f(r"Allgatherv time\s*:\s*([0-9.eE+-]+)"))
update = float(f(r"Update kernel time\s*:\s*([0-9.eE+-]+)"))
iters = int(f(r"Iterations\s*:\s*([0-9]+)"))
max_error = vf(r"Max \|err\|\s*:\s*([0-9.eE+-]+)")
comm_fraction = comm_time / pr_time if pr_time > 0 else 0.0

nodes = re.search(r"Work nodes\s*:\s*min=([0-9]+)\s+avg=([0-9.eE+-]+)\s+max=([0-9]+)", text)
edges = re.search(r"Work inedges\s*:\s*min=([0-9]+)\s+avg=([0-9.eE+-]+)\s+max=([0-9]+)\s+imbalance=([0-9.eE+-]+)", text)
thread_edges = re.search(
    r"Thread work inedges\s*:\s*min=([0-9]+)\s+avg=([0-9.eE+-]+)\s+max=([0-9]+)\s+imbalance=([0-9.eE+-]+)\s+workers=([0-9]+)",
    text,
)
node_vals = nodes.groups() if nodes else ("0", "0", "0")
edge_vals = edges.groups() if edges else ("0", "0", "0", "0")
thread_vals = thread_edges.groups() if thread_edges else ("0", "0", "0", "0", "0")

print(",".join([
    dataset, mode, variant, ranks, threads, workers, rep,
    f"{pr_time:.9f}", f"{total_time:.9f}", f"{comm_time:.9f}",
    f"{comm_fraction:.9f}", f"{dangling:.9f}", f"{diff:.9f}",
    f"{allg:.9f}", f"{update:.9f}", str(iters), max_error, status,
    node_vals[0], node_vals[1], node_vals[2],
    edge_vals[0], edge_vals[1], edge_vals[2], edge_vals[3],
    thread_vals[0], thread_vals[1], thread_vals[2], thread_vals[3], thread_vals[4],
]))
PYEOF
)

            echo "$ROW" >> "$RAW_CSV"
            PR_TIME=$(printf "%s\n" "$ROW" | awk -F, '{print $8}')
            UPDATE_TIME=$(printf "%s\n" "$ROW" | awk -F, '{print $15}')
            MAX_ERR=$(printf "%s\n" "$ROW" | awk -F, '{print $17}')
            THREAD_IMBALANCE=$(printf "%s\n" "$ROW" | awk -F, '{print $29}')
            echo "  status=$STATUS, PR=$PR_TIME s, update=$UPDATE_TIME s, thread_imbalance=$THREAD_IMBALANCE, max_err=$MAX_ERR"
        done
    done
done

"$PYTHON" - "$RAW_CSV" "$SUMMARY_CSV" "$REQUIRE_1X1_BASELINE" <<'PYEOF'
import csv
import math
import statistics
import sys
from collections import defaultdict

raw_csv, summary_csv, require_baseline = sys.argv[1:]
require_baseline = require_baseline == "1"
with open(raw_csv, newline="", encoding="utf-8") as handle:
    rows = list(csv.DictReader(handle))

groups = defaultdict(list)
for row in rows:
    key = (
        row["dataset"], row["mode"], row["variant"],
        int(row["ranks"]), int(row["threads"]), int(row["total_workers"]),
    )
    groups[key].append(row)

variant_order = {
    "no_inv_static": 0,
    "inv_static": 1,
    "no_inv_dynamic": 2,
    "inv_dynamic": 3,
}

avg_pr = {key: statistics.mean(float(row["pr_time_s"]) for row in group) for key, group in groups.items()}
avg_update = {key: statistics.mean(float(row["update_time_s"]) for row in group) for key, group in groups.items()}
variant_baselines = {}
for key, value in avg_pr.items():
    dataset, mode, variant, ranks, threads, workers = key
    if (ranks, threads, workers) == (1, 1, 1):
        variant_baselines[(dataset, mode, variant)] = value

if require_baseline:
    missing = []
    for dataset, mode, variant, _, _, _ in groups:
        if (dataset, mode, variant) not in variant_baselines:
            missing.append(f"{dataset}/{mode}/{variant}")
    if missing:
        raise SystemExit("missing 1x1 efficiency baselines: " + ", ".join(sorted(set(missing))))

fieldnames = [
    "dataset", "mode", "variant", "ranks", "threads", "total_workers", "runs",
    "pr_time_min_s", "pr_time_avg_s", "pr_time_median_s",
    "total_time_avg_s", "comm_time_avg_s", "comm_fraction_avg",
    "dangling_reduce_avg_s", "diff_reduce_avg_s", "allgatherv_avg_s",
    "update_time_avg_s", "iterations", "max_error_max", "status",
    "work_nodes_min", "work_nodes_avg", "work_nodes_max",
    "work_inedges_min", "work_inedges_avg", "work_inedges_max", "work_imbalance",
    "thread_inedges_min", "thread_inedges_avg", "thread_inedges_max",
    "thread_imbalance", "thread_workers",
    "speedup_vs_no_inv_static", "update_speedup_vs_no_inv_static",
    "speedup_vs_variant_1x1", "parallel_efficiency_vs_variant_1x1",
    "efficiency_delta_vs_no_inv_static",
]

with open(summary_csv, "w", newline="", encoding="utf-8") as handle:
    writer = csv.DictWriter(handle, fieldnames=fieldnames, lineterminator="\n")
    writer.writeheader()
    for key in sorted(groups, key=lambda item: (item[5], item[3], item[4], variant_order.get(item[2], 99))):
        dataset, mode, variant, ranks, threads, workers = key
        group = groups[key]
        pr = [float(row["pr_time_s"]) for row in group]
        total = [float(row["total_time_s"]) for row in group]
        comm = [float(row["comm_time_s"]) for row in group]
        comm_frac = [float(row["comm_fraction"]) for row in group]
        dang = [float(row["dangling_reduce_s"]) for row in group]
        diff = [float(row["diff_reduce_s"]) for row in group]
        allg = [float(row["allgatherv_s"]) for row in group]
        update = [float(row["update_time_s"]) for row in group]
        errors = [float(row["max_error"]) for row in group if row["max_error"] != "nan"]
        this_pr = avg_pr[key]
        this_update = avg_update[key]
        before_key = (dataset, mode, "no_inv_static", ranks, threads, workers)
        before_pr = avg_pr.get(before_key)
        before_update = avg_update.get(before_key)
        own_base = variant_baselines.get((dataset, mode, variant))
        before_base = variant_baselines.get((dataset, mode, "no_inv_static"))
        speedup_before = before_pr / this_pr if before_pr and this_pr > 0 else None
        update_speedup = before_update / this_update if before_update and this_update > 0 else None
        scaling_speedup = own_base / this_pr if own_base and this_pr > 0 else None
        efficiency = scaling_speedup / workers if scaling_speedup is not None else None
        before_efficiency = (
            (before_base / before_pr) / workers
            if before_base and before_pr and before_pr > 0 else None
        )
        efficiency_delta = (
            efficiency - before_efficiency
            if efficiency is not None and before_efficiency is not None else None
        )
        status = "PASS" if all(row["status"] == "PASS" for row in group) else "FAIL"
        writer.writerow({
            "dataset": dataset,
            "mode": mode,
            "variant": variant,
            "ranks": ranks,
            "threads": threads,
            "total_workers": workers,
            "runs": len(group),
            "pr_time_min_s": f"{min(pr):.9f}",
            "pr_time_avg_s": f"{this_pr:.9f}",
            "pr_time_median_s": f"{statistics.median(pr):.9f}",
            "total_time_avg_s": f"{statistics.mean(total):.9f}",
            "comm_time_avg_s": f"{statistics.mean(comm):.9f}",
            "comm_fraction_avg": f"{statistics.mean(comm_frac):.9f}",
            "dangling_reduce_avg_s": f"{statistics.mean(dang):.9f}",
            "diff_reduce_avg_s": f"{statistics.mean(diff):.9f}",
            "allgatherv_avg_s": f"{statistics.mean(allg):.9f}",
            "update_time_avg_s": f"{this_update:.9f}",
            "iterations": group[0]["iterations"],
            "max_error_max": f"{max(errors) if errors else math.nan:.6e}",
            "status": status,
            "work_nodes_min": min(int(row["work_nodes_min"]) for row in group),
            "work_nodes_avg": f"{statistics.mean(float(row['work_nodes_avg']) for row in group):.2f}",
            "work_nodes_max": max(int(row["work_nodes_max"]) for row in group),
            "work_inedges_min": min(int(row["work_inedges_min"]) for row in group),
            "work_inedges_avg": f"{statistics.mean(float(row['work_inedges_avg']) for row in group):.2f}",
            "work_inedges_max": max(int(row["work_inedges_max"]) for row in group),
            "work_imbalance": f"{statistics.mean(float(row['work_imbalance']) for row in group):.6f}",
            "thread_inedges_min": f"{statistics.mean(float(row['thread_inedges_min']) for row in group):.2f}",
            "thread_inedges_avg": f"{statistics.mean(float(row['thread_inedges_avg']) for row in group):.2f}",
            "thread_inedges_max": f"{statistics.mean(float(row['thread_inedges_max']) for row in group):.2f}",
            "thread_imbalance": f"{statistics.mean(float(row['thread_imbalance']) for row in group):.6f}",
            "thread_workers": max(int(row["thread_workers"]) for row in group),
            "speedup_vs_no_inv_static": f"{speedup_before:.9f}" if speedup_before is not None else "",
            "update_speedup_vs_no_inv_static": f"{update_speedup:.9f}" if update_speedup is not None else "",
            "speedup_vs_variant_1x1": f"{scaling_speedup:.9f}" if scaling_speedup is not None else "",
            "parallel_efficiency_vs_variant_1x1": f"{efficiency:.9f}" if efficiency is not None else "",
            "efficiency_delta_vs_no_inv_static": f"{efficiency_delta:.9f}" if efficiency_delta is not None else "",
        })
PYEOF

echo ""
echo "[done] wrote $RAW_CSV"
echo "[done] wrote $SUMMARY_CSV"
