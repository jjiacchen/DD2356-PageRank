#!/bin/bash -l
#SBATCH -J pagerank_mpi_cluster
#SBATCH --nodes=1
#SBATCH --ntasks=32
#SBATCH --cpus-per-task=1
#SBATCH -t 00:30:00
#SBATCH -o results/cluster_mpi_%j.out
#SBATCH -e results/cluster_mpi_%j.err

set -e

cd "${SLURM_SUBMIT_DIR:-$HOME/DD2356-PageRank}"
mkdir -p results

# Optional school-cluster module setup. Example:
#   MODULES="gcc openmpi" sbatch run_mpi_cluster.sh
if [ -n "${MODULES:-}" ] && command -v module >/dev/null 2>&1; then
    for MOD in $MODULES; do
        module load "$MOD"
    done
fi

GRAPH="${GRAPH:-data/polblogs.csv}"
MODE="${MODE:-directed}"
RANKS="${RANKS:-1 2 4 8 16 32}"
REPEAT="${REPEAT:-5}"
TOL="${TOL:-1e-6}"
OUTPUT_PREFIX="${OUTPUT_PREFIX:-cluster_${SLURM_JOB_ID:-local}_}"

echo "=== School cluster MPI PageRank job ==="
hostname
lscpu | grep -E "Model name|Socket|Core\(s\)|Thread|MHz" || true
mpicc --version | head -1
echo ""

MPI_RUNNER=srun \
MPI_NP_FLAG=-n \
CC="${CC:-gcc}" \
MPICC="${MPICC:-mpicc}" \
REPEAT="$REPEAT" \
TOL="$TOL" \
SCALING_MODE="${SCALING_MODE:-strong}" \
OUTPUT_PREFIX="$OUTPUT_PREFIX" \
./mpi/profile_mpi.sh "$GRAPH" "$MODE" "$RANKS"
