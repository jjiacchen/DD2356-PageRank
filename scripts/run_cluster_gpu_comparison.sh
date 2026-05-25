#!/usr/bin/env bash
# Run Wang's confirmed-device GPU comparison in the DD2356 Small GPU
# Jupyter server. The server provides at most eight CPU cores and one
# shared NVIDIA MIG GPU, so the CPU control is Hybrid 4x2.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
mkdir -p results

PLATFORM="${PLATFORM:-cluster_gpu}"
GRAPH="${GRAPH:-data/synthetic/synthetic_100k_1m.csv}"
MODE="${MODE:-directed}"
REPEAT="${REPEAT:-5}"
HYBRID_COMBO="${HYBRID_COMBO:-4x2}"
ENV_LOG="results/${PLATFORM}_environment.log"
PROBE_OUT="results/${PLATFORM}_device_probe_output.txt"
PROBE_LOG="results/${PLATFORM}_device_probe.log"
ARCHIVE="${ARCHIVE:-wang_cluster_gpu_results.tar.gz}"
RUN_TAG="$(id -un 2>/dev/null || printf 'jupyter')"
RUN_TAG="${RUN_TAG:-jupyter}"

echo "========================================"
echo " DD2356 Wang Cluster GPU comparison"
echo "========================================"
echo "Host           : $(hostname)"
echo "Graph          : $GRAPH ($MODE)"
echo "GPU variants   : naive persistent"
echo "Hybrid control : $HYBRID_COMBO (eight CPU workers)"
echo "Repeat         : $REPEAT"
echo ""

{
    echo "=== GPU environment evidence ==="
    date
    hostname
    uname -a
    echo ""
    command -v nvidia-smi
    nvidia-smi -L
    nvidia-smi --query-gpu=name,uuid,memory.total,driver_version --format=csv,noheader
    echo ""
    command -v gcc || true
    gcc --version 2>/dev/null | head -1 || true
    command -v nvc || true
    nvc --version 2>/dev/null | head -2 || true
    command -v mpicc || true
    mpicc --showme:command 2>/dev/null || true
} 2>&1 | tee "$ENV_LOG"

if ! command -v nvidia-smi >/dev/null 2>&1; then
    echo "nvidia-smi is unavailable: restart the Jupyter server with DD2356 - Small GPU." >&2
    exit 1
fi

python3 tools/generate_graph.py --preset all

try_gpu_compiler() {
    local label="$1"
    local compiler="$2"
    local cflags="$3"
    local ldflags="$4"
    local build_log="results/${PLATFORM}_compiler_${label}_build.log"
    local run_log="results/${PLATFORM}_compiler_${label}_run.log"
    local bin="/tmp/pagerank_gpu_probe_${RUN_TAG}_${label}"
    local out="/tmp/pagerank_gpu_probe_${RUN_TAG}_${label}.txt"
    if ! command -v "$compiler" >/dev/null 2>&1; then
        return 1
    fi
    echo "[probe] trying $label: $compiler $cflags"
    # shellcheck disable=SC2086
    if ! "$compiler" -O2 $cflags -o "$bin" openmp/pagerank_openmp_gpu.c $ldflags -lm \
        > "$build_log" 2>&1; then
        echo "  compile failed (see $build_log)"
        return 1
    fi
    if ! PR_REQUIRE_DEVICE=1 "$bin" data/karateDir.csv directed \
        0.85 1e-10 1000 "$out" persistent > "$run_log" 2>&1; then
        echo "  binary did not execute on the target device (see $run_log)"
        return 1
    fi
    if ! grep -q "Target executed on device: YES" "$run_log"; then
        echo "  device proof missing from $run_log"
        return 1
    fi
    export GPU_CC="$compiler"
    export GPU_OPENMP_CFLAGS="$cflags"
    export GPU_OPENMP_LDFLAGS="$ldflags"
    cp "$run_log" "$PROBE_LOG"
    cp "$out" "$PROBE_OUT"
    echo "  selected $label; confirmed target device execution"
    return 0
}

# NVIDIA HPC SDK has the most direct OpenMP GPU interface when installed.
# Ubuntu's GCC build defaults to CET for the x86 host; explicitly disable it
# because the NVPTX offload target does not support -fcf-protection.
if try_gpu_compiler "nvc" "nvc" "-mp=gpu" "-mp=gpu"; then
    :
elif try_gpu_compiler "gcc_nvptx_nocet" "gcc" "-fopenmp -foffload=nvptx-none -fcf-protection=none" "-fopenmp -foffload=nvptx-none -fcf-protection=none"; then
    :
elif try_gpu_compiler "gcc_configured_nocet" "gcc" "-fopenmp -fcf-protection=none" "-fopenmp -fcf-protection=none"; then
    :
else
    echo "" >&2
    echo "No installed compiler produced confirmed OpenMP target execution." >&2
    echo "Please send results/${PLATFORM}_environment.log and results/${PLATFORM}_compiler_* logs back for diagnosis." >&2
    exit 2
fi

export CC="${CC:-gcc}"
export MPICC="${MPICC:-mpicc}"
export OPENMP_CFLAGS="${OPENMP_CFLAGS:--fopenmp}"
export OPENMP_LDFLAGS="${OPENMP_LDFLAGS:-$OPENMP_CFLAGS}"
export PR_REQUIRE_DEVICE=1

PLATFORM="$PLATFORM" PR_REQUIRE_DEVICE=1 RUN_CORRECTNESS=1 \
    VARIANTS="naive persistent" REPEAT="$REPEAT" \
    ./openmp/profile_gpu.sh "$GRAPH" "$MODE"

MPI_RUNNER="${MPI_RUNNER:-mpirun}"
MPI_NP_FLAG="${MPI_NP_FLAG:--np}"
MPI_FLAGS="${MPI_FLAGS:---bind-to core --map-by slot:PE=2}"
OUTPUT_PREFIX="${PLATFORM}_"
export MPI_RUNNER MPI_NP_FLAG MPI_FLAGS OUTPUT_PREFIX
REPEAT="$REPEAT" MPI_CPUS_PER_TASK_FLAG="" \
    ./mpi/profile_hybrid.sh "$GRAPH" "$MODE" "$HYBRID_COMBO"

python3 - "$PLATFORM" "$GRAPH" "$MODE" <<'PYEOF'
import csv
import pathlib
import sys

platform, graph, mode = sys.argv[1:]
dataset = pathlib.Path(graph).stem
gpu_path = f"results/gpu_offload_{platform}_{dataset}_{mode}.csv"
hybrid_path = f"results/hybrid_fixedcore_{platform}_{dataset}_{mode}.csv"
out_path = f"results/gpu_vs_hybrid_{platform}_{dataset}_{mode}.csv"

with open(gpu_path, newline="") as stream:
    gpu = list(csv.DictReader(stream))
with open(hybrid_path, newline="") as stream:
    hybrid = list(csv.DictReader(stream))
serial = next(row for row in gpu if row["implementation"] == "serial")
serial_pr = float(serial["pr_time_avg_s"])
rows = []
for row in gpu:
    pr = float(row["pr_time_avg_s"])
    rows.append({
        "platform": platform,
        "implementation": row["implementation"],
        "configuration": row["variant"],
        "dataset": row["dataset"],
        "mode": row["mode"],
        "pr_time_avg_s": row["pr_time_avg_s"],
        "total_time_avg_s": row["total_time_avg_s"],
        "speedup_vs_serial": f"{serial_pr / pr:.9f}",
        "executed_on_device": row["executed_on_device"],
        "status": row["status"],
    })
for row in hybrid:
    pr = float(row["pr_time_avg_s"])
    rows.append({
        "platform": platform,
        "implementation": "hybrid",
        "configuration": f"{row['ranks']}x{row['threads']}",
        "dataset": row["dataset"],
        "mode": row["mode"],
        "pr_time_avg_s": row["pr_time_avg_s"],
        "total_time_avg_s": row["total_time_avg_s"],
        "speedup_vs_serial": f"{serial_pr / pr:.9f}",
        "executed_on_device": "N/A",
        "status": row["status"],
    })
with open(out_path, "w", newline="") as stream:
    writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
    writer.writeheader()
    writer.writerows(rows)
print(f"[done] wrote {out_path}")
PYEOF

tar -czf "$ARCHIVE" \
    results/gpu_offload_"${PLATFORM}"_*.csv \
    results/gpu_correctness_"${PLATFORM}".csv \
    results/hybrid_fixedcore_"${PLATFORM}"_*.csv \
    results/gpu_vs_hybrid_"${PLATFORM}"_*.csv \
    results/"${PLATFORM}"_environment.log \
    results/"${PLATFORM}"_device_probe.log \
    results/"${PLATFORM}"_compiler_*.log

echo ""
echo "Cluster GPU experiment complete."
echo "Download this archive from JupyterLab: $ARCHIVE"
