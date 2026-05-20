#!/usr/bin/env python3
"""
Generate a deterministic large directed CSV graph for PageRank scaling tests.

The output uses the repository CSV format:
    node_a,0,node_b,0

Defaults are chosen to exceed a 10 MB hot working set while staying within the
current C implementations' MAX_NODES=100000 static node-map pool.
"""

import argparse
import random
from pathlib import Path


DEFAULT_NODES = 100_000
DEFAULT_EDGES = 2_000_000
MAX_SUPPORTED_NODES = 100_000


def working_set_bytes(nodes: int, edges: int) -> int:
    return 3 * nodes * 8 + 2 * nodes * 4 + edges * 4


def fmt_bytes(num_bytes: int) -> str:
    mib = num_bytes / 1024 / 1024
    if mib >= 1:
        return f"{mib:.2f} MiB"
    return f"{num_bytes / 1024:.1f} KiB"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate a deterministic large directed graph CSV."
    )
    parser.add_argument(
        "-o",
        "--output",
        default="data/synthetic_large_directed.csv",
        help="Output CSV path. Default: data/synthetic_large_directed.csv",
    )
    parser.add_argument(
        "-n",
        "--nodes",
        type=int,
        default=DEFAULT_NODES,
        help=f"Number of nodes. Default: {DEFAULT_NODES}",
    )
    parser.add_argument(
        "-m",
        "--edges",
        type=int,
        default=DEFAULT_EDGES,
        help=f"Number of directed edges. Default: {DEFAULT_EDGES}",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=26,
        help="Random seed for deterministic generation. Default: 26",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    nodes = args.nodes
    edges = args.edges

    if nodes < 2:
        raise SystemExit("nodes must be at least 2")
    if nodes > MAX_SUPPORTED_NODES:
        raise SystemExit(
            f"nodes={nodes} exceeds current C MAX_NODES={MAX_SUPPORTED_NODES}; "
            "raise MAX_NODES in all implementations before generating a larger graph."
        )
    if edges < nodes:
        raise SystemExit("edges must be >= nodes so the generator can touch every node")

    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)

    rng = random.Random(args.seed)
    remaining = edges - nodes

    with out.open("w", encoding="ascii") as f:
        # A directed ring guarantees every node appears and has nonzero in/out degree.
        for u in range(nodes):
            f.write(f"{u},0,{(u + 1) % nodes},0\n")

        # Add a reproducible mix of random edges and hub-biased edges. This keeps
        # the graph simple while creating enough degree skew to make scheduling
        # and locality choices visible in the parallel implementations.
        hub_count = max(1, nodes // 100)
        for i in range(remaining):
            u = rng.randrange(nodes)
            if i % 5 == 0:
                v = rng.randrange(hub_count)
            else:
                v = rng.randrange(nodes)
            if u == v:
                v = (v + 1) % nodes
            f.write(f"{u},0,{v},0\n")

    ws = working_set_bytes(nodes, edges)
    print(f"Wrote {out}")
    print(f"Nodes: {nodes}")
    print(f"Edges: {edges}")
    print(f"Estimated PageRank hot working set: {fmt_bytes(ws)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
