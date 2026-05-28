#!/bin/bash -l
#SBATCH -J pagerank_gpu_compare
#SBATCH -A edu26.DD2356
#SBATCH -p gpu
#SBATCH -t 01:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=8
#SBATCH --cpus-per-task=2
#SBATCH --hint=nomultithread
#SBATCH -o results/dardel_gpu_%j.out
#SBATCH -e results/dardel_gpu_%j.err

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
mkdir -p results

ml PDC/24.11
ml rocm/6.3.3
ml craype-accel-amd-gfx90a

export CC="${CC:-cc}"
export MPICC="${MPICC:-cc}"
export GPU_CC="${GPU_CC:-cc}"
export OPENMP_CFLAGS="${OPENMP_CFLAGS:--fopenmp}"
export OPENMP_LDFLAGS="${OPENMP_LDFLAGS:-$OPENMP_CFLAGS}"
export GPU_OPENMP_CFLAGS="${GPU_OPENMP_CFLAGS:--fopenmp}"
export GPU_OPENMP_LDFLAGS="${GPU_OPENMP_LDFLAGS:-$GPU_OPENMP_CFLAGS}"
export BUILD_GPU=1
export MPI_RUNNER="${MPI_RUNNER:-srun}"
export MPI_NP_FLAG="${MPI_NP_FLAG:--n}"
export MPI_CPUS_PER_TASK_FLAG="${MPI_CPUS_PER_TASK_FLAG:---cpus-per-task}"
export REPEAT="${REPEAT:-5}"

GRAPH="data/synthetic/synthetic_100k_1m.csv"
MODE="directed"

echo "========================================"
echo " DD2356 Wang Dardel GPU comparison"
echo "========================================"
echo "Host           : $(hostname)"
echo "Job ID         : ${SLURM_JOB_ID:-interactive}"
echo "Graph          : $GRAPH ($MODE)"
echo "GPU variants   : naive persistent"
echo "Hybrid control : 8x2"
echo "Repeat         : $REPEAT"
echo ""
module list 2>&1

./scripts/build_all.sh
python3 tools/generate_graph.py --preset all

echo "[probe] confirmed OpenMP target execution with Cray runtime transfer log"
CRAY_ACC_DEBUG=3 PR_REQUIRE_DEVICE=1 \
    ./openmp/pagerank_openmp_gpu data/karateDir.csv directed \
    0.85 1e-10 1000 results/gpu_device_probe_output.txt persistent \
    > results/dardel_gpu_device_probe.log 2>&1

PLATFORM=dardel_gpu PR_REQUIRE_DEVICE=1 RUN_CORRECTNESS=1 \
    VARIANTS="naive persistent" REPEAT="$REPEAT" \
    ./openmp/profile_gpu.sh "$GRAPH" "$MODE"

OUTPUT_PREFIX=dardel_gpu_ REPEAT="$REPEAT" \
    MPI_RUNNER="$MPI_RUNNER" MPI_NP_FLAG="$MPI_NP_FLAG" \
    MPI_CPUS_PER_TASK_FLAG="$MPI_CPUS_PER_TASK_FLAG" \
    ./mpi/profile_hybrid.sh "$GRAPH" "$MODE" "8x2"

python3 - <<'PYEOF'
import csv

gpu_path = "results/gpu_offload_dardel_gpu_synthetic_100k_1m_directed.csv"
hybrid_path = "results/hybrid_fixedcore_dardel_gpu_synthetic_100k_1m_directed.csv"
out_path = "results/gpu_vs_hybrid_dardel_gpu_synthetic_100k_1m_directed.csv"

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
        "platform": "dardel_gpu",
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
        "platform": "dardel_gpu",
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
fields = list(rows[0])
with open(out_path, "w", newline="") as stream:
    writer = csv.DictWriter(stream, fieldnames=fields)
    writer.writeheader()
    writer.writerows(rows)
print(f"[done] wrote {out_path}")
PYEOF

echo ""
echo "Dardel GPU experiment summaries:"
ls -1 results/gpu_offload_dardel_gpu_synthetic_100k_1m_directed*.csv \
      results/gpu_correctness_dardel_gpu.csv \
      results/hybrid_fixedcore_dardel_gpu_synthetic_100k_1m_directed*.csv \
      results/gpu_vs_hybrid_dardel_gpu_synthetic_100k_1m_directed.csv \
      results/dardel_gpu_device_probe.log
