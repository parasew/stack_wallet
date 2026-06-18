#!/usr/bin/env python3
"""
charts.py: Generate SVG charts for the benchmark report.

Usage: python3 bm/charts.py <results_dir> <output_dir>

Produces SVG images that are embedded in the markdown report.
Uses matplotlib with a clean, professional style suitable for PDF.
"""
import csv
import sys
import os
from collections import defaultdict
from statistics import mean
from pathlib import Path

import matplotlib
matplotlib.use("SVG")
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import numpy as np

# ---- color palette ----
BASELINE_COLORS = {
    "before-changes": "#94a3b8",   # slate
    "upstream-merged": "#60a5fa",  # blue-400
    "current": "#2563eb",           # blue-600
}
BASELINE_ORDER = ["before-changes", "upstream-merged", "current"]
BASELINE_LABELS = {
    "before-changes": "Before changes (March '26)",
    "upstream-merged": "Upstream staging",
    "current": "Current (this work)",
}

plt.rcParams.update({
    "font.family": "sans-serif",
    "font.size": 9,
    "axes.titlesize": 11,
    "axes.labelsize": 9,
    "figure.dpi": 150,
    "savefig.dpi": 150,
    "savefig.bbox": "tight",
    "savefig.pad_inches": 0.15,
})


def parse_data(results_dir):
    """Parse benchmark CSVs into target -> baseline -> {wall_sec, disk_kb, ...}."""
    data = defaultdict(lambda: defaultdict(dict))
    platforms = set()

    for fpath in Path(results_dir).glob("*.csv"):
        name = fpath.name
        if name.startswith("sizes_") or name.startswith("hf_"):
            continue
        try:
            with open(fpath) as f:
                reader = csv.DictReader(f)
                for row in reader:
                    tid = row.get("target", "").strip()
                    bl = row.get("baseline", "").strip()
                    plat = row.get("platform", "").strip()
                    if not tid or not bl:
                        continue
                    platforms.add(plat)
                    try:
                        sec = float(row.get("wall_sec", 0))
                    except (ValueError, TypeError):
                        sec = 0
                    try:
                        disk = int(row.get("disk_total_kb", 0))
                    except (ValueError, TypeError):
                        disk = 0
                    try:
                        proj = int(row.get("project_total_kb", 0))
                    except (ValueError, TypeError):
                        proj = 0
                    try:
                        art = int(row.get("artifact_total_kb", 0))
                    except (ValueError, TypeError):
                        art = 0

                    if tid not in data or bl not in data[tid]:
                        data[tid][bl] = {"secs": [], "disk_kb": [], "proj_kb": [], "art_kb": [], "platform": plat}
                    data[tid][bl]["secs"].append(sec)
                    data[tid][bl]["disk_kb"].append(disk)
                    data[tid][bl]["proj_kb"].append(proj)
                    data[tid][bl]["art_kb"].append(art)
        except Exception:
            continue

    # Compute means
    result = {}
    for tid, bdata in data.items():
        result[tid] = {}
        for bl, vals in bdata.items():
            result[tid][bl] = {
                "sec": mean(vals["secs"]) if vals["secs"] else 0,
                "disk_mb": mean(vals["disk_kb"]) / 1024 if vals["disk_kb"] else 0,
                "proj_mb": mean(vals["proj_kb"]) / 1024 if vals["proj_kb"] else 0,
                "art_mb": mean(vals["art_kb"]) / 1024 if vals["art_kb"] else 0,
                "platform": vals["platform"],
            }

    return result, sorted(platforms)


def chart_build_time(data, out_dir):
    """Grouped bar chart: full build time per baseline."""
    targets = ["build-macos-cold", "build-linux-cold"]
    available = [t for t in targets if t in data]
    if not available:
        return None

    fig, ax = plt.subplots(figsize=(8, 4))

    bls = [b for b in BASELINE_ORDER if any(b in data.get(t, {}) for t in available)]
    x = np.arange(len(available))
    width = 0.25

    for i, bl in enumerate(bls):
        vals = []
        for t in available:
            v = data[t].get(bl, {}).get("sec", 0)
            vals.append(v / 60)  # minutes
        bars = ax.bar(x + i * width, vals, width, label=BASELINE_LABELS.get(bl, bl),
                      color=BASELINE_COLORS.get(bl, "#999"))
        for bar, v in zip(bars, vals):
            if v > 0:
                ax.text(bar.get_x() + bar.get_width() / 2, bar.get_height() + 0.3,
                        f"{v:.0f}m", ha="center", va="bottom", fontsize=8)

    labels = [t.replace("build-", "").replace("-cold", "").replace("macos", "macOS").replace("linux", "Linux") for t in available]
    ax.set_xticks(x + width)
    ax.set_xticklabels(labels, fontsize=10)
    ax.set_ylabel("Minutes", fontsize=9)
    ax.set_title("Full Build Time", fontsize=12, fontweight="bold")
    ax.legend(fontsize=8, framealpha=0.9)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.grid(axis="y", alpha=0.3)

    path = os.path.join(out_dir, "chart_build_time.svg")
    fig.savefig(path)
    plt.close(fig)
    return os.path.basename(path)


def chart_phase_breakdown(data, out_dir):
    """Horizontal stacked bar: where time is spent in the build."""
    phases = ["macos-prepare", "macos-configure", "macos-restore-metadata",
              "macos-build-native", "macos-build-app"]
    phase_labels = ["Sanitize", "Configure", "Restore metadata",
                    "Native deps (Rust)", "Flutter compile"]
    available = [p for p in phases if p in data]
    if len(available) < 2:
        return None

    fig, ax = plt.subplots(figsize=(8, 3.5))

    bls = [b for b in BASELINE_ORDER if any(b in data.get(p, {}) for p in available)]
    colors = ["#2563eb", "#3b82f6", "#60a5fa", "#93c5fd", "#bfdbfe"]

    y_pos = range(len(bls))
    bar_height = 0.6

    for i, bl in enumerate(bls):
        left = 0
        for j, phase in enumerate(available):
            sec = data[phase].get(bl, {}).get("sec", 0)
            if sec > 0:
                ax.barh(i, sec / 60, bar_height, left=left,
                        color=colors[j % len(colors)],
                        label=phase_labels[j] if i == 0 else "",
                        edgecolor="white", linewidth=0.5)
                if sec > 60 and j == len(available) - 1:
                    total = sum(data[p].get(bl, {}).get("sec", 0) for p in available) / 60
                    ax.text(left + sec / 60 + 0.2, i, f"{total:.0f}m",
                            va="center", fontsize=8, fontweight="bold")
                left += sec / 60

    ax.set_yticks(list(y_pos))
    ax.set_yticklabels([BASELINE_LABELS.get(bl, bl) for bl in bls], fontsize=9)
    ax.set_xlabel("Minutes", fontsize=9)
    ax.set_title("Build Phase Breakdown (macOS)", fontsize=12, fontweight="bold")
    ax.legend(fontsize=7, loc="lower right", framealpha=0.9, ncol=2)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.grid(axis="x", alpha=0.3)

    path = os.path.join(out_dir, "chart_phase_breakdown.svg")
    fig.savefig(path)
    plt.close(fig)
    return os.path.basename(path)


def chart_disk_usage(data, out_dir):
    """Grouped bar chart: disk usage per baseline for full build."""
    targets = ["build-macos-cold", "build-linux-cold"]
    available = [t for t in targets if t in data]
    if not available:
        return None

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(9, 3.5))

    bls = [b for b in BASELINE_ORDER if any(b in data.get(t, {}) for t in available)]

    # Chart 1: Build dirs
    x = np.arange(len(available))
    width = 0.25
    for i, bl in enumerate(bls):
        vals = []
        for t in available:
            v = data[t].get(bl, {}).get("disk_mb", 0)
            vals.append(v / 1024)  # GB
        ax1.bar(x + i * width, vals, width, label=BASELINE_LABELS.get(bl, bl),
                color=BASELINE_COLORS.get(bl, "#999"))
    labels = [t.replace("build-", "").replace("-cold", "").replace("macos", "macOS").replace("linux", "Linux") for t in available]
    ax1.set_xticks(x + width)
    ax1.set_xticklabels(labels, fontsize=8)
    ax1.set_ylabel("GB", fontsize=8)
    ax1.set_title("Build Dirs", fontsize=10, fontweight="bold")
    ax1.legend(fontsize=7, framealpha=0.9)
    ax1.spines["top"].set_visible(False)
    ax1.spines["right"].set_visible(False)
    ax1.grid(axis="y", alpha=0.3)

    # Chart 2: Artifacts
    for i, bl in enumerate(bls):
        vals = []
        for t in available:
            v = data[t].get(bl, {}).get("art_mb", 0)
            vals.append(v)
        ax2.bar(x + i * width, vals, width, label=BASELINE_LABELS.get(bl, bl),
                color=BASELINE_COLORS.get(bl, "#999"))
    ax2.set_xticks(x + width)
    ax2.set_xticklabels(labels, fontsize=8)
    ax2.set_ylabel("MB", fontsize=8)
    ax2.set_title("Artifacts", fontsize=10, fontweight="bold")
    ax2.legend(fontsize=7, framealpha=0.9)
    ax2.spines["top"].set_visible(False)
    ax2.spines["right"].set_visible(False)
    ax2.grid(axis="y", alpha=0.3)

    fig.suptitle("Disk Usage After Full Build", fontsize=12, fontweight="bold", y=1.02)
    fig.tight_layout()

    path = os.path.join(out_dir, "chart_disk_usage.svg")
    fig.savefig(path)
    plt.close(fig)
    return os.path.basename(path)


def chart_improvement(data, out_dir):
    """Horizontal bar: % improvement (current vs before-changes) per target."""
    targets = [
        ("build-macos-cold", "Full macOS build"),
        ("build-linux-cold", "Full Linux build"),
        ("build-macos-warm", "Incremental build"),
        ("macos-build-native", "Native crypto deps"),
        ("macos-build-app", "Flutter compile"),
        ("bootstrap-macos", "Bootstrap (macOS)"),
        ("bootstrap-nix", "Nix shell enter"),
    ]
    items = []
    for tid, label in targets:
        if tid in data and "before-changes" in data[tid] and "current" in data[tid]:
            old = data[tid]["before-changes"].get("sec", 0)
            new = data[tid]["current"].get("sec", 0)
            if old > 0:
                pct = (old - new) / old * 100
                items.append((label, pct, old / 60, new / 60))

    if len(items) < 2:
        return None

    items.sort(key=lambda x: x[1], reverse=True)
    labels = [x[0] for x in items]
    pcts = [x[1] for x in items]
    old_times = [x[2] for x in items]
    new_times = [x[3] for x in items]

    fig, ax = plt.subplots(figsize=(8, 3.5))

    colors = ["#2563eb" if p >= 30 else "#60a5fa" if p >= 15 else "#93c5fd" for p in pcts]
    bars = ax.barh(labels, pcts, color=colors, height=0.6)

    for bar, pct, old_t, new_t in zip(bars, pcts, old_times, new_times):
        ax.text(bar.get_width() + 1, bar.get_y() + bar.get_height() / 2,
                f"{pct:.0f}%  ({old_t:.0f}m → {new_t:.0f}m)",
                va="center", fontsize=7.5)

    ax.set_xlabel("Improvement (%)", fontsize=9)
    ax.set_title("Time Savings (Current vs Before Changes)", fontsize=12, fontweight="bold")
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.grid(axis="x", alpha=0.3)
    ax.set_xlim(0, max(pcts) * 1.25)

    path = os.path.join(out_dir, "chart_improvement.svg")
    fig.savefig(path)
    plt.close(fig)
    return os.path.basename(path)


def chart_toolchain_reduction(sizes_dir, out_dir):
    """Simple bar chart: number of Rust toolchains per baseline."""
    toolchains = {}
    for fpath in Path(sizes_dir).glob("sizes_*.csv"):
        try:
            with open(fpath) as f:
                reader = csv.DictReader(f)
                for row in reader:
                    bl = row.get("baseline", "").strip()
                    metric = row.get("metric", "").strip()
                    if metric == "toolchain_count":
                        plat = row.get("platform", "").strip()
                        tc = int(row.get("value_kb", 0))
                        key = f"{bl} ({plat})"
                        toolchains[key] = tc
        except Exception:
            continue

    if not toolchains:
        return None

    bls = [b for b in BASELINE_ORDER if any(b in k for k in toolchains.keys())]

    fig, ax = plt.subplots(figsize=(5, 2.5))

    # Aggregate per baseline
    for i, bl in enumerate(bls):
        vals = [v for k, v in toolchains.items() if bl in k]
        tc = max(vals) if vals else 0
        ax.bar(i, tc, color=BASELINE_COLORS.get(bl, "#999"), width=0.5)
        ax.text(i, tc + 0.1, str(tc), ha="center", fontsize=14, fontweight="bold")

    ax.set_xticks(range(len(bls)))
    ax.set_xticklabels([BASELINE_LABELS.get(bl, bl) for bl in bls], fontsize=9)
    ax.set_ylabel("Toolchains", fontsize=9)
    ax.set_title("Rust Toolchain Consolidation", fontsize=12, fontweight="bold")
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.set_ylim(0, max(toolchains.values()) + 1)
    ax.yaxis.set_major_locator(mticker.MaxNLocator(integer=True))

    path = os.path.join(out_dir, "chart_toolchain.svg")
    fig.savefig(path)
    plt.close(fig)
    return os.path.basename(path)


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 bm/charts.py <results_dir> [output_dir]", file=sys.stderr)
        sys.exit(1)

    results_dir = sys.argv[1]
    out_dir = sys.argv[2] if len(sys.argv) > 2 else results_dir
    os.makedirs(out_dir, exist_ok=True)

    data, platforms = parse_data(results_dir)

    charts = []
    for fn in [chart_build_time, chart_phase_breakdown, chart_disk_usage,
                chart_improvement, chart_toolchain_reduction]:
        try:
            if fn == chart_toolchain_reduction:
                result = fn(results_dir, out_dir)
            else:
                result = fn(data, out_dir)
            if result:
                charts.append(result)
        except Exception as e:
            print(f"  Chart {fn.__name__}: {e}", file=sys.stderr)

    print(f"Generated {len(charts)} charts in {out_dir}/")
    for c in charts:
        print(f"  {c}")


if __name__ == "__main__":
    main()
