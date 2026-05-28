# Verification matrix

The OpenMP target GPU results below are now supported by a formal
confirmed-device run on the DD2356 Small GPU server (NVIDIA H100
`MIG 1g.10gb`). All GPU rows in `results/gpu_correctness_cluster_gpu.csv`
record `executed_on_device=YES`.

| Dataset | Mode | OpenMP vs serial | GPU vs serial |
|---|---|---|---|
| polblogs.csv | directed | PASS | PASS |
| karateDir.csv | directed | PASS | PASS |
| lesmisDir.csv | directed | PASS | PASS |
| dolphinsDir.csv | directed | PASS | PASS |
| NCAA_football.csv | directed | PASS | PASS |
| dolphins.csv | undirected | PASS | PASS |
| karate.csv | undirected | PASS | PASS |
| lesmis.csv | undirected | PASS | PASS |
| stateborders.csv | undirected | PASS | PASS |
