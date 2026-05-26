#!/usr/bin/env python3
"""Compatibility entry point for the canonical CSV-backed figure generator."""

from pathlib import Path
import runpy


ROOT = Path(__file__).resolve().parents[2]
runpy.run_path(str(ROOT / "scripts" / "make_paper_figures.py"), run_name="__main__")
