#!/bin/bash -l
#SBATCH -J pagerank_mpi
#SBATCH -A edu26.dd2356
#SBATCH -p shared
#SBATCH --nodes=1
#SBATCH --ntasks=16
#SBATCH --cpus-per-task=1
#SBATCH -t 00:20:00
#SBATCH -o results/mpi_%j.out
#SBATCH -e results/mpi_%j.err

set -e

cd "${SLURM_SUBMIT_DIR:-$HOME/DD2356-PageRank}"
mkdir -p results

GRAPH="${GRAPH:-data/polblogs.csv}"
MODE="${MODE:-directed}"
RANKS="${RANKS:-1 2 4 8 16}"
REPEAT="${REPEAT:-3}"
TOL="${TOL:-1e-6}"
OUTPUT_PREFIX="${OUTPUT_PREFIX:-slurm_${SLURM_JOB_ID:-local}_}"

# Optional module setup. Example:
#   MODULES="gcc openmpi" sbatch run_mpi.sh
if [ -n "${MODULES:-}" ] && command -v module >/dev/null 2>&1; then
    for MOD in $MODULES; do
        module load "$MOD"
    done
fi

echo "=== System Info ==="
hostname
lscpu | grep -E "Model name|Socket|Core\(s\)|Thread|MHz" || true
free -h | head -2 || true
mpicc --version | head -1
echo ""

MPI_RUNNER="${MPI_RUNNER:-srun}" \
MPI_NP_FLAG="${MPI_NP_FLAG:--n}" \
CC="${CC:-gcc}" \
MPICC="${MPICC:-mpicc}" \
REPEAT="$REPEAT" \
TOL="$TOL" \
SCALING_MODE="${SCALING_MODE:-strong}" \
OUTPUT_PREFIX="$OUTPUT_PREFIX" \
./mpi/profile_mpi.sh "$GRAPH" "$MODE" "$RANKS"
