#!/usr/bin/env python3
"""
compare.py — Render benchmark results from bm/results/<host>.csv files.

Usage:
  python3 bm/compare.py bm/results/              # terminal report
  python3 bm/compare.py bm/results/ > report.md   # markdown for bm/render.sh
"""

import csv, sys, os, json
from collections import defaultdict
from pathlib import Path
from statistics import mean, stdev, median

PIPE = "│"

def load_results(results_dir):
    rows = []
    for fpath in sorted(Path(results_dir).glob("*.csv")):
        if fpath.name.startswith("sizes_"):
            continue
        try:
            with open(fpath) as f:
                reader = csv.DictReader(f)
                for r in reader:
                    if r.get("success","0") in ("1", "True"):
                        rows.append(r)
        except Exception as e:
            print(f"  skip {fpath.name}: {e}", file=sys.stderr)
    return rows



def wall_fmt(s):
    """Format seconds to human readable."""
    try:
        s = int(float(s))
        m, sec = divmod(s, 60)
        if m >= 60:
            h, m = divmod(m, 60)
            return f"{h}h{m:02d}m{sec:02d}s"
        return f"{m}m{sec:02d}s"
    except:
        return str(s)

def wall_s(s):
    """Parse string to int seconds."""
    try: return int(float(s))
    except: return 0

def mb(kb_str):
    try: return int(float(kb_str)) // 1024
    except: return 0

def hr_label(label):
    """Human readable label."""
    l = label.lower()
    if l == "cold": return "Cold build"
    if l == "warm": return "Warm rebuild"
    if l == "cold-nosccache": return "Cold (no sccache)"
    if l == "cold-sccache": return "Cold (sccache)"
    if l == "cold-dart-only": return "Cold (Dart only)"
    if l == "warm-nosccache": return "Warm (no sccache)"
    if l == "warm-sccache": return "Warm (sccache)"
    if l == "warm-dart-only": return "Warm (Dart only)"
    if "skip-native" in l: return "Dart only"
    return label

def render(rows, fmt="terminal"):
    if not rows:
        print("No successful benchmark results found.", file=sys.stderr)
        return

    # Group by host then label
    by_host = defaultdict(list)
    for r in rows:
        by_host[r.get("host","unknown")].append(r)

    hdr = ["Mode", "Commit", "Arch", "Branch", "OS", "Warm", "Flags", "Wall Time", "Disk Δ"]

    for host, host_rows in sorted(by_host.items()):
        if fmt == "markdown":
            print(f"\n## {host}\n")
        else:
            print(f"\n{'═'*80}")
            print(f"  {host}")
            print(f"{'═'*80}")

        # Sort: cold first, then by label
        host_rows.sort(key=lambda r: (r.get("warm","0"), r.get("label","")))

        if fmt == "markdown":
            print(f"| {' | '.join(hdr)} |")
            print(f"|{'|'.join(['---']*len(hdr))}|")
        else:
            # Terminal table with rich/box drawing
            widths = [max(len(h), 18) for h in hdr]
            # Print header
            print(PIPE + PIPE.join(h.center(w) for h,w in zip(hdr,widths)) + PIPE)
            print(PIPE + PIPE.join("─"*w for w in widths) + PIPE)

        for r in host_rows:
            label    = hr_label(r.get("label",""))
            commit   = r.get("commit","")[:7]
            arch     = r.get("arch","")
            branch   = r.get("branch","")[:12]
            os_str   = f"{r.get('os_name','')} {r.get('os_ver','')}"[:14]
            warm     = "yes" if r.get("warm","0") == "1" else "no"
            flags    = r.get("flags","-").replace("SCCACHE=1,","").replace("SCCACHE=0,","") or "-"
            wall     = wall_fmt(r.get("wall_sec",""))
            disk     = f"{mb(r.get('disk_delta_kb',''))}MB"

            cols = [label, commit, arch, branch, os_str, warm, flags, wall, disk]

            if fmt == "markdown":
                print(f"| {' | '.join(cols)} |")
            else:
                print(PIPE + PIPE.join(c.center(w) for c,w in zip(cols,widths)) + PIPE)

    # Comparison summary
    labels = sorted(set(r["label"] for r in rows))
    if len(labels) > 1:
        print(f"\n{'═'*80}")
        print(f"  Summary")
        print(f"{'═'*80}")
        machines = sorted(set(f"{r.get('host','')} ({r.get('arch','')} {r.get('os_name','')} {r.get('os_ver','')})" for r in rows))
        for m in machines:
            print(f"  Machine: {m}")
        for label in labels:
            lbl_rows = [r for r in rows if r["label"] == label]
            times = [wall_s(r["wall_sec"]) for r in lbl_rows]
            disks = [mb(r["disk_delta_kb"]) for r in lbl_rows]
            if len(times) >= 1:
                avg = mean(times)
                print(f"  {hr_label(label):25s}  {wall_fmt(avg):>10s}  (n={len(times)})")

    # Embed chart references for markdown output
    if fmt == "markdown":
        print("\n---")
        print("\n## Charts\n")
        charts_dir = "bm/results"
        print(f"![Build Time]({charts_dir}/chart_build_time.svg)")
        print(f"![Disk Usage]({charts_dir}/chart_disk_usage.svg)")

def compare(dir1, dir2=None):
    """Compare two result directories."""
    rows1 = load_results(dir1)
    rows2 = load_results(dir2) if dir2 else []
    all_rows = rows1 + rows2

    if not all_rows:
        print("No benchmark results found.", file=sys.stderr)
        return

    # Mark format based on output
    is_pipe = not sys.stdout.isatty()
    fmt = "markdown" if is_pipe else "terminal"

    render(all_rows, fmt)

    if dir2 and rows1 and rows2:
        print(f"\n{'═'*80}")
        print(f"  Delta: {os.path.basename(dir1)} → {os.path.basename(dir2)}")
        print(f"{'═'*80}")
        labels1 = {r["label"] for r in rows1}
        labels2 = {r["label"] for r in rows2}
        for label in sorted(labels1 & labels2):
            t1 = wall_s(rows1[0]["wall_sec"])
            t2 = wall_s(rows2[0]["wall_sec"])
            delta = t2 - t1
            pct = (delta/t1)*100 if t1 else 0
            sign = "+" if delta > 0 else ""
            print(f"  {hr_label(label):25s}  {wall_fmt(t1)} → {wall_fmt(t2)}  ({sign}{pct:.0f}%)")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <results_dir> [compare_dir]", file=sys.stderr)
        print(f"  {sys.argv[0]} bm/results/              # single report", file=sys.stderr)
        print(f"  {sys.argv[0]} old/ new/                # compare two dirs", file=sys.stderr)
        print(f"  {sys.argv[0]} bm/results/ > report.md  # markdown for PDF", file=sys.stderr)
        sys.exit(1)

    compare(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
