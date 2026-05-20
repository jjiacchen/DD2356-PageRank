#!/bin/bash -l
#SBATCH -J pagerank_mpi_dardel
#SBATCH -A edu26.dd2356
#SBATCH -p shared
#SBATCH --nodes=1
#SBATCH --ntasks=32
#SBATCH --cpus-per-task=1
#SBATCH -t 00:30:00
#SBATCH -o results/dardel_mpi_%j.out
#SBATCH -e results/dardel_mpi_%j.err

set -e

cd "${SLURM_SUBMIT_DIR:-$HOME/DD2356-PageRank}"
mkdir -p results

# Dardel module names can change between course images. Keep this explicit
# but optional so the script is safe before confirming the environment:
#   MODULES="gcc/12.2.0 cray-mpich" sbatch run_mpi_dardel.sh
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
OUTPUT_PREFIX="${OUTPUT_PREFIX:-dardel_${SLURM_JOB_ID:-local}_}"

echo "=== Dardel MPI PageRank job ==="
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
