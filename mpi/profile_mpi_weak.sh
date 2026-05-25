#!/bin/bash
# profile_mpi_weak.sh - true MPI weak scaling profile for DD2356 PageRank.
#
# Weak scaling keeps graph size per MPI rank approximately constant.  The
# default workload is 12,500 nodes and 125,000 directed edges per rank, so the
# 16-rank case uses a 200k-node / 2M-edge graph.
#
# Usage:
#   ./mpi/profile_mpi_weak.sh [directed|undirected] [rank_list]
#
# Examples:
#   PLATFORM=cluster REPEAT=5 ./mpi/profile_mpi_weak.sh
#   PLATFORM=dardel MPI_RUNNER=srun MPI_NP_FLAG=-n REPEAT=5 ./mpi/profile_mpi_weak.sh directed "1 2 4 8 16"

set -euo pipefail

MODE="${1:-directed}"
RANKS="${2:-${RANKS:-1 2 4 8 16}}"
REPEAT="${REPEAT:-1}"
PLATFORM="${PLATFORM:-local}"
MPI_RUNNER="${MPI_RUNNER:-mpirun}"
MPI_NP_FLAG="${MPI_NP_FLAG:--np}"
MPI_FLAGS="${MPI_FLAGS:-}"
MPI_PLACEMENT="${MPI_PLACEMENT:-default}"
PLACEMENT_CSV="${PLACEMENT_CSV:-}"
TOL="${TOL:-1e-6}"
OUTPUT_PREFIX="${OUTPUT_PREFIX:-}"
PYTHON="${PYTHON:-python3}"
CC="${CC:-gcc}"
MPICC="${MPICC:-mpicc}"
WEAK_NODES_PER_RANK="${WEAK_NODES_PER_RANK:-12500}"
WEAK_EDGES_PER_RANK="${WEAK_EDGES_PER_RANK:-125000}"
WEAK_OUTPUT_DIR="${WEAK_OUTPUT_DIR:-data/synthetic}"
GENERATE_WEAK_GRAPHS="${GENERATE_WEAK_GRAPHS:-1}"
WEAK_SEED_BASE="${WEAK_SEED_BASE:-2356}"

SERIAL_BIN="./serial/pagerank_serial"
MPI_BIN="./mpi/pagerank_mpi"
VERIFY_BIN="./verify/verify"

RUN_ID="${OUTPUT_PREFIX}${PLATFORM}_${MODE}"
RAW_CSV="results/mpi_weak_scaling_${RUN_ID}_raw.csv"
SUMMARY_CSV="results/mpi_weak_scaling_${RUN_ID}.csv"

mkdir -p results "$WEAK_OUTPUT_DIR"

configure_step_placement() {
    local np="$1"
    local dataset="$2"
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
                echo "$RUN_ID,$dataset,$MODE,weak,$np,$STEP_NODES,$RANKS_PER_NODE,$NODE_HOSTS" >> "$PLACEMENT_CSV"
            fi
            ;;
        *)
            echo "Unknown MPI_PLACEMENT mode: $MPI_PLACEMENT" >&2
            exit 1
            ;;
    esac
}

weak_seed_for_rank() {
    case "$1" in
        1) echo "$WEAK_SEED_BASE" ;;
        2) echo "$((WEAK_SEED_BASE + 1))" ;;
        4) echo "$((WEAK_SEED_BASE + 2))" ;;
        8) echo "$((WEAK_SEED_BASE + 3))" ;;
        16) echo "$((WEAK_SEED_BASE + 4))" ;;
        *) echo "$((WEAK_SEED_BASE + $1))" ;;
    esac
}

echo "========================================"
echo " DD2356 MPI PageRank - weak scaling"
echo "========================================"
echo "Mode          : $MODE"
echo "Ranks         : $RANKS"
echo "Repeat        : $REPEAT"
echo "Platform      : $PLATFORM"
echo "Per-rank work : ${WEAK_NODES_PER_RANK} nodes, ${WEAK_EDGES_PER_RANK} edges"
echo "MPI runner    : $MPI_RUNNER $MPI_FLAGS $MPI_NP_FLAG <np>"
echo "Placement     : $MPI_PLACEMENT"
echo "Tolerance     : $TOL"
echo ""

echo "[build] serial baseline"
"$CC" -O2 -o "$SERIAL_BIN" serial/pagerank_serial.c -lm

echo "[build] MPI version"
"$MPICC" -O2 -o "$MPI_BIN" mpi/pagerank_mpi.c -lm

echo "[build] verifier"
"$CC" -O2 -o "$VERIFY_BIN" verify/verify_correctness.c -lm

echo "dataset,mode,scaling_mode,ranks,repeat,target_nodes,target_edges,nodes,edges,edges_per_rank,pr_time_s,total_time_s,comm_time_s,dangling_reduce_s,diff_reduce_s,allgatherv_s,iterations,max_error,status,work_nodes_min,work_nodes_avg,work_nodes_max,work_inedges_min,work_inedges_avg,work_inedges_max,work_imbalance,weak_efficiency,step_nodes,ranks_per_node,node_hosts" > "$RAW_CSV"

BASE_PR_TIME=""

for NP in $RANKS; do
    TARGET_NODES=$((NP * WEAK_NODES_PER_RANK))
    TARGET_EDGES=$((NP * WEAK_EDGES_PER_RANK))
    GRAPH="${WEAK_OUTPUT_DIR}/weak_${NP}rank_${TARGET_NODES}_${TARGET_EDGES}.csv"
    BASE_NAME="$(basename "$GRAPH" .csv)"
    NP_TIMES=()

    if [ ! -s "$GRAPH" ]; then
        if [ "$GENERATE_WEAK_GRAPHS" = "1" ]; then
            GRAPH_SEED="$(weak_seed_for_rank "$NP")"
            echo ""
            echo "[generate] $GRAPH ($TARGET_NODES nodes, $TARGET_EDGES edges, seed=$GRAPH_SEED)"
            "$PYTHON" tools/generate_graph.py \
                --nodes "$TARGET_NODES" \
                --edges "$TARGET_EDGES" \
                --seed "$GRAPH_SEED" \
                --output "$GRAPH"
        else
            echo "Missing graph: $GRAPH" >&2
            echo "Set GENERATE_WEAK_GRAPHS=1 or generate it with tools/generate_graph.py." >&2
            exit 1
        fi
    fi

    configure_step_placement "$NP" "$BASE_NAME"

    SERIAL_LOG="results/serial_weak_${RUN_ID}_np${NP}.log"
    echo ""
    echo "[reference] np=$NP graph=$GRAPH"
    "$SERIAL_BIN" "$GRAPH" "$MODE" > "$SERIAL_LOG"

    for REP in $(seq 1 "$REPEAT"); do
        MPI_LOG="results/mpi_weak_${RUN_ID}_np${NP}_r${REP}.log"
        VERIFY_LOG="results/verify_mpi_weak_${RUN_ID}_np${NP}_r${REP}.log"
        MPI_OUT="pagerank_mpi_output_weak_${RUN_ID}_np${NP}_r${REP}.txt"

        echo "[run] np=$NP repeat=$REP/$REPEAT"
        set +e
        if [ "$MPI_PLACEMENT" = "default" ]; then
            # shellcheck disable=SC2086
            "$MPI_RUNNER" $MPI_FLAGS "$MPI_NP_FLAG" "$NP" \
                "$MPI_BIN" "$GRAPH" "$MODE" 0.85 1e-10 1000 "$MPI_OUT" \
                > "$MPI_LOG" < /dev/null
        else
            # shellcheck disable=SC2086
            "$MPI_RUNNER" $MPI_FLAGS "${MPI_STEP_ARGS[@]}" "$MPI_NP_FLAG" "$NP" \
                "$MPI_BIN" "$GRAPH" "$MODE" 0.85 1e-10 1000 "$MPI_OUT" \
                > "$MPI_LOG" < /dev/null
        fi
        RUN_CODE=$?
        if [ "$RUN_CODE" -eq 0 ] && "$VERIFY_BIN" pagerank_serial_output.txt "$MPI_OUT" "$TOL" > "$VERIFY_LOG"; then
            STATUS="PASS"
        else
            STATUS="FAIL"
            if [ "$RUN_CODE" -ne 0 ]; then
                echo "[FAIL] MPI run failed with exit code $RUN_CODE" > "$VERIFY_LOG"
            fi
        fi
        set -e

        ROW=$("$PYTHON" - "$MPI_LOG" "$VERIFY_LOG" "$BASE_PR_TIME" "$NP" "$BASE_NAME" "$MODE" "$REP" "$STATUS" "$TARGET_NODES" "$TARGET_EDGES" "$STEP_NODES" "$RANKS_PER_NODE" "$NODE_HOSTS" <<'PYEOF'
import re
import sys

(
    mpi_log,
    verify_log,
    base_pr,
    np_s,
    dataset,
    mode,
    rep,
    status,
    target_nodes_s,
    target_edges_s,
    step_nodes,
    ranks_per_node,
    node_hosts,
) = sys.argv[1:]

np = int(np_s)
target_nodes = int(target_nodes_s)
target_edges = int(target_edges_s)
text = open(mpi_log, encoding="utf-8", errors="replace").read()
vtext = open(verify_log, encoding="utf-8", errors="replace").read()

def f(pattern, default="0"):
    m = re.search(pattern, text)
    return m.group(1) if m else default

def vf(pattern, default="nan"):
    m = re.search(pattern, vtext)
    return m.group(1) if m else default

nodes_total = int(f(r"Nodes\s*:\s*([0-9]+)", str(target_nodes)))
edges_total = int(f(r"Edges\s*:\s*([0-9]+)", str(target_edges)))
edges_per_rank = edges_total / np if np else 0.0
pr_time = float(f(r"PR time\s*:\s*([0-9.eE+-]+)"))
total_time = float(f(r"Total time\s*:\s*([0-9.eE+-]+)"))
comm_time = float(f(r"Comm time\s*:\s*([0-9.eE+-]+)"))
dangling = float(f(r"Dangling reduce time\s*:\s*([0-9.eE+-]+)"))
diff = float(f(r"Diff reduce time\s*:\s*([0-9.eE+-]+)"))
allg = float(f(r"Allgatherv time\s*:\s*([0-9.eE+-]+)"))
iters = int(f(r"Iterations\s*:\s*([0-9]+)"))
max_error = vf(r"Max \|err\|\s*:\s*([0-9.eE+-]+)")

nodes = re.search(r"Work nodes\s*:\s*min=([0-9]+)\s+avg=([0-9.eE+-]+)\s+max=([0-9]+)", text)
inedges = re.search(r"Work inedges\s*:\s*min=([0-9]+)\s+avg=([0-9.eE+-]+)\s+max=([0-9]+)\s+imbalance=([0-9.eE+-]+)", text)
node_vals = nodes.groups() if nodes else ("0", "0", "0")
edge_vals = inedges.groups() if inedges else ("0", "0", "0", "0")

base = float(base_pr) if base_pr else pr_time
weak_eff = base / pr_time if pr_time > 0 else 0.0

print(",".join([
    dataset, mode, "weak", str(np), rep,
    str(target_nodes), str(target_edges), str(nodes_total), str(edges_total),
    f"{edges_per_rank:.2f}",
    f"{pr_time:.9f}", f"{total_time:.9f}", f"{comm_time:.9f}",
    f"{dangling:.9f}", f"{diff:.9f}", f"{allg:.9f}",
    str(iters), max_error, status,
    node_vals[0], node_vals[1], node_vals[2],
    edge_vals[0], edge_vals[1], edge_vals[2], edge_vals[3],
    f"{weak_eff:.9f}",
    step_nodes, ranks_per_node, node_hosts,
]))
PYEOF
)

        echo "$ROW" >> "$RAW_CSV"
        PR_TIME=$(printf "%s\n" "$ROW" | awk -F, '{print $11}')
        MAX_ERR=$(printf "%s\n" "$ROW" | awk -F, '{print $18}')
        COMM_TIME=$(printf "%s\n" "$ROW" | awk -F, '{print $13}')
        WEAK_EFF=$(printf "%s\n" "$ROW" | awk -F, '{print $27}')
        NP_TIMES+=("$PR_TIME")

        echo "  status=$STATUS, PR=$PR_TIME s, comm=$COMM_TIME s, weak_eff=$WEAK_EFF, max_err=$MAX_ERR"
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
    rows.extend(csv.DictReader(f))

groups = defaultdict(list)
for row in rows:
    groups[(row["dataset"], row["mode"], int(row["ranks"]))].append(row)

base_key = min(groups, key=lambda k: k[2]) if groups else None
base_avg = None
if base_key:
    base_avg = statistics.mean(float(r["pr_time_s"]) for r in groups[base_key])

fieldnames = [
    "dataset", "mode", "scaling_mode", "ranks", "runs",
    "target_nodes", "target_edges", "nodes", "edges", "edges_per_rank",
    "pr_time_min_s", "pr_time_avg_s", "pr_time_median_s",
    "total_time_avg_s", "comm_time_avg_s", "comm_fraction_avg",
    "dangling_reduce_avg_s", "diff_reduce_avg_s", "allgatherv_avg_s",
    "iterations", "max_error_max", "status",
    "work_nodes_min", "work_nodes_avg", "work_nodes_max",
    "work_inedges_min", "work_inedges_avg", "work_inedges_max",
    "work_imbalance", "weak_efficiency",
    "step_nodes", "ranks_per_node", "node_hosts",
]

with open(summary_csv, "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames, lineterminator="\n")
    writer.writeheader()
    for key in sorted(groups, key=lambda k: k[2]):
        dataset, mode, ranks = key
        rs = groups[key]
        pr = [float(r["pr_time_s"]) for r in rs]
        total = [float(r["total_time_s"]) for r in rs]
        comm = [float(r["comm_time_s"]) for r in rs]
        dang = [float(r["dangling_reduce_s"]) for r in rs]
        diff = [float(r["diff_reduce_s"]) for r in rs]
        allg = [float(r["allgatherv_s"]) for r in rs]
        errs = [float(r["max_error"]) for r in rs if r["max_error"] != "nan"]
        avg_pr = statistics.mean(pr)
        weak_eff = (base_avg / avg_pr) if base_avg and avg_pr > 0 else 0.0
        status = "PASS" if all(r["status"] == "PASS" for r in rs) else "FAIL"
        comm_frac = statistics.mean((c / p if p > 0 else 0.0) for c, p in zip(comm, pr))
        writer.writerow({
            "dataset": dataset,
            "mode": mode,
            "scaling_mode": "weak",
            "ranks": ranks,
            "runs": len(rs),
            "target_nodes": rs[0]["target_nodes"],
            "target_edges": rs[0]["target_edges"],
            "nodes": rs[0]["nodes"],
            "edges": rs[0]["edges"],
            "edges_per_rank": f"{statistics.mean(float(r['edges_per_rank']) for r in rs):.2f}",
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
            "weak_efficiency": f"{weak_eff:.9f}",
            "step_nodes": rs[0]["step_nodes"],
            "ranks_per_node": rs[0]["ranks_per_node"],
            "node_hosts": rs[0]["node_hosts"],
        })
PYEOF

echo ""
echo "[done] wrote $RAW_CSV"
echo "[done] wrote $SUMMARY_CSV"
