#!/usr/bin/env python3
"""Compare benchmark results across machines and modes."""
import csv, sys, os
from collections import defaultdict
from pathlib import Path

def load_results(results_dir):
    rows = []
    for fpath in Path(results_dir).glob("*.csv"):
        try:
            with open(fpath) as f:
                reader = csv.DictReader(f)
                rows.extend(list(reader))
        except Exception as e:
            print(f"  skip {fpath.name}: {e}", file=sys.stderr)
    return rows

def fmt_sec(s):
    try:
        s = int(float(s))
        return f"{s//60}m{s%60:02d}s"
    except: return s

def fmt_mb(kb):
    try: return f"{int(float(kb))//1024}MB"
    except: return kb

def compare(dir1, dir2=None, fmt="markdown"):
    rows1 = load_results(dir1)
    rows2 = load_results(dir2) if dir2 else []

    all_rows = rows1 + rows2
    if not all_rows:
        print("No benchmark results found.")
        return

    # Group by origin dir
    by_dir = defaultdict(list)
    for r in rows1: by_dir[os.path.basename(dir1)].append(r)
    for r in rows2: by_dir[os.path.basename(dir2)].append(r) if dir2 else None

    # Collect unique labels and hosts
    labels = sorted(set(r.get("label","") for r in all_rows))
    hosts = sorted(set(r.get("host","") for r in all_rows))

    if fmt == "markdown":
        print("# Build Benchmark Comparison\n")
        for host in hosts:
            print(f"## {host}\n")
            host_rows = [r for r in all_rows if r.get("host") == host]
            print("| Label | Branch | Warm | Flags | Wall Time | Disk Δ |")
            print("|-------|--------|------|-------|-----------|--------|")
            for r in sorted(host_rows, key=lambda x: x.get("label","")):
                branch = r.get("branch","")[:20]
                wall = fmt_sec(r.get("wall_sec",""))
                disk = fmt_mb(r.get("disk_delta_kb",""))
                warm = "yes" if r.get("warm","0") == "1" else "no"
                flags = r.get("flags","-") or "-"
                print(f"| {r['label']} | {branch} | {warm} | {flags} | {wall} | {disk} |")
            print()

    if dir2:
        print("## Comparison\n")
        print("| Metric | Before | After | Delta |")
        print("|--------|--------|-------|-------|")
        for label in labels:
            d1 = [r for r in rows1 if r.get("label") == label]
            d2 = [r for r in rows2 if r.get("label") == label]
            if d1 and d2:
                w1 = int(float(d1[0]["wall_sec"]))
                w2 = int(float(d2[0]["wall_sec"]))
                delta = w2 - w1
                sign = "+" if delta > 0 else ""
                pct = (delta/w1)*100 if w1 else 0
                print(f"| {label} (wall time) | {fmt_sec(w1)} | {fmt_sec(w2)} | {sign}{fmt_sec(abs(delta))} ({pct:+.0f}%) |")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <results_dir> [compare_dir]")
        print(f"  {sys.argv[0]} bm/results/           # single dir report")
        print(f"  {sys.argv[0]} old_results/ new_results/   # compare two dirs")
        sys.exit(1)

    compare(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
