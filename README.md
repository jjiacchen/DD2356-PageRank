# DD2356 Final Project – High-Performance PageRank
**Group 26**: Jiachen Shi, Minyi Zhu, Pengyu Wang

## Structure
- `serial/`  – Serial C baseline + profiling scripts 
- `verify/`  – Correctness verification framework 
- `data/`    – Course-provided graph datasets

## Build & Run
```bash
gcc -O2 -o serial/pagerank_serial serial/pagerank_serial.c -lm
./serial/pagerank_serial data/polblogs.csv directed
./serial/pagerank_serial data/dolphins.csv undirected
```

## Correctness Verification
```bash
gcc -O2 -o verify/verify verify/verify_correctness.c -lm
./verify/verify pagerank_serial_output.txt pagerank_parallel_output.txt
```
