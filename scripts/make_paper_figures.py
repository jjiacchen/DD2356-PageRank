#!/usr/bin/env python3
"""
Generate publication-quality figures for the DD2356 PageRank report.
Outputs to results/figures/paper/ as PNG at 300 DPI.
Run: python3 scripts/make_paper_figures.py
"""
import os
import matplotlib.pyplot as plt
import numpy as np

OUT = "results/figures/paper"
os.makedirs(OUT, exist_ok=True)
plt.rcParams.update({
    "font.size": 11, "axes.labelsize": 12, "legend.fontsize": 10,
    "axes.spines.top": False, "axes.spines.right": False,
})

# ---------------- DATA ----------------
mpi_ranks = [1, 2, 4, 8, 16]
speedup_dardel  = [1.000, 0.0042, 0.0050, 0.0036, 0.0022]
speedup_cluster = [1.000, 1.543,  2.138,  1.705,  1.166]
comm_dardel     = [0.013, 0.996,  0.998,  0.999,  1.000]
comm_cluster    = [0.014, 0.177,  0.436,  0.751,  0.848]

weak_ranks = [1, 2, 4, 8, 16]
weak_eff_dardel  = [1.000, 0.0019, 0.0018, 0.0004, 0.0002]
weak_eff_cluster = [1.000, 0.619,  0.439,  0.286,  0.136]

omp_T = [1, 2, 4, 8, 16, 32, 64]
omp_colab  = [1.00, 0.84, 1.27, None, None, None, None]
omp_kth    = [1.00, 1.48, 2.46, 3.57, 2.79, 4.48, 1.83]
omp_dardel = [1.00, 1.79, 2.90, 3.75, 4.32, 3.80, 2.59]

# ---------------- FIG 1: Cross-platform MPI Speedup ----------------
fig, ax = plt.subplots(figsize=(5.0, 3.4))
ax.plot(mpi_ranks, mpi_ranks, "--", color="gray", lw=1, label="ideal", alpha=0.6)
ax.plot(mpi_ranks, speedup_dardel,  "o-", color="#1f77b4", lw=2, label="Dardel (Cray MPICH)")
ax.plot(mpi_ranks, speedup_cluster, "s-", color="#d62728", lw=2, label="KTH cluster (OpenMPI)")
ax.set_xscale("log", base=2); ax.set_yscale("log")
ax.set_xticks(mpi_ranks); ax.set_xticklabels(mpi_ranks)
ax.set_xlabel("MPI ranks P")
ax.set_ylabel("Speedup vs. P=1")
ax.set_title("MPI strong scaling on synthetic_100k_1m")
ax.legend(loc="lower right"); ax.grid(True, which="both", alpha=0.3)
plt.tight_layout(); plt.savefig(f"{OUT}/fig_mpi_speedup.png", dpi=300); plt.close()

# ---------------- FIG 2: Cross-platform MPI Comm Fraction ----------------
fig, ax = plt.subplots(figsize=(5.0, 3.4))
ax.plot(mpi_ranks, [c*100 for c in comm_dardel],  "o-", color="#1f77b4", lw=2, label="Dardel")
ax.plot(mpi_ranks, [c*100 for c in comm_cluster], "s-", color="#d62728", lw=2, label="KTH cluster")
ax.set_xscale("log", base=2)
ax.set_xticks(mpi_ranks); ax.set_xticklabels(mpi_ranks)
ax.set_xlabel("MPI ranks P")
ax.set_ylabel("Communication fraction (%)")
ax.set_title("Per-iteration communication overhead")
ax.axhline(99, ls=":", color="gray", alpha=0.5)
ax.legend(loc="center right"); ax.grid(True, alpha=0.3); ax.set_ylim(0, 105)
plt.tight_layout(); plt.savefig(f"{OUT}/fig_mpi_comm.png", dpi=300); plt.close()

# ---------------- FIG 3: Breakdown (horizontal bar, replaces unreadable pie) ---
fig, ax = plt.subplots(figsize=(5.5, 2.4))
labels = ["MPI_Allgatherv", "Allreduce (dangling+diff)", "Local compute"]
sizes  = [91.5, 4.0, 4.5]
colors = ["#d62728", "#ff7f0e", "#2ca02c"]
y_pos = np.arange(len(labels))
bars = ax.barh(y_pos, sizes, color=colors, edgecolor="white")
ax.set_yticks(y_pos); ax.set_yticklabels(labels, fontsize=11)
ax.invert_yaxis()
ax.set_xlim(0, 105); ax.set_xlabel("Share of PR time (%)")
ax.set_title("Dardel weak P=16: PR-time breakdown (23.8 s total)")
for i, v in enumerate(sizes):
    ax.text(v + 1.5, i, f"{v}%", va="center", fontsize=11, fontweight="bold")
ax.spines["left"].set_visible(False)
ax.tick_params(axis="y", length=0)
plt.tight_layout(); plt.savefig(f"{OUT}/fig_breakdown.png", dpi=300); plt.close()

# ---------------- FIG 4: OpenMP three-platform speedup ----------------
fig, ax = plt.subplots(figsize=(5.0, 3.4))
def trimmed(xs, ys):
    return [(x, y) for x, y in zip(xs, ys) if y is not None]
xc, yc = zip(*trimmed(omp_T, omp_colab))
ax.plot(xc, yc, "^--", color="#9467bd", lw=2, label="Colab (2 vCPU)")
ax.plot(omp_T, omp_kth,    "s-",  color="#d62728", lw=2, label="KTH (112 cores)")
ax.plot(omp_T, omp_dardel, "o-",  color="#1f77b4", lw=2, label="Dardel (128 cores)")
ax.set_xscale("log", base=2)
ax.set_xticks(omp_T); ax.set_xticklabels(omp_T)
ax.set_xlabel("OpenMP threads T")
ax.set_ylabel("Speedup vs. T=1")
ax.set_title("OpenMP strong scaling on synthetic_100k_1m")
ax.annotate("KTH peak\n4.48x", xy=(32, 4.48), xytext=(20, 5.2),
    arrowprops=dict(arrowstyle="->", color="#d62728", lw=0.8), color="#d62728", fontsize=9)
ax.annotate("Dardel peak\n4.32x", xy=(16, 4.32), xytext=(6, 4.8),
    arrowprops=dict(arrowstyle="->", color="#1f77b4", lw=0.8), color="#1f77b4", fontsize=9)
ax.annotate("NUMA dip", xy=(16, 2.79), xytext=(20, 2.0),
    arrowprops=dict(arrowstyle="->", color="#d62728", lw=0.8, alpha=0.6),
    color="#d62728", fontsize=8, alpha=0.8)
ax.legend(loc="lower left"); ax.grid(True, which="both", alpha=0.3); ax.set_ylim(0, 6)
plt.tight_layout(); plt.savefig(f"{OUT}/fig_omp_speedup.png", dpi=300); plt.close()

# ---------------- FIG 5: MPI Weak-Scaling Efficiency ----------------
fig, ax = plt.subplots(figsize=(5.0, 3.4))
ax.plot(weak_ranks, weak_eff_dardel,  "o-", color="#1f77b4", lw=2, label="Dardel")
ax.plot(weak_ranks, weak_eff_cluster, "s-", color="#d62728", lw=2, label="KTH cluster")
ax.axhline(1.0, ls="--", color="gray", alpha=0.5, label="ideal")
ax.set_xscale("log", base=2); ax.set_yscale("log")
ax.set_xticks(weak_ranks); ax.set_xticklabels(weak_ranks)
ax.set_xlabel("MPI ranks P (125k edges per rank)")
ax.set_ylabel("Weak-scaling efficiency")
ax.set_title("MPI weak scaling")
ax.legend(loc="lower left"); ax.grid(True, which="both", alpha=0.3)
plt.tight_layout(); plt.savefig(f"{OUT}/fig_mpi_weak.png", dpi=300); plt.close()

print(f"Wrote 5 figures to {OUT}/")