#!/usr/bin/env bash
# Run Wang's Dardel CPU experiments from inside an interactive allocation.
#
# Allocate first, for example:
#   salloc -t 03:00:00 -A edu26.DD2356 -p shared --nodes=1 --ntasks=16 --cpus-per-task=1
#
# Then run:
#   ./scripts/run_dardel_wang_experiments.sh

set -euo pipefail

export CC="${CC:-gcc}"
export MPICC="${MPICC:-cc}"
export OPENMP_CFLAGS="${OPENMP_CFLAGS:--fopenmp}"
export OPENMP_LDFLAGS="${OPENMP_LDFLAGS:-$OPENMP_CFLAGS}"
export BUILD_GPU="${BUILD_GPU:-0}"
export MPI_RUNNER="${MPI_RUNNER:-srun}"
export MPI_NP_FLAG="${MPI_NP_FLAG:--n}"
export MPI_CPUS_PER_TASK_FLAG="${MPI_CPUS_PER_TASK_FLAG:---cpus-per-task}"
export REPEAT="${REPEAT:-5}"

RANKS="${RANKS:-1 2 4 8 16}"
HYBRID_COMBOS="${HYBRID_COMBOS:-1x16 2x8 4x4 8x2 16x1}"
ABLATION_COMBOS="${ABLATION_COMBOS:-1x16 4x4}"
GRAPH="${GRAPH:-data/synthetic/synthetic_100k_1m.csv}"
MODE="${MODE:-directed}"

echo "========================================"
echo " DD2356 Wang Dardel experiments"
echo "========================================"
echo "Ranks          : $RANKS"
echo "Hybrid combos  : $HYBRID_COMBOS"
echo "Ablation combos: $ABLATION_COMBOS"
echo "Repeat         : $REPEAT"
echo "MPI runner     : $MPI_RUNNER $MPI_NP_FLAG <np>"
echo "CPU flag       : $MPI_CPUS_PER_TASK_FLAG <threads>"
echo ""

./scripts/build_all.sh
python3 tools/generate_graph.py --preset all
python3 tools/generate_graph.py --preset weak

MPI_RUNNER="$MPI_RUNNER" MPI_NP_FLAG="$MPI_NP_FLAG" ./mpi/test_mpi_all.sh

OUTPUT_PREFIX=dardel_ REPEAT="$REPEAT" MPI_RUNNER="$MPI_RUNNER" MPI_NP_FLAG="$MPI_NP_FLAG" \
    ./mpi/profile_mpi.sh "$GRAPH" "$MODE" "$RANKS"

OUTPUT_PREFIX=dardel_course_ REPEAT="$REPEAT" MPI_RUNNER="$MPI_RUNNER" MPI_NP_FLAG="$MPI_NP_FLAG" \
    ./mpi/profile_mpi.sh data/polblogs.csv directed "$RANKS"

PLATFORM=dardel REPEAT="$REPEAT" MPI_RUNNER="$MPI_RUNNER" MPI_NP_FLAG="$MPI_NP_FLAG" \
    ./mpi/profile_mpi_weak.sh directed "$RANKS"

OUTPUT_PREFIX=dardel_ REPEAT="$REPEAT" MPI_RUNNER="$MPI_RUNNER" MPI_NP_FLAG="$MPI_NP_FLAG" \
    MPI_CPUS_PER_TASK_FLAG="$MPI_CPUS_PER_TASK_FLAG" \
    ./mpi/profile_hybrid.sh "$GRAPH" "$MODE" "$HYBRID_COMBOS"

OUTPUT_PREFIX=dardel_ REPEAT="$REPEAT" MPI_RUNNER="$MPI_RUNNER" MPI_NP_FLAG="$MPI_NP_FLAG" \
    MPI_CPUS_PER_TASK_FLAG="$MPI_CPUS_PER_TASK_FLAG" \
    ./mpi/profile_optimization_ablation.sh "$GRAPH" "$MODE" "$ABLATION_COMBOS"

echo ""
echo "Dardel experiment summaries:"
ls -1 results/mpi_scaling_dardel_*.csv \
      results/mpi_weak_scaling_dardel_*.csv \
      results/hybrid_fixedcore_dardel_*.csv \
      results/optimization_ablation_dardel_*.csv
