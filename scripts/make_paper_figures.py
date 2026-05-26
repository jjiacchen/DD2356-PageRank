#!/usr/bin/env python3
"""Generate auxiliary report figures from the formal result CSV files."""

import csv
from pathlib import Path

import matplotlib.pyplot as plt


def find_repo_root() -> Path:
    for parent in Path(__file__).resolve().parents:
        if (parent / "results").is_dir() and (parent / "scripts").is_dir():
            return parent
    raise RuntimeError("cannot locate repository root")


ROOT = find_repo_root()
RESULTS = ROOT / "results"
OUT = RESULTS / "figures" / "paper"
OUT.mkdir(parents=True, exist_ok=True)

plt.rcParams.update(
    {
        "font.size": 11,
        "axes.labelsize": 12,
        "legend.fontsize": 10,
        "axes.spines.top": False,
        "axes.spines.right": False,
    }
)


def read_rows(relative_path: str, *, dataset: str | None = None) -> list[dict[str, str]]:
    path = RESULTS / relative_path
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    if dataset is not None:
        rows = [row for row in rows if row["dataset"] == dataset]
    if not rows:
        raise ValueError(f"no rows read from {path}")
    failed = [row for row in rows if "status" in row and row["status"] != "PASS"]
    if failed:
        raise ValueError(f"non-PASS rows in {path}: {failed}")
    return rows


def rank_series(rows: list[dict[str, str]], field: str) -> tuple[list[int], list[float]]:
    ordered = sorted(rows, key=lambda row: int(row["ranks"]))
    return [int(row["ranks"]) for row in ordered], [float(row[field]) for row in ordered]


def categorical_axis(ax: plt.Axes, values: list[int], label: str) -> list[int]:
    positions = list(range(len(values)))
    ax.set_xticks(positions, [str(value) for value in values])
    ax.set_xlabel(label)
    return positions


dardel_strong = read_rows("mpi_scaling_dardel_multinode_synthetic_100k_1m_directed.csv")
cluster_strong = read_rows("mpi_scaling_cluster_synthetic_100k_1m_directed.csv")
dardel_weak = read_rows("mpi_weak_scaling_dardel_multinode_directed.csv")
cluster_weak = read_rows("mpi_weak_scaling_cluster_directed.csv")


# Cross-platform MPI strong-scaling speedup.
ranks, dardel_speedup = rank_series(dardel_strong, "speedup")
_, cluster_speedup = rank_series(cluster_strong, "speedup")
fig, ax = plt.subplots(figsize=(5.0, 3.4))
x = categorical_axis(ax, ranks, "MPI ranks $P$")
ax.plot(x, ranks, "--", color="gray", lw=1, label="ideal", alpha=0.6)
ax.plot(x, dardel_speedup, "o-", color="#1f77b4", lw=2, label="Dardel two-node")
ax.plot(x, cluster_speedup, "s-", color="#d62728", lw=2, label="KTH cluster")
ax.set_ylabel("Speedup vs. $P{=}1$")
ax.set_title("MPI strong scaling on synthetic_100k_1m")
ax.legend(loc="upper left")
ax.grid(True, axis="y", alpha=0.3)
fig.tight_layout()
fig.savefig(OUT / "fig_mpi_speedup.png", dpi=300)
plt.close(fig)


# Cross-platform MPI communication fraction.
_, dardel_comm = rank_series(dardel_strong, "comm_fraction_avg")
_, cluster_comm = rank_series(cluster_strong, "comm_fraction_avg")
fig, ax = plt.subplots(figsize=(5.0, 3.4))
x = categorical_axis(ax, ranks, "MPI ranks $P$")
ax.plot(x, [value * 100 for value in dardel_comm], "o-", color="#1f77b4", lw=2, label="Dardel two-node")
ax.plot(x, [value * 100 for value in cluster_comm], "s-", color="#d62728", lw=2, label="KTH cluster")
ax.set_ylabel("Communication fraction (%)")
ax.set_title("Per-iteration communication overhead")
ax.legend(loc="upper left")
ax.grid(True, axis="y", alpha=0.3)
ax.set_ylim(0, 100)
fig.tight_layout()
fig.savefig(OUT / "fig_mpi_comm.png", dpi=300)
plt.close(fig)


# Exact Dardel weak-scaling communication/local split at P=16.
weak_16 = next(row for row in dardel_weak if int(row["ranks"]) == 16)
pr_time = float(weak_16["pr_time_avg_s"])
comm_time = float(weak_16["comm_time_avg_s"])
local_time = pr_time - comm_time
comm_pct = 100 * comm_time / pr_time
local_pct = 100 * local_time / pr_time
fig, ax = plt.subplots(figsize=(4.3, 3.4))
ax.pie(
    [comm_time, local_time],
    labels=[f"Measured communication\n({comm_pct:.1f}%)", f"Local/update remainder\n({local_pct:.1f}%)"],
    colors=["#d62728", "#2ca02c"],
    startangle=90,
    wedgeprops={"edgecolor": "white", "linewidth": 1.5},
)
ax.set_title(f"Dardel two-node weak $P{{=}}16$\nPR-time split ({pr_time:.4f} s total)")
fig.tight_layout()
fig.savefig(OUT / "fig_breakdown_pie.png", dpi=300)
plt.close(fig)


# OpenMP plots are CSV-backed on the two measured multi-core systems.
omp_paths = [("openmp_scaling_kth.csv", "KTH", "#d62728", "s-"), ("openmp_scaling_dardel.csv", "Dardel", "#1f77b4", "o-")]
fig, ax = plt.subplots(figsize=(5.0, 3.4))
threads: list[int] | None = None
for path, label, color, marker in omp_paths:
    rows = read_rows(path, dataset="synthetic_100k_1m")
    ordered = sorted(rows, key=lambda row: int(row["threads"]))
    platform_threads = [int(row["threads"]) for row in ordered]
    platform_speedup = [float(row["speedup_vs_T1"]) for row in ordered]
    if threads is None:
        threads = platform_threads
    x = list(range(len(platform_threads)))
    ax.plot(x, platform_speedup, marker, color=color, lw=2, label=label)
assert threads is not None
categorical_axis(ax, threads, "OpenMP threads $T$")
ax.set_ylabel("Speedup vs. $T{=}1$")
ax.set_title("OpenMP strong scaling on synthetic_100k_1m")
ax.legend(loc="upper left")
ax.grid(True, axis="y", alpha=0.3)
fig.tight_layout()
fig.savefig(OUT / "fig_omp_speedup.png", dpi=300)
plt.close(fig)


# Cross-platform MPI weak-scaling efficiency.
weak_ranks, dardel_eff = rank_series(dardel_weak, "weak_efficiency")
_, cluster_eff = rank_series(cluster_weak, "weak_efficiency")
fig, ax = plt.subplots(figsize=(5.0, 3.4))
x = categorical_axis(ax, weak_ranks, "MPI ranks $P$ (125k edges per rank)")
ax.plot(x, dardel_eff, "o-", color="#1f77b4", lw=2, label="Dardel two-node")
ax.plot(x, cluster_eff, "s-", color="#d62728", lw=2, label="KTH cluster")
ax.axhline(1.0, ls="--", color="gray", alpha=0.5, label="ideal")
ax.set_ylabel("Weak-scaling efficiency")
ax.set_title("MPI weak scaling")
ax.legend(loc="upper right")
ax.grid(True, axis="y", alpha=0.3)
fig.tight_layout()
fig.savefig(OUT / "fig_mpi_weak.png", dpi=300)
plt.close(fig)

print(f"Wrote five CSV-backed figures to {OUT}")
