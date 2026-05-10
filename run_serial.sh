#!/bin/bash -l
#SBATCH -J pagerank_serial
#SBATCH -A edu26.dd2356
#SBATCH -p shared
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH -t 00:10:00
#SBATCH -o results/dardel_%j.out
#SBATCH -e results/dardel_%j.err

cd $HOME/DD2356-PageRank

echo "=== System Info ==="
hostname
lscpu | grep -E "Model name|Socket|Core\(s\)|Thread|MHz"
free -h | head -2
gcc --version | head -1
echo ""

echo "=== Running all datasets ==="
for entry in \
    "data/polblogs.csv directed" \
    "data/karateDir.csv directed" \
    "data/lesmisDir.csv directed" \
    "data/dolphinsDir.csv directed" \
    "data/NCAA_football.csv directed" \
    "data/dolphins.csv undirected" \
    "data/karate.csv undirected" \
    "data/lesmis.csv undirected" \
    "data/stateborders.csv undirected"
do
    csv=$(echo $entry | cut -d' ' -f1)
    mode=$(echo $entry | cut -d' ' -f2)
    echo "=================================================="
    ./serial/pagerank_serial $csv $mode
done

echo ""
echo "=== polblogs 5次计时 ==="
for i in 1 2 3 4 5; do
    echo -n "Run $i: "
    start=$(date +%s%N)
    ./serial/pagerank_serial data/polblogs.csv directed > /dev/null
    end=$(date +%s%N)
    echo "$(echo "scale=6; ($end - $start) / 1000000000" | bc) s"
done

echo "=== Done ==="
