#!/usr/bin/env python3
"""Generate course-compatible CSV graphs for PageRank scaling tests.

Output format:
    src,0,dst,0

The generator intentionally allows repeated edges by default. For performance
scaling this keeps generation fast and deterministic while preserving the
sparse irregular access pattern that PageRank exercises.
"""

import argparse
import random
from pathlib import Path
from typing import Dict, List, Tuple


PRESETS: Dict[str, List[Tuple[int, int, str]]] = {
    "smoke": [(1_000, 10_000, "synthetic_1k_10k.csv")],
    "all": [
        (10_000, 100_000, "synthetic_10k_100k.csv"),
        (50_000, 500_000, "synthetic_50k_500k.csv"),
        (100_000, 1_000_000, "synthetic_100k_1m.csv"),
    ],
    "weak": [
        (12_500, 125_000, "weak_1rank_12500_125000.csv"),
        (25_000, 250_000, "weak_2rank_25000_250000.csv"),
        (50_000, 500_000, "weak_4rank_50000_500000.csv"),
        (100_000, 1_000_000, "weak_8rank_100000_1000000.csv"),
        (200_000, 2_000_000, "weak_16rank_200000_2000000.csv"),
    ],
    "optimization": [
        (100_000, 1_000_000, "skewed_100k_1m.csv"),
    ],
}


def generate_graph(path: Path, nodes: int, edges: int, seed: int) -> None:
    if nodes < 2:
        raise ValueError("nodes must be at least 2")
    if edges < 1:
        raise ValueError("edges must be positive")

    rng = random.Random(seed)
    path.parent.mkdir(parents=True, exist_ok=True)

    with path.open("w", encoding="utf-8") as f:
        for _ in range(edges):
            src = rng.randrange(nodes)
            dst = rng.randrange(nodes - 1)
            if dst >= src:
                dst += 1
            f.write(f"{src},0,{dst},0\n")


def generate_skewed_graph(path: Path, nodes: int, edges: int, seed: int) -> None:
    """Generate a stable hot-destination graph for thread-scheduling evidence."""
    if nodes < 2:
        raise ValueError("nodes must be at least 2")
    if edges < nodes:
        raise ValueError("skewed graph needs at least one cycle edge per node")

    rng = random.Random(seed)
    hot_nodes = max(1, nodes // 16)
    path.parent.mkdir(parents=True, exist_ok=True)

    with path.open("w", encoding="utf-8") as f:
        # Stabilize parser-assigned node IDs so the hot region is contiguous.
        for src in range(nodes):
            f.write(f"{src},0,{(src + 1) % nodes},0\n")

        for _ in range(edges - nodes):
            src = rng.randrange(nodes)
            if rng.random() < 0.8:
                dst = rng.randrange(hot_nodes)
            else:
                dst = rng.randrange(nodes)
            if dst == src:
                dst = (dst + 1) % nodes
            f.write(f"{src},0,{dst},0\n")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate synthetic PageRank CSV graphs.")
    parser.add_argument("--nodes", type=int, help="number of nodes for a single graph")
    parser.add_argument("--edges", type=int, help="number of edges for a single graph")
    parser.add_argument("--output", type=Path, help="output CSV path for a single graph")
    parser.add_argument("--seed", type=int, default=2356, help="base random seed")
    parser.add_argument(
        "--preset",
        choices=sorted(PRESETS),
        help="generate a preset graph set under --output-dir",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("data/synthetic"),
        help="directory used with --preset",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    if args.preset:
        for i, (nodes, edges, filename) in enumerate(PRESETS[args.preset]):
            out = args.output_dir / filename
            if args.preset == "optimization":
                generate_skewed_graph(out, nodes, edges, args.seed + i)
            else:
                generate_graph(out, nodes, edges, args.seed + i)
            print(f"wrote {out} ({nodes} nodes, {edges} edges)")
        return

    if args.nodes is None or args.edges is None or args.output is None:
        raise SystemExit("single-graph mode requires --nodes, --edges, and --output")

    generate_graph(args.output, args.nodes, args.edges, args.seed)
    print(f"wrote {args.output} ({args.nodes} nodes, {args.edges} edges)")


if __name__ == "__main__":
    main()
