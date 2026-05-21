# Large-graph scaling results

- Graph: `/home/jovyan/DD2356-PageRank/data/synthetic_large_directed.csv`
- Mode: `directed`
- Generator config if this script created the graph: nodes=100000, edges=2000000
- Purpose: performance/scalability, not correctness smoke testing

| Variant | Config | PR time (s) | Iterations |
|---|---|---:|---:|
| serial | 1 thread | 0.040141 | 16 |
