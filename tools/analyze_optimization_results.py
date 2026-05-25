#!/usr/bin/env python3
"""Validate formal optimization evidence and write concise tables and SVG figures."""

from __future__ import annotations

import argparse
import csv
import html
from pathlib import Path
from typing import Dict, Iterable, List, Sequence, Tuple


VARIANTS = ["no_inv_static", "inv_static", "no_inv_dynamic", "inv_dynamic"]
FORMAL_CONFIGS = ["1x1", "1x2", "1x4", "1x8", "1x16", "2x8", "4x4", "8x2", "16x1"]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Analyze Hybrid optimization ablation CSVs.")
    parser.add_argument("regular_csv", type=Path)
    parser.add_argument("skewed_csv", type=Path)
    parser.add_argument("--out", type=Path, default=Path("results/optimization_evidence_cluster.md"))
    parser.add_argument(
        "--figure-dir",
        type=Path,
        default=Path("results/figures/cluster_optimization"),
    )
    parser.add_argument("--expected-runs", type=int, default=10)
    parser.add_argument(
        "--allow-partial",
        action="store_true",
        help="Validate a reduced smoke-test configuration set instead of formal coverage.",
    )
    return parser.parse_args()


def combo(row: Dict[str, str]) -> str:
    return f"{row['ranks']}x{row['threads']}"


def load_summary(path: Path) -> List[Dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def validate_summary(
    path: Path,
    rows: List[Dict[str, str]],
    expected_runs: int,
    allow_partial: bool,
) -> Dict[Tuple[str, str], Dict[str, str]]:
    required_fields = {
        "variant",
        "ranks",
        "threads",
        "runs",
        "pr_time_avg_s",
        "update_time_avg_s",
        "thread_imbalance",
        "parallel_efficiency_vs_variant_1x1",
        "efficiency_delta_vs_no_inv_static",
        "status",
    }
    if not rows or not required_fields.issubset(rows[0]):
        missing = sorted(required_fields.difference(rows[0] if rows else {}))
        raise SystemExit(f"{path}: missing required summary fields: {', '.join(missing)}")

    configs = sorted({combo(row) for row in rows})
    expected_configs = configs if allow_partial else FORMAL_CONFIGS
    expected_pairs = {(variant, setting) for variant in VARIANTS for setting in expected_configs}
    indexed = {(row["variant"], combo(row)): row for row in rows}
    missing_pairs = sorted(expected_pairs.difference(indexed))
    unexpected = sorted(set(indexed).difference(expected_pairs)) if not allow_partial else []
    if missing_pairs:
        raise SystemExit(f"{path}: missing variant/config rows: {missing_pairs}")
    if unexpected:
        raise SystemExit(f"{path}: unexpected variant/config rows: {unexpected}")
    if len(rows) != len(expected_pairs):
        raise SystemExit(f"{path}: expected {len(expected_pairs)} summary rows, found {len(rows)}")

    for pair, row in indexed.items():
        if row["status"] != "PASS":
            raise SystemExit(f"{path}: non-PASS status for {pair}")
        if int(row["runs"]) != expected_runs:
            raise SystemExit(f"{path}: {pair} has {row['runs']} runs, expected {expected_runs}")
        if int(row["thread_workers"]) != int(row["ranks"]) * int(row["threads"]):
            raise SystemExit(
                f"{path}: {pair} used {row['thread_workers']} diagnostic workers, "
                f"expected {int(row['ranks']) * int(row['threads'])}"
            )
        for field in (
            "update_time_avg_s",
            "thread_imbalance",
            "speedup_vs_variant_1x1",
            "parallel_efficiency_vs_variant_1x1",
            "efficiency_delta_vs_no_inv_static",
        ):
            if not row[field]:
                raise SystemExit(f"{path}: {pair} has empty {field}")

    raw_path = path.with_name(f"{path.stem}_raw.csv")
    if not raw_path.exists():
        raise SystemExit(f"{path}: missing raw repeat CSV {raw_path}")
    with raw_path.open(newline="", encoding="utf-8") as handle:
        raw_rows = list(csv.DictReader(handle))
    expected_raw = len(expected_pairs) * expected_runs
    if len(raw_rows) != expected_raw:
        raise SystemExit(f"{raw_path}: expected {expected_raw} raw rows, found {len(raw_rows)}")
    if any(row["status"] != "PASS" for row in raw_rows):
        raise SystemExit(f"{raw_path}: contains failed correctness rows")
    for row in raw_rows:
        expected_workers = int(row["ranks"]) * int(row["threads"])
        if int(row["thread_workers"]) != expected_workers:
            raise SystemExit(
                f"{raw_path}: {row['variant']} {combo(row)} repeat {row['repeat']} "
                f"used {row['thread_workers']} diagnostic workers, expected {expected_workers}"
            )
    return indexed


def numeric(row: Dict[str, str], field: str) -> float:
    return float(row[field])


def md_table(headers: Sequence[str], rows: Iterable[Sequence[str]]) -> str:
    lines = [
        "| " + " | ".join(headers) + " |",
        "| " + " | ".join("---" for _ in headers) + " |",
    ]
    lines.extend("| " + " | ".join(row) + " |" for row in rows)
    return "\n".join(lines)


def write_grouped_bar_svg(
    path: Path,
    title: str,
    ylabel: str,
    labels: Sequence[str],
    before: Sequence[float],
    after: Sequence[float],
    before_name: str,
    after_name: str,
) -> None:
    width, height = 900, 510
    left, top, bottom = 82, 60, 92
    plot_w, plot_h = width - left - 30, height - top - bottom
    peak = max([*before, *after, 1e-12]) * 1.15
    group_w = plot_w / max(len(labels), 1)
    bar_w = min(42.0, group_w * 0.32)
    elements = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="white"/>',
        f'<text x="{left}" y="30" font-family="Arial, sans-serif" font-size="20" font-weight="bold">{html.escape(title)}</text>',
        f'<text x="18" y="{top + plot_h / 2}" transform="rotate(-90 18 {top + plot_h / 2})" font-family="Arial, sans-serif" font-size="14">{html.escape(ylabel)}</text>',
    ]
    for step in range(5):
        value = peak * step / 4
        y = top + plot_h - (value / peak * plot_h)
        elements.append(f'<line x1="{left}" y1="{y:.1f}" x2="{left + plot_w}" y2="{y:.1f}" stroke="#e5e7eb"/>')
        elements.append(f'<text x="{left - 8}" y="{y + 5:.1f}" text-anchor="end" font-family="Arial, sans-serif" font-size="12" fill="#374151">{value:.3f}</text>')
    elements.append(f'<line x1="{left}" y1="{top + plot_h}" x2="{left + plot_w}" y2="{top + plot_h}" stroke="#111827"/>')
    for index, label in enumerate(labels):
        center = left + group_w * (index + 0.5)
        for value, color, x in (
            (before[index], "#607D8B", center - bar_w - 3),
            (after[index], "#E67E22", center + 3),
        ):
            bar_h = value / peak * plot_h
            y = top + plot_h - bar_h
            elements.append(f'<rect x="{x:.1f}" y="{y:.1f}" width="{bar_w:.1f}" height="{bar_h:.1f}" fill="{color}"/>')
            elements.append(f'<text x="{x + bar_w / 2:.1f}" y="{max(top + 13, y - 6):.1f}" text-anchor="middle" font-family="Arial, sans-serif" font-size="11">{value:.3f}</text>')
        elements.append(f'<text x="{center:.1f}" y="{top + plot_h + 25}" text-anchor="middle" font-family="Arial, sans-serif" font-size="13">{html.escape(label)}</text>')
    legend_y = height - 32
    elements.extend([
        f'<rect x="{left}" y="{legend_y - 13}" width="16" height="16" fill="#607D8B"/>',
        f'<text x="{left + 23}" y="{legend_y}" font-family="Arial, sans-serif" font-size="13">{html.escape(before_name)}</text>',
        f'<rect x="{left + 220}" y="{legend_y - 13}" width="16" height="16" fill="#E67E22"/>',
        f'<text x="{left + 243}" y="{legend_y}" font-family="Arial, sans-serif" font-size="13">{html.escape(after_name)}</text>',
        "</svg>",
    ])
    path.write_text("\n".join(elements), encoding="utf-8")


def write_grouped_bar_png(
    path: Path,
    title: str,
    ylabel: str,
    labels: Sequence[str],
    before: Sequence[float],
    after: Sequence[float],
    before_name: str,
    after_name: str,
) -> bool:
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:
        return False

    def font(size: int):
        try:
            return ImageFont.truetype("Arial.ttf", size)
        except OSError:
            return ImageFont.load_default()

    width, height = 1400, 820
    left, top, right, bottom = 130, 120, 1340, 670
    plot_w, plot_h = right - left, bottom - top
    peak = max([*before, *after, 1e-12]) * 1.18
    image = Image.new("RGB", (width, height), "white")
    draw = ImageDraw.Draw(image)
    text = (15, 23, 42)
    muted = (100, 116, 139)
    grid = (226, 232, 240)
    before_color = (96, 125, 139)
    after_color = (230, 126, 34)
    draw.text((65, 35), title, fill=text, font=font(28))
    draw.text((28, 90), ylabel, fill=muted, font=font(17))
    for step in range(6):
        value = peak * step / 5
        y = bottom - plot_h * step / 5
        draw.line((left, y, right, y), fill=grid, width=1)
        draw.text((28, y - 10), f"{value:.3f}", fill=muted, font=font(14))
    draw.line((left, bottom, right, bottom), fill=text, width=2)
    group_w = plot_w / max(len(labels), 1)
    bar_w = min(70, int(group_w * 0.32))
    for index, label in enumerate(labels):
        center = left + group_w * (index + 0.5)
        for value, color, x in (
            (before[index], before_color, center - bar_w - 5),
            (after[index], after_color, center + 5),
        ):
            bar_h = plot_h * value / peak
            y = bottom - bar_h
            draw.rectangle((x, y, x + bar_w, bottom), fill=color)
            draw.text((x, max(top + 5, y - 25)), f"{value:.3f}", fill=text, font=font(13))
        draw.text((center - 22, bottom + 20), label, fill=text, font=font(16))
    legend_y = 758
    draw.rectangle((left, legend_y - 16, left + 20, legend_y + 4), fill=before_color)
    draw.text((left + 30, legend_y - 16), before_name, fill=text, font=font(16))
    draw.rectangle((left + 300, legend_y - 16, left + 320, legend_y + 4), fill=after_color)
    draw.text((left + 330, legend_y - 16), after_name, fill=text, font=font(16))
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)
    return True


def main() -> None:
    args = parse_args()
    regular_rows = load_summary(args.regular_csv)
    skewed_rows = load_summary(args.skewed_csv)
    regular = validate_summary(args.regular_csv, regular_rows, args.expected_runs, args.allow_partial)
    skewed = validate_summary(args.skewed_csv, skewed_rows, args.expected_runs, args.allow_partial)
    available = sorted({combo(row) for row in regular_rows}, key=lambda setting: (int(setting.split("x")[0]) * int(setting.split("x")[1]), setting))
    primary_configs = [setting for setting in ("1x1", "1x4", "1x8", "1x16", "4x4") if setting in available]
    efficiency_configs = [setting for setting in ("1x2", "1x4", "1x8", "1x16") if setting in available]
    imbalance_configs = [setting for setting in ("1x4", "1x8", "1x16") if setting in available]

    if "1x16" in {combo(row) for row in skewed_rows}:
        inv_static_imb = numeric(skewed[("inv_static", "1x16")], "thread_imbalance")
        inv_dynamic_imb = numeric(skewed[("inv_dynamic", "1x16")], "thread_imbalance")
        if inv_dynamic_imb >= inv_static_imb:
            raise SystemExit(
                "skewed 1x16 evidence does not show reduced thread imbalance for dynamic scheduling: "
                f"{inv_dynamic_imb:.6f} >= {inv_static_imb:.6f}"
            )

    args.figure_dir.mkdir(parents=True, exist_ok=True)
    if primary_configs:
        write_grouped_bar_svg(
            args.figure_dir / "optimization_pr_time.svg",
            "Regular Synthetic Graph: PageRank Time",
            "PR time (s)",
            primary_configs,
            [numeric(regular[("no_inv_static", setting)], "pr_time_avg_s") for setting in primary_configs],
            [numeric(regular[("inv_dynamic", setting)], "pr_time_avg_s") for setting in primary_configs],
            "no_inv_static",
            "inv_dynamic",
        )
        write_grouped_bar_png(
            args.figure_dir / "optimization_pr_time.png",
            "Regular Synthetic Graph: PageRank Time",
            "PR time (s)",
            primary_configs,
            [numeric(regular[("no_inv_static", setting)], "pr_time_avg_s") for setting in primary_configs],
            [numeric(regular[("inv_dynamic", setting)], "pr_time_avg_s") for setting in primary_configs],
            "no_inv_static",
            "inv_dynamic",
        )
    if efficiency_configs:
        write_grouped_bar_svg(
            args.figure_dir / "optimization_efficiency.svg",
            "Regular Synthetic Graph: Parallel Efficiency",
            "Efficiency",
            efficiency_configs,
            [numeric(regular[("no_inv_static", setting)], "parallel_efficiency_vs_variant_1x1") for setting in efficiency_configs],
            [numeric(regular[("inv_dynamic", setting)], "parallel_efficiency_vs_variant_1x1") for setting in efficiency_configs],
            "no_inv_static",
            "inv_dynamic",
        )
        write_grouped_bar_png(
            args.figure_dir / "optimization_efficiency.png",
            "Regular Synthetic Graph: Parallel Efficiency",
            "Efficiency",
            efficiency_configs,
            [numeric(regular[("no_inv_static", setting)], "parallel_efficiency_vs_variant_1x1") for setting in efficiency_configs],
            [numeric(regular[("inv_dynamic", setting)], "parallel_efficiency_vs_variant_1x1") for setting in efficiency_configs],
            "no_inv_static",
            "inv_dynamic",
        )
    if imbalance_configs:
        write_grouped_bar_svg(
            args.figure_dir / "optimization_thread_imbalance.svg",
            "Skewed Stress Graph: Thread In-edge Imbalance",
            "max / average work",
            imbalance_configs,
            [numeric(skewed[("inv_static", setting)], "thread_imbalance") for setting in imbalance_configs],
            [numeric(skewed[("inv_dynamic", setting)], "thread_imbalance") for setting in imbalance_configs],
            "inv_static",
            "inv_dynamic",
        )
        write_grouped_bar_png(
            args.figure_dir / "optimization_thread_imbalance.png",
            "Skewed Stress Graph: Thread In-edge Imbalance",
            "max / average work",
            imbalance_configs,
            [numeric(skewed[("inv_static", setting)], "thread_imbalance") for setting in imbalance_configs],
            [numeric(skewed[("inv_dynamic", setting)], "thread_imbalance") for setting in imbalance_configs],
            "inv_static",
            "inv_dynamic",
        )

    regular_table = []
    for setting in primary_configs:
        before = regular[("no_inv_static", setting)]
        after = regular[("inv_dynamic", setting)]
        regular_table.append([
            setting,
            f"{numeric(before, 'pr_time_avg_s'):.6f}",
            f"{numeric(after, 'pr_time_avg_s'):.6f}",
            f"{numeric(after, 'speedup_vs_no_inv_static'):.3f}x",
            f"{numeric(before, 'update_time_avg_s'):.6f}",
            f"{numeric(after, 'update_time_avg_s'):.6f}",
            f"{numeric(before, 'parallel_efficiency_vs_variant_1x1'):.4f}",
            f"{numeric(after, 'parallel_efficiency_vs_variant_1x1'):.4f}",
            f"{numeric(after, 'efficiency_delta_vs_no_inv_static'):+.4f}",
        ])
    skew_table = []
    for setting in imbalance_configs:
        static = skewed[("inv_static", setting)]
        dynamic = skewed[("inv_dynamic", setting)]
        skew_table.append([
            setting,
            f"{numeric(static, 'thread_imbalance'):.4f}",
            f"{numeric(dynamic, 'thread_imbalance'):.4f}",
            f"{numeric(static, 'thread_imbalance') / numeric(dynamic, 'thread_imbalance'):.3f}x",
            f"{numeric(static, 'update_time_avg_s'):.6f}",
            f"{numeric(dynamic, 'update_time_avg_s'):.6f}",
        ])

    lines = [
        "# Formal Optimization Evidence - DD2356 Medium CPU",
        "",
        "## Validation",
        "",
        f"- Regular graph summary: `{args.regular_csv}` ({len(regular_rows)} rows, all PASS).",
        f"- Skewed stress graph summary: `{args.skewed_csv}` ({len(skewed_rows)} rows, all PASS).",
        f"- Each summary row contains `{args.expected_runs}` correctness-checked timed repetitions.",
        "- Parallel efficiency is computed per variant against its own `1x1` PageRank runtime.",
        "",
        "## Regular Synthetic Graph",
        "",
        md_table(
            ["Config", "PR before (s)", "PR full opt. (s)", "PR speedup", "Update before (s)", "Update full opt. (s)", "Eff. before", "Eff. full opt.", "Eff. delta"],
            regular_table,
        ),
        "",
        "## Skewed Thread-Load Stress Graph",
        "",
        md_table(
            ["Config", "Static imbalance", "Dynamic imbalance", "Balance improvement", "Static update (s)", "Dynamic update (s)"],
            skew_table,
        ),
        "",
    ]
    if "1x16" in {combo(row) for row in skewed_rows}:
        static = skewed[("inv_static", "1x16")]
        dynamic = skewed[("inv_dynamic", "1x16")]
        static_update = numeric(static, "update_time_avg_s")
        dynamic_update = numeric(dynamic, "update_time_avg_s")
        runtime_text = (
            "also reduces update-kernel time"
            if dynamic_update < static_update
            else "reduces measured imbalance, but its scheduling overhead does not reduce update-kernel time"
        )
        lines.extend([
            "## Interpretation",
            "",
            "On the controlled skewed input at `1x16`, dynamic scheduling lowers "
            f"thread in-edge imbalance from `{numeric(static, 'thread_imbalance'):.4f}` to "
            f"`{numeric(dynamic, 'thread_imbalance'):.4f}` and {runtime_text}. "
            "This distinction prevents a load-balance observation from being overstated as a runtime speedup.",
            "",
        ])
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text("\n".join(lines), encoding="utf-8")
    print(f"validated {args.regular_csv} and {args.skewed_csv}")
    print(f"wrote {args.out}")
    print(f"wrote figures to {args.figure_dir}")


if __name__ == "__main__":
    main()
