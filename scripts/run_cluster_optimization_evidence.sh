#!/usr/bin/env bash
# Formal optimization and parallel-efficiency evidence for DD2356 Medium CPU Only.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

REPEAT="${REPEAT:-10}"
WARMUP="${WARMUP:-1}"
COMBOS="${COMBOS:-1x1 1x2 1x4 1x8 1x16 2x8 4x4 8x2 16x1}"
PYTHON="${PYTHON:-python3}"

export CC="${CC:-gcc}"
export MPICC="${MPICC:-mpicc}"
export OPENMP_CFLAGS="${OPENMP_CFLAGS:--fopenmp}"
export OPENMP_LDFLAGS="${OPENMP_LDFLAGS:-$OPENMP_CFLAGS}"
export MPI_RUNNER="${MPI_RUNNER:-mpirun}"
export MPI_NP_FLAG="${MPI_NP_FLAG:--np}"
export MPI_BIND_BY_THREADS="${MPI_BIND_BY_THREADS:-1}"
export THREAD_WORK_PROFILE="${THREAD_WORK_PROFILE:-1}"
export REQUIRE_1X1_BASELINE="${REQUIRE_1X1_BASELINE:-1}"

REGULAR_CSV="results/optimization_ablation_cluster_optpe_synthetic_100k_1m_directed.csv"
SKEWED_CSV="results/optimization_ablation_cluster_optpe_skewed_100k_1m_directed.csv"

mkdir -p results results/figures/cluster_optimization

CPU_COUNT="$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc)"
if [ "$CPU_COUNT" -lt 16 ]; then
    echo "This formal workflow needs at least 16 online CPUs; select DD2356 - Medium CPU Only." >&2
    exit 1
fi

echo "========================================"
echo " DD2356 Wang Optimization Evidence"
echo "========================================"
echo "Host           : $(hostname)"
echo "Datasets       : synthetic_100k_1m, skewed_100k_1m"
echo "Combos         : $COMBOS"
echo "Variants       : no_inv_static inv_static no_inv_dynamic inv_dynamic"
echo "Repeat         : $REPEAT"
echo "Warmup         : $WARMUP"
echo "Online CPUs    : $CPU_COUNT"
echo ""

{
    date
    hostname
    uname -a
    echo "online_cpus=$CPU_COUNT"
    command -v "$CC"
    "$CC" --version | sed -n '1p'
    command -v "$MPICC"
    "$MPICC" --showme:command 2>/dev/null || true
    command -v "$MPI_RUNNER"
    "$MPI_RUNNER" --version | sed -n '1,2p'
    echo "OMP_PLACES=${OMP_PLACES:-cores}"
    echo "OMP_PROC_BIND=${OMP_PROC_BIND:-close}"
    echo "MPI_BIND_BY_THREADS=$MPI_BIND_BY_THREADS"
} | tee results/cluster_optimization_environment.log

"$PYTHON" tools/generate_graph.py --preset all
"$PYTHON" tools/generate_graph.py --preset optimization

{
    echo "OpenMPI binding probes; each rank requests the threads used by its layout."
    for PROBE_COMBO in 1x16 4x4 16x1; do
        PROBE_RANKS="${PROBE_COMBO%x*}"
        PROBE_THREADS="${PROBE_COMBO#*x}"
        echo ""
        echo "combo=$PROBE_COMBO"
        "$MPI_RUNNER" --report-bindings --bind-to core --map-by "slot:PE=${PROBE_THREADS}" \
            "$MPI_NP_FLAG" "$PROBE_RANKS" hostname
    done
} > results/cluster_optimization_binding.log 2>&1

OUTPUT_PREFIX=cluster_optpe_ REPEAT="$REPEAT" WARMUP="$WARMUP" \
    ./mpi/profile_optimization_ablation.sh data/synthetic/synthetic_100k_1m.csv directed "$COMBOS"

OUTPUT_PREFIX=cluster_optpe_ REPEAT="$REPEAT" WARMUP="$WARMUP" \
    ./mpi/profile_optimization_ablation.sh data/synthetic/skewed_100k_1m.csv directed "$COMBOS"

"$PYTHON" tools/analyze_optimization_results.py "$REGULAR_CSV" "$SKEWED_CSV" \
    --expected-runs "$REPEAT" \
    --out results/optimization_evidence_cluster.md \
    --figure-dir results/figures/cluster_optimization

tar -czf wang_cluster_optimization_results.tar.gz \
    results/optimization_ablation_cluster_optpe_*.csv \
    results/cluster_optimization_*.log \
    results/optimization_evidence_cluster.md \
    results/figures/cluster_optimization/*

echo ""
echo "Formal optimization experiment complete."
echo "Download this archive from JupyterLab: wang_cluster_optimization_results.tar.gz"
