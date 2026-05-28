#!/bin/bash -l
# Formal Dardel multi-node MPI experiment for Pengyu Wang's scaling section.
#
# Submit on two exclusive CPU nodes:
#   sbatch run_mpi_dardel_multinode.sh
#
# If the course allocation cannot access main, retry explicitly on shared:
#   sbatch -p shared run_mpi_dardel_multinode.sh
#
# In either case the profilers abort unless P >= 2 actually spans two hosts.

#SBATCH -J pagerank_mpi_multinode
#SBATCH -A edu26.DD2356
#SBATCH -p main
#SBATCH -t 01:00:00
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=8
#SBATCH --cpus-per-task=1
#SBATCH --hint=nomultithread
#SBATCH -o results/dardel_multinode_%j.out
#SBATCH -e results/dardel_multinode_%j.err

set -euo pipefail

cd "${SLURM_SUBMIT_DIR:-$HOME/DD2356-PageRank}"
mkdir -p results

RANKS="${RANKS:-1 2 4 8 16}"
REPEAT="${REPEAT:-5}"
MODE="${MODE:-directed}"
SYNTHETIC_GRAPH="${SYNTHETIC_GRAPH:-data/synthetic/synthetic_100k_1m.csv}"
PLACEMENT_CSV="results/dardel_multinode_placement.csv"

export CC="${CC:-gcc}"
export MPICC="${MPICC:-cc}"
export MPI_RUNNER="${MPI_RUNNER:-srun}"
export MPI_NP_FLAG="${MPI_NP_FLAG:--n}"
export MPI_PLACEMENT="dardel_two_node_balanced"
export PLACEMENT_CSV

ALLOCATED_HOSTS=$(scontrol show hostnames "$SLURM_JOB_NODELIST" | sort -u | paste -sd';' -)
ALLOCATED_NODE_COUNT=$(scontrol show hostnames "$SLURM_JOB_NODELIST" | sort -u | wc -l | tr -d ' ')
if [ "$ALLOCATED_NODE_COUNT" -lt 2 ]; then
    echo "This experiment requires two allocated Dardel compute nodes; found $ALLOCATED_NODE_COUNT ($ALLOCATED_HOSTS)." >&2
    exit 1
fi

echo "========================================"
echo " DD2356 MPI Dardel multi-node experiment"
echo "========================================"
echo "SLURM job      : ${SLURM_JOB_ID:-unknown}"
echo "Allocated nodes: $ALLOCATED_HOSTS"
echo "Ranks          : $RANKS"
echo "Repeat         : $REPEAT"
echo "Placement      : P=1 on one node; P>=2 balanced across two nodes"
echo ""

printf "profile,dataset,mode,scaling_mode,ranks,step_nodes,ranks_per_node,node_hosts\n" > "$PLACEMENT_CSV"

python3 tools/generate_graph.py --preset all
python3 tools/generate_graph.py --preset weak

OUTPUT_PREFIX=dardel_multinode_ \
REPEAT="$REPEAT" \
./mpi/profile_mpi.sh "$SYNTHETIC_GRAPH" "$MODE" "$RANKS"

OUTPUT_PREFIX=dardel_multinode_course_ \
REPEAT="$REPEAT" \
./mpi/profile_mpi.sh data/polblogs.csv directed "$RANKS"

PLATFORM=dardel_multinode \
REPEAT="$REPEAT" \
GENERATE_WEAK_GRAPHS=0 \
./mpi/profile_mpi_weak.sh directed "$RANKS"

echo ""
echo "Dardel multi-node experiment outputs:"
ls -1 \
    results/dardel_multinode_placement.csv \
    results/mpi_scaling_dardel_multinode_synthetic_100k_1m_directed.csv \
    results/mpi_scaling_dardel_multinode_synthetic_100k_1m_directed_raw.csv \
    results/mpi_scaling_dardel_multinode_course_polblogs_directed.csv \
    results/mpi_scaling_dardel_multinode_course_polblogs_directed_raw.csv \
    results/mpi_weak_scaling_dardel_multinode_directed.csv \
    results/mpi_weak_scaling_dardel_multinode_directed_raw.csv
