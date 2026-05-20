#!/usr/bin/env python3
"""Create MPI PageRank result figures from profile_mpi summary CSV files.

This script uses Pillow instead of matplotlib so it works in the lightweight
runtime available on local machines and clusters.
"""

from __future__ import annotations

import argparse
import csv
from collections import defaultdict
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


COLORS = [
    (36, 99, 235),
    (16, 185, 129),
    (245, 158, 11),
    (239, 68, 68),
    (139, 92, 246),
    (20, 184, 166),
]
GRID = (226, 232, 240)
TEXT = (15, 23, 42)
MUTED = (100, 116, 139)
COMPUTE = (59, 130, 246)
COMM = (249, 115, 22)


def load_rows(paths: list[Path]) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for path in paths:
        with path.open(newline="", encoding="utf-8") as f:
            for row in csv.DictReader(f):
                row["_source"] = path.name
                rows.append(row)
    if not rows:
        raise SystemExit("no rows found in input CSV files")
    return rows


def font(size: int) -> ImageFont.ImageFont:
    try:
        return ImageFont.truetype("Arial.ttf", size)
    except OSError:
        return ImageFont.load_default()


def canvas(title: str) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    img = Image.new("RGB", (1400, 900), "white")
    draw = ImageDraw.Draw(img)
    draw.text((70, 35), title, fill=TEXT, font=font(30))
    return img, draw


def chart_area() -> tuple[int, int, int, int]:
    return 95, 120, 1310, 780


def label_for(row: dict[str, str]) -> str:
    dataset = row.get("dataset", "dataset")
    mode = row.get("mode", "")
    scaling = row.get("scaling_mode", "")
    return f"{dataset} {mode} {scaling}".strip()


def grouped(rows: list[dict[str, str]]) -> dict[str, list[dict[str, str]]]:
    out: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        out[label_for(row)].append(row)
    for vals in out.values():
        vals.sort(key=lambda r: int(r["ranks"]))
    return out


def draw_axes(draw: ImageDraw.ImageDraw, y_max: float, y_label: str) -> None:
    left, top, right, bottom = chart_area()
    draw.line((left, bottom, right, bottom), fill=TEXT, width=2)
    draw.line((left, top, left, bottom), fill=TEXT, width=2)
    for i in range(6):
        y = bottom - (bottom - top) * i / 5
        val = y_max * i / 5
        draw.line((left, y, right, y), fill=GRID, width=1)
        draw.text((25, y - 8), f"{val:.2f}", fill=MUTED, font=font(14))
    draw.text((25, top - 35), y_label, fill=MUTED, font=font(16))


def x_positions(ranks: list[int]) -> dict[int, float]:
    left, _top, right, _bottom = chart_area()
    if len(ranks) == 1:
        return {ranks[0]: (left + right) / 2}
    return {
        rank: left + (right - left) * i / (len(ranks) - 1)
        for i, rank in enumerate(ranks)
    }


def draw_legend(draw: ImageDraw.ImageDraw, labels: list[str], colors: list[tuple[int, int, int]]) -> None:
    x, y = 920, 45
    for label, color in zip(labels, colors):
        draw.rectangle((x, y + 4, x + 18, y + 18), fill=color)
        draw.text((x + 26, y), label[:38], fill=TEXT, font=font(15))
        y += 24


def line_chart(rows: list[dict[str, str]], field: str, title: str, ylabel: str, out: Path, ideal: bool = False) -> None:
    groups = grouped(rows)
    ranks = sorted({int(r["ranks"]) for r in rows})
    ymax = max(float(r[field]) for r in rows)
    if ideal:
        ymax = max(ymax, float(max(ranks)))
    ymax = ymax * 1.12 if ymax > 0 else 1.0

    img, draw = canvas(title)
    draw_axes(draw, ymax, ylabel)
    left, top, right, bottom = chart_area()
    xpos = x_positions(ranks)

    for rank in ranks:
        x = xpos[rank]
        draw.line((x, bottom, x, bottom + 8), fill=TEXT, width=2)
        draw.text((x - 10, bottom + 18), str(rank), fill=TEXT, font=font(15))
    draw.text(((left + right) / 2 - 35, bottom + 55), "MPI ranks", fill=MUTED, font=font(16))

    legend_labels: list[str] = []
    legend_colors: list[tuple[int, int, int]] = []
    for idx, (label, vals) in enumerate(groups.items()):
        color = COLORS[idx % len(COLORS)]
        points = []
        for row in vals:
            x = xpos[int(row["ranks"])]
            y = bottom - (bottom - top) * float(row[field]) / ymax
            points.append((x, y))
        if len(points) > 1:
            draw.line(points, fill=color, width=4)
        for x, y in points:
            draw.ellipse((x - 5, y - 5, x + 5, y + 5), fill=color)
        legend_labels.append(label)
        legend_colors.append(color)

    if ideal:
        ideal_points = [(xpos[r], bottom - (bottom - top) * r / ymax) for r in ranks]
        if len(ideal_points) > 1:
            draw.line(ideal_points, fill=MUTED, width=2)
        legend_labels.append("ideal")
        legend_colors.append(MUTED)

    draw_legend(draw, legend_labels, legend_colors)
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)


def stacked_runtime_chart(rows: list[dict[str, str]], out: Path) -> None:
    rows = sorted(rows, key=lambda r: (label_for(r), int(r["ranks"])))
    labels = [f"{r['dataset']}\nnp={r['ranks']}" for r in rows]
    compute_vals = [max(float(r["pr_time_avg_s"]) - float(r["comm_time_avg_s"]), 0.0) for r in rows]
    comm_vals = [float(r["comm_time_avg_s"]) for r in rows]
    totals = [c + m for c, m in zip(compute_vals, comm_vals)]
    ymax = max(totals) * 1.15 if totals else 1.0

    img, draw = canvas("MPI Runtime Breakdown")
    draw_axes(draw, ymax, "seconds")
    left, top, right, bottom = chart_area()
    n = max(len(rows), 1)
    gap = 16
    bar_w = max(18, min(70, (right - left - gap * (n + 1)) / n))

    for i, row in enumerate(rows):
        x0 = left + gap + i * (bar_w + gap)
        x1 = x0 + bar_w
        compute_h = (bottom - top) * compute_vals[i] / ymax
        comm_h = (bottom - top) * comm_vals[i] / ymax
        y0 = bottom - compute_h
        draw.rectangle((x0, y0, x1, bottom), fill=COMPUTE)
        y1 = y0 - comm_h
        draw.rectangle((x0, y1, x1, y0), fill=COMM)
        draw.text((x0 - 4, bottom + 15), str(row["ranks"]), fill=TEXT, font=font(14))

    draw.text(((left + right) / 2 - 35, bottom + 55), "MPI ranks", fill=MUTED, font=font(16))
    draw_legend(draw, ["compute/local", "communication"], [COMPUTE, COMM])
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)


def bar_chart(rows: list[dict[str, str]], field: str, title: str, ylabel: str, out: Path) -> None:
    rows = sorted(rows, key=lambda r: (label_for(r), int(r["ranks"])))
    ymax = max(float(r[field]) for r in rows) * 1.15 if rows else 1.0
    if ymax <= 0:
        ymax = 1.0

    img, draw = canvas(title)
    draw_axes(draw, ymax, ylabel)
    left, top, right, bottom = chart_area()
    n = max(len(rows), 1)
    gap = 16
    bar_w = max(18, min(70, (right - left - gap * (n + 1)) / n))

    for i, row in enumerate(rows):
        x0 = left + gap + i * (bar_w + gap)
        x1 = x0 + bar_w
        val = float(row[field])
        y = bottom - (bottom - top) * val / ymax
        draw.rectangle((x0, y, x1, bottom), fill=COLORS[i % len(COLORS)])
        draw.text((x0 - 4, bottom + 15), str(row["ranks"]), fill=TEXT, font=font(14))
    draw.text(((left + right) / 2 - 35, bottom + 55), "MPI ranks", fill=MUTED, font=font(16))
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Plot MPI PageRank summary CSV files.")
    parser.add_argument("csv", nargs="+", type=Path, help="summary CSV files from mpi/profile_mpi.sh")
    parser.add_argument("--out-dir", type=Path, default=Path("results/figures"))
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    rows = load_rows(args.csv)
    out = args.out_dir
    line_chart(rows, "speedup", "MPI Speedup", "speedup", out / "mpi_speedup.png", ideal=True)
    line_chart(rows, "parallel_efficiency", "MPI Parallel Efficiency", "efficiency", out / "mpi_efficiency.png")
    stacked_runtime_chart(rows, out / "mpi_runtime_breakdown.png")
    bar_chart(rows, "comm_fraction_avg", "MPI Communication Fraction", "comm / PR time", out / "mpi_comm_fraction.png")
    bar_chart(rows, "work_imbalance", "MPI Workload Balance", "max in-edges / avg", out / "mpi_workload_balance.png")
    print(f"wrote figures to {out}")


if __name__ == "__main__":
    main()
