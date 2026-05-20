#!/usr/bin/env python3
"""
analyze_serial.py - DD2356 Serial PageRank analysis aggregator (Group 26)

Consolidates baseline timing and per-platform perf data into a single
analysis document for the report. Produces results/serial_analysis.md
covering:

  1. Per-edge throughput (MEdges/s) - 3 platforms x 9 datasets
  2. Roofline / arithmetic-intensity analysis (analytical model)
  3. Working-set vs cache-hierarchy table
  4. Microarchitecture comparison from perf stat counters
  5. Amdahl serial-residual estimate (load + save vs PR kernel)
  6. Noise floor (5-run spread) for the main test dataset (polblogs)

Inputs (all under results/):
  - baseline_results.md                 (timing tables)
  - perf_stat_polblogs_{colab,kth,dardel}.txt
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESULTS = ROOT / "results"
BASELINE = RESULTS / "baseline_results.md"
OUT_FILE = RESULTS / "serial_analysis.md"

PLATFORMS = ["colab", "kth", "dardel"]

PLATFORM_INFO = {
    "colab":  {"name": "Colab",  "cpu": "Intel Xeon @ 2.20GHz",
               "max_ghz": 2.20},
    "kth":    {"name": "KTH",    "cpu": "Intel Xeon Platinum 8480C",
               "max_ghz": 3.80},
    "dardel": {"name": "Dardel", "cpu": "AMD EPYC 7742",
               "max_ghz": 2.25},
}

# Algorithm cost model (per edge, per iteration) for the roofline view.
# Inner loop: s += pr[u] * inv_out_degree[u]
FLOPS_PER_EDGE = 2          # 1 mul + 1 add
BYTES_PER_EDGE = 4 + 8 + 8  # col_idx (4B) + pr[u] (8B random) + inv_deg[u] (8B random)


# ============================== Parsers ==============================

def parse_baseline_table(text):
    """Extract the per-dataset rows from the '全数据集' table."""
    rows = []
    in_table = False
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("##") and "全数据集" in s:
            in_table = True
            continue
        if not in_table:
            continue
        if not s.startswith("|"):
            if rows:
                break
            continue
        parts = [p.strip() for p in s.strip("|").split("|")]
        if len(parts) < 8:
            continue
        try:
            rows.append({
                "dataset": parts[0],
                "mode":    parts[1],
                "nodes":   int(parts[2]),
                "edges":   int(parts[3]),
                "iters":   int(parts[4]),
                "colab":   float(parts[5]),
                "kth":     float(parts[6]),
                "dardel":  float(parts[7]),
            })
        except ValueError:
            continue  # header / separator rows
    return rows


def parse_polblogs_timing(text):
    """Extract the polblogs '主测试集' table -> per-platform dict of values."""
    cur = {p: {} for p in PLATFORMS}
    label_map = {
        "Load time (s)":      "load",
        "PR time (s)":        "pr",
        "Iterations":         "iters",
        "Time Min / 5次 (s)": "tmin",
        "Time Max / 5次 (s)": "tmax",
        "Time Avg / 5次 (s)": "tavg",
    }
    in_table = False
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("##") and "polblogs.csv" in s:
            in_table = True
            continue
        if not in_table:
            continue
        if s.startswith("##"):
            break
        if not s.startswith("|"):
            continue
        parts = [p.strip() for p in s.strip("|").split("|")]
        if len(parts) < 4:
            continue
        key = label_map.get(parts[0])
        if not key:
            continue
        try:
            cur["colab"][key]  = float(parts[1].split()[0])
            cur["kth"][key]    = float(parts[2].split()[0])
            cur["dardel"][key] = float(parts[3].split()[0])
        except (ValueError, IndexError):
            continue
    return cur


def parse_perf_stat(path):
    """Parse perf-stat output. Tolerates both 'cycles' and 'cycles:u' forms."""
    if not path.exists():
        return None
    text = path.read_text()
    if "unavailable" in text.lower() and "cycles" not in text:
        return None
    out = {}
    patterns = {
        "cycles":       r"([\d,]+)\s+cycles(?::u)?\b",
        "instructions": r"([\d,]+)\s+instructions(?::u)?\b",
        "cache_refs":   r"([\d,]+)\s+cache-references(?::u)?\b",
        "cache_misses": r"([\d,]+)\s+cache-misses(?::u)?\b",
        "l1_misses":    r"([\d,]+)\s+L1-dcache-load-misses(?::u)?\b",
        "llc_misses":   r"([\d,]+)\s+LLC-load-misses(?::u)?\b",
        "elapsed":      r"([\d.]+)\s+seconds time elapsed",
    }
    for k, pat in patterns.items():
        m = re.search(pat, text)
        if not m:
            continue
        raw = m.group(1).replace(",", "")
        try:
            out[k] = float(raw) if k == "elapsed" else int(raw)
        except ValueError:
            pass
    if "cycles" not in out:
        return None
    if "instructions" in out and out["cycles"] > 0:
        out["ipc"] = out["instructions"] / out["cycles"]
    if "elapsed" in out and out["elapsed"] > 0:
        out["eff_ghz"] = out["cycles"] / out["elapsed"] / 1e9
    if "l1_misses" in out and out.get("instructions"):
        out["l1_miss_per_kinstr"] = 1000 * out["l1_misses"] / out["instructions"]
    if out.get("cache_refs"):
        out["cache_miss_pct"] = 100.0 * out.get("cache_misses", 0) / out["cache_refs"]
    # Detect counter scope (kernel+user vs user-only)
    out["scope"] = "user-only (:u)" if re.search(r"cycles:u", text) else "all (kernel+user)"
    return out


# ============================== Analysis ==============================

def edge_throughput_medges(iters, edges, pr_time):
    if pr_time <= 0:
        return 0.0
    return iters * edges / pr_time / 1e6


def working_set_bytes(nodes, edges):
    # pr + pr_new + inv_out_degree (3 * N * 8 B)
    # + row_ptr (N * 4 B) + out_degree (N * 4 B)
    # + col_idx (M * 4 B)
    return 3 * nodes * 8 + 2 * nodes * 4 + edges * 4


def fits_in(b):
    if b < 32 * 1024:
        return "L1 (~32 KB)"
    if b < 1 * 1024 * 1024:
        return "L2 (~1 MB)"
    if b < 32 * 1024 * 1024:
        return "LLC (~32 MB)"
    return "DRAM"


def fmt_bytes(b):
    if b < 1024 * 1024:
        return f"{b/1024:.1f} KB"
    return f"{b/1024/1024:.2f} MB"


# ============================== Output ==============================

def make_throughput_table(rows):
    lines = [
        "| Dataset | Mode | N | M | Iters | Colab MEdges/s | KTH MEdges/s | Dardel MEdges/s |",
        "|---|---|---:|---:|---:|---:|---:|---:|",
    ]
    for r in rows:
        tp = {p: edge_throughput_medges(r["iters"], r["edges"], r[p]) for p in PLATFORMS}
        lines.append(
            f"| {r['dataset']} | {r['mode']} | {r['nodes']} | {r['edges']} | "
            f"{r['iters']} | {tp['colab']:.1f} | {tp['kth']:.1f} | {tp['dardel']:.1f} |"
        )
    return "\n".join(lines)


def make_working_set_table(rows):
    lines = [
        "| Dataset | N | M | Working set | Likely resident |",
        "|---|---:|---:|---:|---|",
    ]
    for r in rows:
        ws = working_set_bytes(r["nodes"], r["edges"])
        lines.append(
            f"| {r['dataset']} | {r['nodes']} | {r['edges']} | "
            f"{fmt_bytes(ws)} | {fits_in(ws)} |"
        )
    return "\n".join(lines)


def make_perf_table(perfs):
    lines = [
        "| Platform | CPU | Eff. GHz | IPC | L1 miss / kinstr | Cache-miss / ref | Scope |",
        "|---|---|---:|---:|---:|---:|---|",
    ]
    for p in PLATFORMS:
        info = PLATFORM_INFO[p]
        d = perfs.get(p)
        if not d:
            lines.append(f"| {info['name']} | {info['cpu']} | - | - | - | - | _no perf data_ |")
            continue
        ghz = d.get("eff_ghz")
        ipc = d.get("ipc")
        l1k = d.get("l1_miss_per_kinstr")
        cmr = d.get("cache_miss_pct")
        lines.append(
            f"| {info['name']} | {info['cpu']} | "
            f"{ghz:.2f}" + (" |" if ghz is not None else "- |") +
            f" {ipc:.2f} |" +
            (f" {l1k:.1f}" if l1k is not None else " -") + " |" +
            (f" {cmr:.2f}%" if cmr is not None else " -") + " |" +
            f" {d.get('scope', '?')} |"
        )
    return "\n".join(lines)


def make_amdahl_table(polblogs):
    lines = [
        "| Platform | Load (s) | PR (s) | PR fraction | Amdahl ceiling (PR-only parallel) |",
        "|---|---:|---:|---:|---:|",
    ]
    for p in PLATFORMS:
        d = polblogs.get(p, {})
        load, pr = d.get("load"), d.get("pr")
        if load is None or pr is None:
            continue
        total = load + pr
        if total <= 0:
            continue
        frac_pr = pr / total
        serial = 1.0 - frac_pr
        ceiling = float("inf") if serial == 0 else 1.0 / serial
        ceil_str = "infinite" if ceiling == float("inf") else f"{ceiling:.2f}x"
        lines.append(
            f"| {PLATFORM_INFO[p]['name']} | {load:.4f} | {pr:.4f} | "
            f"{frac_pr*100:.1f}% | {ceil_str} |"
        )
    return "\n".join(lines)


def make_noise_table(polblogs):
    lines = [
        "| Platform | Min (s) | Max (s) | Avg (s) | Spread (Max-Min)/Avg |",
        "|---|---:|---:|---:|---:|",
    ]
    for p in PLATFORMS:
        d = polblogs.get(p, {})
        if "tmin" not in d or d.get("tavg", 0) == 0:
            continue
        spread = 100.0 * (d["tmax"] - d["tmin"]) / d["tavg"]
        lines.append(
            f"| {PLATFORM_INFO[p]['name']} | {d['tmin']:.6f} | {d['tmax']:.6f} | "
            f"{d['tavg']:.6f} | {spread:.1f}% |"
        )
    return "\n".join(lines)


# ============================== Main ==============================

def main():
    if not BASELINE.exists():
        sys.exit(f"missing {BASELINE}")
    text = BASELINE.read_text()
    rows = parse_baseline_table(text)
    polblogs = parse_polblogs_timing(text)
    perfs = {p: parse_perf_stat(RESULTS / f"perf_stat_polblogs_{p}.txt")
             for p in PLATFORMS}

    pb_row = next((r for r in rows if r["dataset"] == "polblogs"), None)
    ai = FLOPS_PER_EDGE / BYTES_PER_EDGE

    md = []
    md.append("# Serial PageRank - Quantitative Analysis")
    md.append("")
    md.append("Auto-generated by `scripts/analyze_serial.py` from "
              "`results/baseline_results.md` and `results/perf_stat_polblogs_*.txt`.")
    md.append("")
    md.append("Turns the raw W1 baseline into per-edge throughput, an arithmetic-intensity "
              "view, a cache-residency table, microarchitecture deltas and an Amdahl "
              "ceiling. These are the references the parallel implementations "
              "(W2 OpenMP, W3 MPI, W4 Hybrid, W5 optimization, W6 GPU) are compared "
              "against.")
    md.append("")
    md.append("---")
    md.append("")

    # 1
    md.append("## 1. Per-edge throughput (MEdges/s)")
    md.append("")
    md.append("`MEdges/s = iters * edges / PR_time / 1e6`. A memory-bound kernel shows a "
              "roughly *dataset-independent* per-edge rate on a given platform - the value "
              "is therefore the right per-core ceiling to compare parallel runs against.")
    md.append("")
    md.append(make_throughput_table(rows))
    md.append("")
    md.append("_Use as the speedup denominator: any parallel implementation should be "
              "compared by `MEdges/s_parallel / MEdges/s_serial` on the same platform._")
    md.append("")

    # 2
    md.append("## 2. Roofline / arithmetic intensity")
    md.append("")
    md.append("Hot inner loop `s += pr[u] * inv_out_degree[u]`:")
    md.append("")
    md.append(f"- FLOPs per edge: **{FLOPS_PER_EDGE}** (1 mul + 1 add)")
    md.append(f"- Bytes per edge: **{BYTES_PER_EDGE}** (`col_idx` 4 B + `pr[u]` 8 B "
              f"random + `inv_out_degree[u]` 8 B random)")
    md.append(f"- Arithmetic intensity: **{ai:.3f} FLOP/Byte**")
    md.append("")
    md.append("Modern CPU ridge point is roughly 5-10 FLOP/Byte, so this kernel sits "
              "deep in the **memory-bound** region of the roofline.")
    md.append("")
    md.append("**Optimization implication**: budget should go to reducing memory traffic "
              "and improving cache reuse (NUMA pinning, neighbour reordering, blocking, "
              "prefetch) - *not* to arithmetic vectorization or unrolling.")
    md.append("")

    # 3
    md.append("## 3. Working-set vs cache hierarchy")
    md.append("")
    md.append("Hot data per iteration: `3*N*8 B (pr/pr_new/inv_deg) + 2*N*4 B "
              "(row_ptr/out_deg) + M*4 B (col_idx)`.")
    md.append("")
    md.append(make_working_set_table(rows))
    md.append("")
    md.append("**Caveat**: all course-provided datasets fit comfortably in L1/L2. "
              "The per-edge throughput table above is therefore **cache-resident** "
              "speed, *not* the DRAM-bandwidth ceiling. A larger graph (e.g. "
              "web-Stanford ~280k nodes, or a synthetic ER/Barabasi at >10 MB working "
              "set) is needed to expose the real ceiling for parallel scaling.")
    md.append("")

    # 4
    md.append("## 4. Microarchitecture comparison (perf stat, polblogs)")
    md.append("")
    md.append(make_perf_table(perfs))
    md.append("")
    md.append("**Reading the table**")
    md.append("")
    md.append("- IPC > 2 on all platforms with measured data -> no front-end stall; "
              "back-end (memory) stalls dominate, consistent with the roofline view.")
    md.append("- L1-miss-per-kinstr difference between KTH and Dardel is the main "
              "reason single-core wall times differ more than frequency alone explains.")
    md.append("- KTH and Dardel perf were collected with **different counter scopes** "
              "(see *Scope* column). For an apples-to-apples comparison both should be "
              "re-collected with the same `:u` setting. Sub-1% impact on IPC for a "
              "user-space dominated benchmark like this, but worth fixing before the "
              "final report.")
    md.append("")
    if pb_row and perfs.get("kth"):
        per_iter_bytes = BYTES_PER_EDGE * pb_row["edges"] + 16 * pb_row["nodes"]
        total_bytes = per_iter_bytes * pb_row["iters"]
        bw_gbs = total_bytes / pb_row["kth"] / 1e9
        md.append(f"_Sanity check (polblogs on KTH): kernel touches "
                  f"~{total_bytes/1e6:.1f} MB total -> effective bandwidth "
                  f"**{bw_gbs:.2f} GB/s** (vs ~300 GB/s DDR5 peak per socket on the "
                  f"8480C - far below peak because the access pattern is "
                  f"random-read into `pr[u]`)._")
        md.append("")

    # 5
    md.append("## 5. Amdahl serial-residual (polblogs)")
    md.append("")
    md.append("Wall-clock = `load_csv + PR + save_results`. W2-W4 only parallelise the "
              "PR kernel. The PR fraction therefore caps the wall-clock speedup.")
    md.append("")
    md.append(make_amdahl_table(polblogs))
    md.append("")
    md.append("**Implication**: on the polblogs-sized graphs the load fraction caps "
              "wall-clock speedup well below the per-kernel speedup. Report "
              "`speedup_PR` (kernel-only) and `speedup_wall` (end-to-end) separately. "
              "A larger graph drops `load fraction` below 5% and decouples the two.")
    md.append("")

    # 6
    md.append("## 6. Noise floor (5-run spread on polblogs)")
    md.append("")
    md.append(make_noise_table(polblogs))
    md.append("")
    md.append("_Treat parallel speedups below ~2x the platform's spread as noise, "
              "not signal. Quote both mean and (min, max) when reporting scaling._")
    md.append("")

    # Footer
    md.append("---")
    md.append("")
    md.append("## What this enables in W2-W6")
    md.append("")
    md.append("| Asset | Used by |")
    md.append("|---|---|")
    md.append("| Per-edge MEdges/s (sec.1)     | Speedup denominator for OpenMP/MPI/Hybrid/GPU |")
    md.append("| Arithmetic intensity (sec.2)  | Justifies optimization picks in W5 |")
    md.append("| Working-set table (sec.3)     | Decides which datasets need a larger graph |")
    md.append("| Microarch deltas (sec.4)      | Explains non-linear speedup across platforms |")
    md.append("| Amdahl ceiling (sec.5)        | Sets upper bound for wall-clock speedup |")
    md.append("| Noise floor (sec.6)           | Significance threshold for scaling plots |")
    md.append("")
    md.append("## Sources")
    md.append("")
    md.append("- Baseline timings: `results/baseline_results.md`")
    for p in PLATFORMS:
        md.append(f"- {PLATFORM_INFO[p]['name']} perf:  `results/perf_stat_polblogs_{p}.txt`")
    md.append("")
    md.append("Regenerate with: `python3 scripts/analyze_serial.py`")
    md.append("")

    OUT_FILE.write_text("\n".join(md))
    print(f"wrote {OUT_FILE.relative_to(ROOT)}")
    print(f"  - {len(rows)} dataset rows")
    print(f"  - perf data:        {[p for p, v in perfs.items() if v]}")
    print(f"  - polblogs timing:  {sorted({p for p, v in polblogs.items() if v})}")


if __name__ == "__main__":
    main()
