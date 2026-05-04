#!/bin/bash
# profile_serial.sh – DD2356 Serial PageRank 性能分析脚本
#
# 多次计时运行，输出 min/max/avg，并给出 perf/gprof 使用指引。
#
# 用法:
#   chmod +x profile_serial.sh
#   ./profile_serial.sh <csv_file> <directed|undirected> [repeat=5]

set -e
BINARY="./pagerank_serial"
GRAPH="${1:-data/polblogs.csv}"
MODE="${2:-directed}"
REPEAT="${3:-5}"

if [ ! -f "$BINARY" ]; then
    echo "[ERROR] 找不到可执行文件，请先编译："
    echo "  gcc -O2 -o pagerank_serial pagerank_serial.c -lm"
    exit 1
fi

echo "========================================"
echo " DD2356 Serial PageRank – 性能分析"
echo "========================================"
echo "Binary  : $BINARY"
echo "Graph   : $GRAPH  ($MODE)"
echo "Repeats : $REPEAT"
echo ""

TIMES=()
for i in $(seq 1 $REPEAT); do
    echo -n "Run $i/$REPEAT ... "
    START=$(date +%s%N)
    $BINARY "$GRAPH" "$MODE" > /tmp/pr_run_$i.txt 2>&1
    END=$(date +%s%N)
    ELAPSED=$(echo "scale=6; ($END - $START) / 1000000000" | bc)
    TIMES+=($ELAPSED)
    echo "${ELAPSED} s"
done

echo ""
echo "--- Timing Summary ---"
python3 - "${TIMES[@]}" <<'PYEOF'
import sys
times = [float(x) for x in sys.argv[1:]]
print(f"  Min  : {min(times):.6f} s")
print(f"  Max  : {max(times):.6f} s")
print(f"  Avg  : {sum(times)/len(times):.6f} s")
print(f"  Std  : {(sum((t-sum(times)/len(times))**2 for t in times)/len(times))**0.5:.6f} s")
PYEOF

echo ""
echo "--- 进阶 Profiling 指引 ---"
echo ""
echo "# gprof（函数级热点）:"
echo "  gcc -O2 -pg -o pagerank_serial_pg pagerank_serial.c -lm"
echo "  ./pagerank_serial_pg $GRAPH $MODE"
echo "  gprof pagerank_serial_pg gmon.out > gprof_report.txt"
echo ""
echo "# perf（Linux，硬件计数器）:"
echo "  perf stat -e cycles,instructions,cache-misses ./pagerank_serial $GRAPH $MODE"
echo "  perf record ./pagerank_serial $GRAPH $MODE && perf report"
echo ""
echo "# Valgrind cachegrind（缓存分析）:"
echo "  valgrind --tool=cachegrind ./pagerank_serial $GRAPH $MODE"
echo "  cg_annotate cachegrind.out.* > cachegrind_report.txt"
