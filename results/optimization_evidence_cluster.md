# Formal Optimization Evidence - DD2356 Medium CPU

## Validation

- Regular graph summary: `results/optimization_ablation_cluster_optpe_synthetic_100k_1m_directed.csv` (36 rows, all PASS).
- Skewed stress graph summary: `results/optimization_ablation_cluster_optpe_skewed_100k_1m_directed.csv` (36 rows, all PASS).
- Each summary row contains `10` correctness-checked timed repetitions.
- Parallel efficiency is computed per variant against its own `1x1` PageRank runtime.

## Regular Synthetic Graph

| Config | PR before (s) | PR full opt. (s) | PR speedup | Update before (s) | Update full opt. (s) | Eff. before | Eff. full opt. | Eff. delta |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1x1 | 0.035842 | 0.032455 | 1.104x | 0.033078 | 0.029548 | 1.0000 | 1.0000 | +0.0000 |
| 1x4 | 0.012826 | 0.010960 | 1.170x | 0.010691 | 0.008779 | 0.6986 | 0.7403 | +0.0417 |
| 1x8 | 0.006531 | 0.006945 | 0.940x | 0.004768 | 0.004852 | 0.6860 | 0.5841 | -0.1019 |
| 1x16 | 0.005576 | 0.005765 | 0.967x | 0.003683 | 0.002765 | 0.4017 | 0.3518 | -0.0499 |
| 4x4 | 0.007609 | 0.007524 | 1.011x | 0.003938 | 0.003026 | 0.2944 | 0.2696 | -0.0248 |

## Skewed Thread-Load Stress Graph

| Config | Static imbalance | Dynamic imbalance | Balance improvement | Static update (s) | Dynamic update (s) |
| --- | --- | --- | --- | --- | --- |
| 1x4 | 3.1591 | 1.1489 | 2.750x | 0.028158 | 0.010108 |
| 1x8 | 6.0388 | 1.2420 | 4.862x | 0.020228 | 0.005293 |
| 1x16 | 11.7988 | 1.2415 | 9.504x | 0.017573 | 0.003117 |

## Interpretation

On the controlled skewed input at `1x16`, dynamic scheduling lowers thread in-edge imbalance from `11.7988` to `1.2415` and also reduces update-kernel time. This distinction prevents a load-balance observation from being overstated as a runtime speedup.
