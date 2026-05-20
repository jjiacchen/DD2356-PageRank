#!/bin/bash
# test_mpi_all.sh - run MPI correctness tests on all course datasets.
#
# Usage:
#   ./mpi/test_mpi_all.sh
#   RANKS="1 2 4 8" ./mpi/test_mpi_all.sh
#   MPI_RUNNER=srun MPI_NP_FLAG=-n ./mpi/test_mpi_all.sh

set -e

RANKS="${RANKS:-1 2 4}"
MPI_RUNNER="${MPI_RUNNER:-mpirun}"
MPI_NP_FLAG="${MPI_NP_FLAG:--np}"
MPI_FLAGS="${MPI_FLAGS:-}"
TOL="${TOL:-1e-6}"
PYTHON="${PYTHON:-python3}"
CC="${CC:-gcc}"
MPICC="${MPICC:-mpicc}"

SERIAL_BIN="./serial/pagerank_serial"
MPI_BIN="./mpi/pagerank_mpi"
VERIFY_BIN="./verify/verify"
SUMMARY="results/mpi_correctness_summary.csv"

mkdir -p results

echo "========================================"
echo " DD2356 MPI PageRank - all correctness"
echo "========================================"
echo "Ranks      : $RANKS"
echo "MPI runner : $MPI_RUNNER $MPI_FLAGS $MPI_NP_FLAG <np>"
echo "Tolerance  : $TOL"
echo ""

echo "[build] serial baseline"
"$CC" -O2 -o "$SERIAL_BIN" serial/pagerank_serial.c -lm

echo "[build] MPI version"
"$MPICC" -O2 -o "$MPI_BIN" mpi/pagerank_mpi.c -lm

echo "[build] verifier"
"$CC" -O2 -o "$VERIFY_BIN" verify/verify_correctness.c -lm

echo "dataset,mode,ranks,status,max_error,l1_error,l2_error,iterations,pr_time_s,comm_time_s,total_time_s" > "$SUMMARY"

OVERALL=0

while read -r GRAPH MODE; do
    [ -z "$GRAPH" ] && continue
    BASE_NAME="$(basename "$GRAPH" .csv)"
    SERIAL_LOG="results/serial_correctness_${BASE_NAME}_${MODE}.log"

    echo ""
    echo "[reference] $GRAPH ($MODE)"
    "$SERIAL_BIN" "$GRAPH" "$MODE" > "$SERIAL_LOG"

    for NP in $RANKS; do
        MPI_LOG="results/mpi_correctness_${BASE_NAME}_${MODE}_np${NP}.log"
        VERIFY_LOG="results/verify_correctness_${BASE_NAME}_${MODE}_np${NP}.log"
        MPI_OUT="pagerank_mpi_output_${BASE_NAME}_${MODE}_np${NP}.txt"

        echo "[run] $BASE_NAME $MODE np=$NP"
        set +e
        # shellcheck disable=SC2086
        "$MPI_RUNNER" $MPI_FLAGS "$MPI_NP_FLAG" "$NP" "$MPI_BIN" "$GRAPH" "$MODE" 0.85 1e-10 1000 "$MPI_OUT" > "$MPI_LOG" < /dev/null
        RUN_CODE=$?
        if [ "$RUN_CODE" -eq 0 ]; then
            "$VERIFY_BIN" pagerank_serial_output.txt "$MPI_OUT" "$TOL" > "$VERIFY_LOG"
            VERIFY_CODE=$?
        else
            VERIFY_CODE=1
            echo "[FAIL] MPI run failed with exit code $RUN_CODE" > "$VERIFY_LOG"
        fi
        set -e

        if [ "$RUN_CODE" -eq 0 ] && [ "$VERIFY_CODE" -eq 0 ]; then
            STATUS="PASS"
        else
            STATUS="FAIL"
            OVERALL=1
        fi

        ROW=$("$PYTHON" - "$BASE_NAME" "$MODE" "$NP" "$STATUS" "$MPI_LOG" "$VERIFY_LOG" <<'PYEOF'
import re
import sys

dataset, mode, ranks, status, mpi_log, verify_log = sys.argv[1:]
text = open(mpi_log, encoding="utf-8", errors="replace").read() if mpi_log else ""
vtext = open(verify_log, encoding="utf-8", errors="replace").read() if verify_log else ""

def f(pattern, src, default="nan"):
    m = re.search(pattern, src)
    return m.group(1) if m else default

print(",".join([
    dataset,
    mode,
    ranks,
    status,
    f(r"Max \|err\|\s*:\s*([0-9.eE+-]+)", vtext),
    f(r"L1\s+error\s*:\s*([0-9.eE+-]+)", vtext),
    f(r"L2\s+error\s*:\s*([0-9.eE+-]+)", vtext),
    f(r"Iterations\s*:\s*([0-9]+)", text),
    f(r"PR time\s*:\s*([0-9.eE+-]+)", text),
    f(r"Comm time\s*:\s*([0-9.eE+-]+)", text),
    f(r"Total time\s*:\s*([0-9.eE+-]+)", text),
]))
PYEOF
)
        echo "$ROW" >> "$SUMMARY"

        MAX_ERR=$(printf "%s\n" "$ROW" | awk -F, '{print $5}')
        echo "  $STATUS max_err=$MAX_ERR"
    done
done <<'EOF'
data/polblogs.csv directed
data/karateDir.csv directed
data/lesmisDir.csv directed
data/dolphinsDir.csv directed
data/NCAA_football.csv directed
data/dolphins.csv undirected
data/karate.csv undirected
data/lesmis.csv undirected
data/stateborders.csv undirected
EOF

echo ""
echo "[done] wrote $SUMMARY"
exit "$OVERALL"
