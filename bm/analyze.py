#!/usr/bin/env python3
"""
analyze.py — Merge benchmark CSVs and generate comparison report.

Usage: python3 bm/analyze.py <results_dir> [--format table|markdown]

Reads benchmark CSVs (timing + disk) and size snapshot CSVs.
Groups by target × baseline and computes statistics.
Outputs a comparison table suitable for client presentations.
"""
import csv
import os
import sys
import json
from collections import defaultdict
from statistics import mean, stdev, median
from pathlib import Path


def parse_benchmark_csvs(results_dir):
    """Parse benchmark CSVs (target.csv) into target -> baseline -> [rows]."""
    data = defaultdict(lambda: defaultdict(list))

    for fpath in Path(results_dir).glob("*.csv"):
        name = fpath.name
        # Skip sizes snapshots and hyperfine raw output
        if name.startswith("sizes_") or name.startswith("hf_"):
            continue

        try:
            with open(fpath) as f:
                reader = csv.DictReader(f)
                for row in reader:
                    tid = row.get("target", "").strip()
                    bl = row.get("baseline", "unknown").strip()
                    if tid and bl:
                        data[tid][bl].append(row)
        except Exception:
            continue

    return data


def parse_sizes_csvs(results_dir):
    """Parse sizes_*.csv into baseline -> platform -> {metric: value_kb}."""
    sizes = defaultdict(lambda: defaultdict(dict))
    toolchain_counts = defaultdict(lambda: defaultdict(int))

    for fpath in Path(results_dir).glob("sizes_*.csv"):
        try:
            with open(fpath) as f:
                reader = csv.DictReader(f)
                for row in reader:
                    bl = row.get("baseline", "").strip()
                    plat = row.get("platform", "").strip()
                    metric = row.get("metric", "").strip()
                    val = row.get("value_kb", "0").strip()

                    if metric == "toolchain_count":
                        toolchain_counts[bl][plat] = int(val)
                    elif metric not in ("git_commit", ""):
                        try:
                            sizes[bl][plat][metric] = int(val)
                        except ValueError:
                            pass
        except Exception:
            continue

    return sizes, toolchain_counts


def compute_stats(rows, field):
    """Compute statistics for a numeric field across runs."""
    vals = []
    for r in rows:
        try:
            v = float(r.get(field, 0))
            vals.append(v)
        except (ValueError, TypeError):
            pass
    if not vals:
        return None
    return {
        "n": len(vals),
        "mean": mean(vals),
        "stddev": stdev(vals) if len(vals) > 1 else 0,
        "min": min(vals),
        "max": max(vals),
        "median": median(vals),
    }


def fmt_sec(v):
    """Format seconds nicely."""
    if v is None:
        return "N/A"
    if v < 10:
        return f"{v:.1f}s"
    if v < 60:
        return f"{v:.0f}s"
    m = int(v // 60)
    s = v % 60
    return f"{m}m{s:.0f}s"


def fmt_mb(kb):
    """Format KB as MB or GB."""
    if kb is None or kb == 0:
        return "—"
    mb = kb / 1024
    if mb >= 1024:
        return f"{mb/1024:.1f}G"
    return f"{mb:.0f}M"


def fmt_pct(new, old):
    """Format percentage change."""
    if old is None or old == 0:
        return "—"
    change = (new - old) / old * 100
    if change > 0:
        return f"+{change:.0f}%"
    return f"{change:.0f}%"


def generate_report(results_dir):
    """Generate a comprehensive markdown report."""
    bench = parse_benchmark_csvs(results_dir)
    sizes, toolchains = parse_sizes_csvs(results_dir)
    lines = []

    if not bench:
        lines.append("No benchmark data found.")
        return "\n".join(lines)

    # Collect all baselines and platforms
    all_baselines = sorted(set(
        bl for tdata in bench.values() for bl in tdata.keys()
    ))
    all_platforms = sorted(set(
        row.get("platform", "?") for tdata in bench.values()
        for rows in tdata.values() for row in rows
    ))

    # Machine metadata
    meta_lines = []
    for fpath in sorted(Path(results_dir).glob("machine_*.json")):
        try:
            with open(fpath) as f:
                m = json.load(f)
            meta_lines.append(
                f"| {m['hostname']} | {m['platform']} | {m['arch']} | "
                f"{m['cpus']} cores | {int(m['memory_mb']/1024)} GB |"
            )
        except Exception:
            pass

    # ---- Report header ----
    lines.append("# Stack Wallet — Build Benchmark Report")
    lines.append("")
    import datetime as dt_mod
    lines.append(f"**Generated:** {dt_mod.datetime.now(dt_mod.timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}")
    lines.append("")
    lines.append(f"**Baselines compared:** {', '.join(all_baselines)}")
    lines.append(f"**Platforms tested:** {', '.join(all_platforms)}")
    lines.append("")

    if meta_lines:
        lines.append("## Test Machines")
        lines.append("")
        lines.append("| Machine | OS | Arch | CPU | RAM |")
        lines.append("|---|---|---|---|---|")
        lines.extend(meta_lines)
        lines.append("")

    # ---- Build Timing ----
    lines.append("## Full Build Time")
    lines.append("")
    lines.append("| Build Target | Platform | " + " | ".join(all_baselines) + " | Improvement |")
    lines.append("|" + " --- |" * (len(all_baselines) + 3) + "")

    # Sort: full builds first, then steps
    order = {k: i for i, k in enumerate([
        "build-macos-cold", "build-linux-cold",
        "build-macos-warm", "build-macos-after-clean",
        "macos-prepare", "macos-configure", "macos-build-native",
        "macos-build-app", "macos-restore-metadata",
        "check-reqs", "check-reqs-macos", "init-submodules", "patch-submodules",
        "bootstrap-macos", "bootstrap-nix",
    ])}

    def sort_key(tid):
        return (order.get(tid, 999), tid)

    for target_id in sorted(bench.keys(), key=sort_key):
        tdata = bench[target_id]

        for platform in all_platforms:
            # Only show if this target has data for this platform
            platform_rows_exist = any(
                any(r.get("platform") == platform for r in rows)
                for rows in tdata.values()
            )
            if not platform_rows_exist:
                continue

            cells = []
            has_data = False
            vals = []

            for bl in all_baselines:
                rows = tdata.get(bl, [])
                plat_rows = [r for r in rows if r.get("platform") == platform]
                stats = compute_stats(plat_rows, "wall_sec")
                if stats:
                    val = (stats["mean"], stats["stddev"])
                    vals.append(val[0])
                    cells.append(fmt_sec(val[0]))
                    has_data = True
                else:
                    cells.append("—")

            if not has_data:
                continue

            # Improvement vs slowest baseline
            if vals and len(vals) > 1:
                slowest = max(v for v in vals if v > 0)
                fastest = min(v for v in vals if v > 0)
                pct = fmt_pct(fastest, slowest)
            else:
                pct = "—"

            lines.append(f"| {target_id} | {platform} | " + " | ".join(cells) + f" | {pct} |")

    lines.append("")
    lines.append("![Full build time comparison](chart_build_time.svg)")
    lines.append("")

    # ---- Disk Usage from benchmark runs ----
    lines.append("## Disk Usage (post-build)")
    lines.append("")
    lines.append("| Target | Platform | Metric | " + " | ".join(all_baselines) + " | Change |")
    lines.append("|" + " --- |" * (len(all_baselines) + 4) + "")

    disk_metrics = [
        ("disk_total_kb", "Build dirs (KB)"),
        ("artifact_total_kb", "Artifacts (KB)"),
        ("project_total_kb", "Total project (KB)"),
    ]

    for target_id in sorted(bench.keys(), key=sort_key):
        tdata = bench[target_id]
        for platform in all_platforms:
            for field, label in disk_metrics:
                vals = {}
                for bl in all_baselines:
                    rows = tdata.get(bl, [])
                    plat_rows = [r for r in rows if r.get("platform") == platform]
                    stats = compute_stats(plat_rows, field)
                    vals[bl] = stats["mean"] if stats else None

                if all(v is None or v == 0 for v in vals.values()):
                    continue

                cells = [fmt_mb(vals.get(bl)) for bl in all_baselines]

                # Change
                first_bl = all_baselines[0]
                last_bl = all_baselines[-1]
                change = fmt_pct(vals.get(last_bl), vals.get(first_bl))

                lines.append(
                    f"| {target_id} | {platform} | {label} | "
                    + " | ".join(cells) + f" | {change} |"
                )
            break  # One platform row per target for disk metrics

    lines.append("![Disk usage after build](chart_disk_usage.svg)")
    lines.append("")

    # ---- Size Snapshots ----
    if any(d for d in sizes.values()):
        lines.append("## Directory Size Snapshots")
        lines.append("")

        # Collect all unique metrics
        all_metrics = set()
        for bdata in sizes.values():
            for pdata in bdata.values():
                all_metrics.update(pdata.keys())

        # Filter to interesting ones
        interesting = [m for m in sorted(all_metrics) if not m.startswith("rustup_toolchain_")]
        # Show disk_* metrics
        disk_metrics_snap = [m for m in interesting if m.startswith("disk_")]
        other_metrics = [m for m in interesting if not m.startswith("disk_")]

        if disk_metrics_snap:
            # Pick representative platform
            rep_platform = all_platforms[0] if all_platforms else "macos"

            lines.append(f"| Directory | " + " | ".join(all_baselines) + " | Change |")
            lines.append("|" + " --- |" * (len(all_baselines) + 2) + "")

            for metric in disk_metrics_snap:
                label = metric.replace("disk_", "").replace("_", "/").replace("__", ".")
                if label == "total_project":
                    continue
                vals = {}
                for bl in all_baselines:
                    v = sizes.get(bl, {}).get(rep_platform, {}).get(metric)
                    vals[bl] = v

                if all(v is None for v in vals.values()):
                    continue

                cells = [fmt_mb(vals.get(bl)) for bl in all_baselines]
                first_bl = all_baselines[0]
                last_bl = all_baselines[-1]
                change = fmt_pct(vals.get(last_bl), vals.get(first_bl))
                lines.append(f"| {label} | " + " | ".join(cells) + f" | {change} |")

            lines.append("")

        # Total project size
        total_metrics = [m for m in other_metrics if "total" in m.lower()]
        if total_metrics:
            lines.append("| Metric | " + " | ".join(all_baselines) + " | Change |")
            lines.append("|" + " --- |" * (len(all_baselines) + 2) + "")
            for metric in total_metrics:
                label = metric.replace("_", " ").title()
                vals = {}
                for bl in all_baselines:
                    v = sizes.get(bl, {}).get(rep_platform, {}).get(metric)
                    vals[bl] = v
                cells = [fmt_mb(vals.get(bl)) for bl in all_baselines]
                first_bl = all_baselines[0]
                last_bl = all_baselines[-1]
                change = fmt_pct(vals.get(last_bl), vals.get(first_bl))
                lines.append(f"| {label} | " + " | ".join(cells) + f" | {change} |")
            lines.append("")

    # ---- Toolchain Counts ----
    if any(tc for tc in toolchains.values()):
        lines.append("## Rust Toolchain Consolidation")
        lines.append("")
        lines.append("| Baseline | Platform | Toolchains needed |")
        lines.append("|---|---|---|")
        for bl in all_baselines:
            for plat in all_platforms:
                tc = toolchains.get(bl, {}).get(plat)
                if tc is not None:
                    lines.append(f"| {bl} | {plat} | {tc} |")
        lines.append("")
    lines.append("![Toolchain consolidation](chart_toolchain.svg)")
    lines.append("")

    # ---- Build Phase Breakdown ----
    lines.append("![Build phase timeline](chart_phase_breakdown.svg)")
    lines.append("")

    phase_targets = [
        "macos-prepare", "macos-configure", "macos-restore-metadata",
        "macos-build-native", "macos-build-app",
    ]
    phase_labels = {
        "macos-prepare": "Sanitize & prep",
        "macos-configure": "Configure & submodules",
        "macos-restore-metadata": "Restore Flutter metadata",
        "macos-build-native": "Native crypto deps (Rust)",
        "macos-build-app": "Final Flutter compile",
    }

    if any(tid in bench for tid in phase_targets):
        lines.append("## Build Phase Breakdown (macOS)")
        lines.append("")

        for platform in all_platforms:
            if platform != "macos":
                continue

            # Build a stacked time table
            lines.append(f"| Phase | " + " | ".join(all_baselines) + " | % of total |")
            lines.append("|" + " --- |" * (len(all_baselines) + 2) + "")

            total_per_bl = {}
            phase_data = {}
            for bl in all_baselines:
                total = 0
                for tid in phase_targets:
                    if tid not in bench:
                        continue
                    rows = bench[tid].get(bl, [])
                    plat_rows = [r for r in rows if r.get("platform") == platform]
                    stats = compute_stats(plat_rows, "wall_sec")
                    v = stats["mean"] if stats else 0
                    phase_data.setdefault(tid, {})[bl] = v
                    total += v
                total_per_bl[bl] = total

            for tid in phase_targets:
                if tid not in phase_data:
                    continue
                label = phase_labels.get(tid, tid)
                cells = []
                for bl in all_baselines:
                    v = phase_data[tid].get(bl, 0)
                    cells.append(fmt_sec(v) if v > 0 else "—")
                pct_cell = ""
                if all_baselines and total_per_bl.get(all_baselines[-1], 0) > 0:
                    pct = phase_data[tid].get(all_baselines[-1], 0) / total_per_bl[all_baselines[-1]] * 100
                    pct_cell = f"{pct:.0f}%"
                lines.append(f"| {label} | " + " | ".join(cells) + f" | {pct_cell} |")

            # Total row
            cells = [fmt_sec(total_per_bl.get(bl, 0)) for bl in all_baselines]
            lines.append(f"| **Total** | " + " | ".join(cells) + " | **100%** |")

        lines.append("")

    # ---- Key Findings ----
    lines.append("## Key Findings")
    lines.append("")

    # Find full build targets
    full_builds = [tid for tid in bench if "cold" in tid or "build-macos" in tid or "build-linux" in tid]
    for tid in sorted(full_builds):
        tdata = bench[tid]
        for platform in all_platforms:
            vals = []
            for bl in all_baselines:
                rows = tdata.get(bl, [])
                plat_rows = [r for r in rows if r.get("platform") == platform]
                stats = compute_stats(plat_rows, "wall_sec")
                if stats:
                    vals.append((bl, stats["mean"], stats["stddev"]))

            if len(vals) >= 2:
                slowest = max(vals, key=lambda x: x[1])
                fastest = min(vals, key=lambda x: x[1])
                improvement = ((slowest[1] - fastest[1]) / slowest[1]) * 100
                lines.append(
                    f"- **{tid}** ({platform}): "
                    f"reduced from {fmt_sec(slowest[1])} ({slowest[0]}) "
                    f"to {fmt_sec(fastest[1])} ({fastest[0]}) "
                    f"— **{improvement:.0f}% faster**"
                )

    # Disk reduction
    rep_platform = all_platforms[0] if all_platforms else "macos"
    if all_baselines and rep_platform in sizes.get(all_baselines[-1], {}):
        first = sizes.get(all_baselines[0], {}).get(rep_platform, {})
        last = sizes.get(all_baselines[-1], {}).get(rep_platform, {})
        total_key = next((k for k in last if "total_project" in k.lower() or k == "total_project"), None)
        if total_key and first.get(total_key) and last.get(total_key):
            delta = first[total_key] - last[total_key]
            pct = (delta / first[total_key]) * 100
            lines.append(
                f"- **Project disk footprint** reduced by "
                f"{fmt_mb(delta)} ({pct:.0f}%)"
            )

    # Toolchain reduction
    for plat in all_platforms:
        tc_first = toolchains.get(all_baselines[0], {}).get(plat)
        tc_last = toolchains.get(all_baselines[-1], {}).get(plat)
        if tc_first and tc_last and tc_first != tc_last:
            lines.append(
                f"- **Rust toolchains** reduced from {tc_first} to {tc_last} "
                f"({plat}) — simpler onboarding"
            )

    lines.append("")
    lines.append("![Time savings overview](chart_improvement.svg)")
    lines.append("")

    return "\n".join(lines)


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 bm/analyze.py <results_dir> [--format markdown|table]", file=sys.stderr)
        sys.exit(1)

    results_dir = sys.argv[1]
    if not os.path.isdir(results_dir):
        print(f"Error: '{results_dir}' is not a directory", file=sys.stderr)
        sys.exit(1)

    report = generate_report(results_dir)
    print(report)


if __name__ == "__main__":
    main()
