#!/usr/bin/env python3
"""Create GPU-offload comparison figures from the Dardel summary CSV files."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


TEXT = (15, 23, 42)
MUTED = (100, 116, 139)
GRID = (226, 232, 240)
COLORS = {
    "serial": (100, 116, 139),
    "naive": (249, 115, 22),
    "persistent": (16, 185, 129),
    "8x2": (36, 99, 235),
}
SETUP = (245, 158, 11)
KERNEL = (36, 99, 235)
TEARDOWN = (239, 68, 68)


def font(size: int) -> ImageFont.ImageFont:
    try:
        return ImageFont.truetype("Arial.ttf", size)
    except OSError:
        return ImageFont.load_default()


def load(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as stream:
        return list(csv.DictReader(stream))


def frame(title: str) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    image = Image.new("RGB", (1400, 900), "white")
    draw = ImageDraw.Draw(image)
    draw.text((70, 35), title, fill=TEXT, font=font(30))
    return image, draw


def axes(draw: ImageDraw.ImageDraw, maximum: float) -> tuple[int, int, int, int]:
    left, top, right, bottom = 115, 120, 1310, 760
    draw.line((left, bottom, right, bottom), fill=TEXT, width=2)
    draw.line((left, top, left, bottom), fill=TEXT, width=2)
    for index in range(6):
        y = bottom - (bottom - top) * index / 5
        value = maximum * index / 5
        draw.line((left, y, right, y), fill=GRID, width=1)
        draw.text((30, y - 9), f"{value:.4f}", fill=MUTED, font=font(14))
    draw.text((28, top - 34), "seconds", fill=MUTED, font=font(16))
    return left, top, right, bottom


def runtime_comparison(rows: list[dict[str, str]], out_path: Path) -> None:
    values = [float(row["pr_time_avg_s"]) for row in rows]
    maximum = max(values) * 1.18 if values else 1.0
    image, draw = frame("Dardel GPU Node: PageRank Runtime Comparison")
    left, top, right, bottom = axes(draw, maximum)
    width = 180
    gap = 78
    x = left + 75
    for row, value in zip(rows, values):
        label = row["configuration"]
        color = COLORS.get(label, (139, 92, 246))
        height = (bottom - top) * value / maximum
        draw.rectangle((x, bottom - height, x + width, bottom), fill=color)
        draw.text((x + 14, bottom - height - 30), f"{value:.6f}", fill=TEXT, font=font(16))
        draw.text((x + 18, bottom + 22), label, fill=TEXT, font=font(18))
        draw.text((x + 18, bottom + 48), row["implementation"], fill=MUTED, font=font(14))
        x += width + gap
    out_path.parent.mkdir(parents=True, exist_ok=True)
    image.save(out_path)


def mapping_breakdown(rows: list[dict[str, str]], out_path: Path) -> None:
    gpu = [row for row in rows if row["variant"] in ("naive", "persistent")]
    maximum = max(float(row["pr_time_avg_s"]) for row in gpu) * 1.18 if gpu else 1.0
    image, draw = frame("OpenMP Target Data Mapping Optimization")
    left, top, right, bottom = axes(draw, maximum)
    width = 250
    x = left + 230
    for row in gpu:
        segments = [
            ("setup", float(row["target_setup_avg_s"]), SETUP),
            ("kernel", float(row["kernel_time_avg_s"]), KERNEL),
            ("teardown", float(row["target_teardown_avg_s"]), TEARDOWN),
        ]
        y = bottom
        for _label, value, color in segments:
            height = (bottom - top) * value / maximum
            draw.rectangle((x, y - height, x + width, y), fill=color)
            y -= height
        total = float(row["pr_time_avg_s"])
        draw.text((x + 40, y - 30), f"{total:.6f}", fill=TEXT, font=font(17))
        draw.text((x + 75, bottom + 25), row["variant"], fill=TEXT, font=font(18))
        x += width + 180
    lx, ly = 1020, 100
    for label, color in [("setup/map", SETUP), ("kernel/iterations", KERNEL), ("teardown/copy", TEARDOWN)]:
        draw.rectangle((lx, ly, lx + 18, ly + 18), fill=color)
        draw.text((lx + 27, ly - 3), label, fill=TEXT, font=font(15))
        ly += 28
    out_path.parent.mkdir(parents=True, exist_ok=True)
    image.save(out_path)


def main() -> None:
    parser = argparse.ArgumentParser(description="Plot Dardel GPU PageRank result CSVs.")
    parser.add_argument("comparison", type=Path, help="gpu_vs_hybrid summary CSV")
    parser.add_argument("gpu_summary", type=Path, help="gpu_offload summary CSV")
    parser.add_argument("--out-dir", type=Path, default=Path("results/figures/dardel_gpu"))
    args = parser.parse_args()

    runtime_comparison(load(args.comparison), args.out_dir / "gpu_pr_time_comparison.png")
    mapping_breakdown(load(args.gpu_summary), args.out_dir / "gpu_mapping_breakdown.png")
    print(f"wrote figures to {args.out_dir}")


if __name__ == "__main__":
    main()
