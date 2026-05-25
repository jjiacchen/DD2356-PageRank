#!/bin/bash
# profile_mpi.sh - DD2356 MPI PageRank scaling and correctness script
#
# Usage:
#   ./mpi/profile_mpi.sh [csv_file] [directed|undirected] [rank_list]
#
# Examples:
#   ./mpi/profile_mpi.sh data/polblogs.csv directed "1 2 4 8"
#   REPEAT=5 ./mpi/profile_mpi.sh data/polblogs.csv directed "1 2 4"
#   MPI_RUNNER=srun MPI_NP_FLAG=-n ./mpi/profile_mpi.sh data/polblogs.csv directed "1 2 4"

set -e

GRAPH="${1:-data/polblogs.csv}"
MODE="${2:-directed}"
RANKS="${3:-1 2 4 8}"
REPEAT="${REPEAT:-1}"
MPI_RUNNER="${MPI_RUNNER:-mpirun}"
MPI_NP_FLAG="${MPI_NP_FLAG:--np}"
MPI_FLAGS="${MPI_FLAGS:-}"
MPI_PLACEMENT="${MPI_PLACEMENT:-default}"
PLACEMENT_CSV="${PLACEMENT_CSV:-}"
TOL="${TOL:-1e-6}"
SCALING_MODE="${SCALING_MODE:-strong}"
OUTPUT_PREFIX="${OUTPUT_PREFIX:-}"
PYTHON="${PYTHON:-python3}"
CC="${CC:-gcc}"
MPICC="${MPICC:-mpicc}"

SERIAL_BIN="./serial/pagerank_serial"
MPI_BIN="./mpi/pagerank_mpi"
VERIFY_BIN="./verify/verify"

mkdir -p results

BASE_NAME="$(basename "$GRAPH" .csv)"
RUN_ID="${OUTPUT_PREFIX}${BASE_NAME}_${MODE}"
RAW_CSV="results/mpi_scaling_${RUN_ID}_raw.csv"
SUMMARY_CSV="results/mpi_scaling_${RUN_ID}.csv"
SERIAL_LOG="results/serial_${RUN_ID}.log"

configure_step_placement() {
    local np="$1"
    local dataset="$2"
    local scaling_mode="$3"
    local probe_output observed_nodes

    MPI_STEP_ARGS=()
    STEP_NODES="unspecified"
    RANKS_PER_NODE="unspecified"
    NODE_HOSTS="not_recorded"

    case "$MPI_PLACEMENT" in
        default)
            return
            ;;
        dardel_two_node_balanced)
            if [ "$np" -eq 1 ]; then
                STEP_NODES=1
                RANKS_PER_NODE=1
            elif [ $((np % 2)) -eq 0 ]; then
                STEP_NODES=2
                RANKS_PER_NODE=$((np / 2))
            else
                echo "Placement mode $MPI_PLACEMENT requires rank count 1 or an even rank count; got $np." >&2
                exit 1
            fi
            MPI_STEP_ARGS=(
                -N "$STEP_NODES"
                --ntasks-per-node="$RANKS_PER_NODE"
                --distribution=block:block
                --hint=nomultithread
            )
            # Probe placement separately so hostname collection is excluded from timings.
            # shellcheck disable=SC2086
            probe_output=$("$MPI_RUNNER" $MPI_FLAGS "${MPI_STEP_ARGS[@]}" "$MPI_NP_FLAG" "$np" hostname)
            NODE_HOSTS=$(printf "%s\n" "$probe_output" | awk 'NF' | sort -u | paste -sd';' -)
            observed_nodes=$(printf "%s\n" "$probe_output" | awk 'NF' | sort -u | wc -l | tr -d ' ')
            if [ "$observed_nodes" -ne "$STEP_NODES" ]; then
                echo "Placement probe failed for np=$np: expected $STEP_NODES nodes, observed $observed_nodes ($NODE_HOSTS)." >&2
                exit 1
            fi
            if [ -n "$PLACEMENT_CSV" ]; then
                if [ ! -s "$PLACEMENT_CSV" ]; then
                    echo "profile,dataset,mode,scaling_mode,ranks,step_nodes,ranks_per_node,node_hosts" > "$PLACEMENT_CSV"
                fi
                echo "$RUN_ID,$dataset,$MODE,$scaling_mode,$np,$STEP_NODES,$RANKS_PER_NODE,$NODE_HOSTS" >> "$PLACEMENT_CSV"
            fi
            ;;
        *)
            echo "Unknown MPI_PLACEMENT mode: $MPI_PLACEMENT" >&2
            exit 1
            ;;
    esac
}

echo "========================================"
echo " DD2356 MPI PageRank - scaling profile"
echo "========================================"
echo "Graph        : $GRAPH ($MODE)"
echo "Ranks        : $RANKS"
echo "Repeat       : $REPEAT"
echo "Scaling mode : $SCALING_MODE"
echo "MPI runner   : $MPI_RUNNER $MPI_FLAGS $MPI_NP_FLAG <np>"
echo "Placement    : $MPI_PLACEMENT"
echo "Tolerance    : $TOL"
echo ""

echo "[build] serial baseline"
"$CC" -O2 -o "$SERIAL_BIN" serial/pagerank_serial.c -lm

echo "[build] MPI version"
"$MPICC" -O2 -o "$MPI_BIN" mpi/pagerank_mpi.c -lm

echo "[build] verifier"
"$CC" -O2 -o "$VERIFY_BIN" verify/verify_correctness.c -lm

echo ""
echo "[reference] generating serial golden output"
"$SERIAL_BIN" "$GRAPH" "$MODE" > "$SERIAL_LOG"

echo "dataset,mode,scaling_mode,ranks,repeat,pr_time_s,total_time_s,comm_time_s,dangling_reduce_s,diff_reduce_s,allgatherv_s,iterations,max_error,status,work_nodes_min,work_nodes_avg,work_nodes_max,work_inedges_min,work_inedges_avg,work_inedges_max,work_imbalance,speedup,parallel_efficiency,step_nodes,ranks_per_node,node_hosts" > "$RAW_CSV"

BASE_PR_TIME=""

for NP in $RANKS; do
    NP_TIMES=()
    configure_step_placement "$NP" "$BASE_NAME" "$SCALING_MODE"

    for REP in $(seq 1 "$REPEAT"); do
        MPI_LOG="results/mpi_${RUN_ID}_np${NP}_r${REP}.log"
        VERIFY_LOG="results/verify_mpi_${RUN_ID}_np${NP}_r${REP}.log"
        MPI_OUT="pagerank_mpi_output_${RUN_ID}_np${NP}_r${REP}.txt"

        echo ""
        echo "[run] np=$NP repeat=$REP/$REPEAT"
        if [ "$MPI_PLACEMENT" = "default" ]; then
            # shellcheck disable=SC2086
            "$MPI_RUNNER" $MPI_FLAGS "$MPI_NP_FLAG" "$NP" "$MPI_BIN" "$GRAPH" "$MODE" 0.85 1e-10 1000 "$MPI_OUT" > "$MPI_LOG"
        else
            # shellcheck disable=SC2086
            "$MPI_RUNNER" $MPI_FLAGS "${MPI_STEP_ARGS[@]}" "$MPI_NP_FLAG" "$NP" "$MPI_BIN" "$GRAPH" "$MODE" 0.85 1e-10 1000 "$MPI_OUT" > "$MPI_LOG"
        fi

        if "$VERIFY_BIN" pagerank_serial_output.txt "$MPI_OUT" "$TOL" > "$VERIFY_LOG"; then
            STATUS="PASS"
        else
            STATUS="FAIL"
        fi

        ROW=$("$PYTHON" - "$MPI_LOG" "$VERIFY_LOG" "$BASE_PR_TIME" "$NP" "$BASE_NAME" "$MODE" "$SCALING_MODE" "$REP" "$STATUS" "$STEP_NODES" "$RANKS_PER_NODE" "$NODE_HOSTS" <<'PYEOF'
import re
import sys

(
    mpi_log, verify_log, base_pr, np_s, dataset, mode, scaling_mode, rep,
    status, step_nodes, ranks_per_node, node_hosts,
) = sys.argv[1:]
np = int(np_s)
text = open(mpi_log, encoding="utf-8", errors="replace").read()
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

nodes = re.search(r"Work nodes\s*:\s*min=([0-9]+)\s+avg=([0-9.eE+-]+)\s+max=([0-9]+)", text)
edges = re.search(r"Work inedges\s*:\s*min=([0-9]+)\s+avg=([0-9.eE+-]+)\s+max=([0-9]+)\s+imbalance=([0-9.eE+-]+)", text)
node_vals = nodes.groups() if nodes else ("0", "0", "0")
edge_vals = edges.groups() if edges else ("0", "0", "0", "0")

base = float(base_pr) if base_pr else pr_time
speedup = base / pr_time if pr_time > 0 else 0.0
eff = speedup / np if np > 0 else 0.0

print(",".join([
    dataset, mode, scaling_mode, str(np), rep,
    f"{pr_time:.9f}", f"{total_time:.9f}", f"{comm_time:.9f}",
    f"{dangling:.9f}", f"{diff:.9f}", f"{allg:.9f}",
    str(iters), max_error, status,
    node_vals[0], node_vals[1], node_vals[2],
    edge_vals[0], edge_vals[1], edge_vals[2], edge_vals[3],
    f"{speedup:.9f}", f"{eff:.9f}",
    step_nodes, ranks_per_node, node_hosts,
]))
PYEOF
)

        echo "$ROW" >> "$RAW_CSV"
        PR_TIME=$(printf "%s\n" "$ROW" | awk -F, '{print $6}')
        MAX_ERR=$(printf "%s\n" "$ROW" | awk -F, '{print $13}')
        COMM_TIME=$(printf "%s\n" "$ROW" | awk -F, '{print $8}')
        NP_TIMES+=("$PR_TIME")

        if [ "$STATUS" != "PASS" ]; then
            echo "  status=$STATUS, PR=$PR_TIME s, comm=$COMM_TIME s, max_err=$MAX_ERR"
        else
            echo "  status=PASS, PR=$PR_TIME s, comm=$COMM_TIME s, max_err=$MAX_ERR"
        fi
    done

    if [ -z "$BASE_PR_TIME" ]; then
        BASE_PR_TIME=$("$PYTHON" - "${NP_TIMES[@]}" <<'PYEOF'
import statistics
import sys
vals = [float(x) for x in sys.argv[1:]]
print(f"{statistics.mean(vals):.9f}")
PYEOF
)
    fi
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
    for row in csv.DictReader(f):
        rows.append(row)

groups = defaultdict(list)
for row in rows:
    groups[(row["dataset"], row["mode"], row["scaling_mode"], int(row["ranks"]))].append(row)

base_key = min(groups, key=lambda k: k[3]) if groups else None
base_avg = None
if base_key:
    base_avg = statistics.mean(float(r["pr_time_s"]) for r in groups[base_key])

fieldnames = [
    "dataset", "mode", "scaling_mode", "ranks", "runs",
    "pr_time_min_s", "pr_time_avg_s", "pr_time_median_s",
    "total_time_avg_s", "comm_time_avg_s", "comm_fraction_avg",
    "dangling_reduce_avg_s", "diff_reduce_avg_s", "allgatherv_avg_s",
    "iterations", "max_error_max", "status",
    "work_nodes_min", "work_nodes_avg", "work_nodes_max",
    "work_inedges_min", "work_inedges_avg", "work_inedges_max",
    "work_imbalance", "speedup", "parallel_efficiency",
    "step_nodes", "ranks_per_node", "node_hosts",
]

with open(summary_csv, "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    for key in sorted(groups, key=lambda k: k[3]):
        dataset, mode, scaling_mode, ranks = key
        rs = groups[key]
        pr = [float(r["pr_time_s"]) for r in rs]
        total = [float(r["total_time_s"]) for r in rs]
        comm = [float(r["comm_time_s"]) for r in rs]
        dang = [float(r["dangling_reduce_s"]) for r in rs]
        diff = [float(r["diff_reduce_s"]) for r in rs]
        allg = [float(r["allgatherv_s"]) for r in rs]
        errs = [float(r["max_error"]) for r in rs if r["max_error"] != "nan"]
        avg_pr = statistics.mean(pr)
        speedup = (base_avg / avg_pr) if base_avg and avg_pr > 0 else 0.0
        eff = speedup / ranks if ranks else 0.0
        status = "PASS" if all(r["status"] == "PASS" for r in rs) else "FAIL"
        comm_frac = statistics.mean((c / p if p > 0 else 0.0) for c, p in zip(comm, pr))
        writer.writerow({
            "dataset": dataset,
            "mode": mode,
            "scaling_mode": scaling_mode,
            "ranks": ranks,
            "runs": len(rs),
            "pr_time_min_s": f"{min(pr):.9f}",
            "pr_time_avg_s": f"{avg_pr:.9f}",
            "pr_time_median_s": f"{statistics.median(pr):.9f}",
            "total_time_avg_s": f"{statistics.mean(total):.9f}",
            "comm_time_avg_s": f"{statistics.mean(comm):.9f}",
            "comm_fraction_avg": f"{comm_frac:.9f}",
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
            "speedup": f"{speedup:.9f}",
            "parallel_efficiency": f"{eff:.9f}",
            "step_nodes": rs[0]["step_nodes"],
            "ranks_per_node": rs[0]["ranks_per_node"],
            "node_hosts": rs[0]["node_hosts"],
        })
PYEOF

echo ""
echo "[done] wrote $RAW_CSV"
echo "[done] wrote $SUMMARY_CSV"
