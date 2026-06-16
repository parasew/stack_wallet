#!/usr/bin/env bash
# ==============================================================================
# run_all.sh — Run full benchmark suite with clean isolation between cold runs
#
# Modes:
#   1. Warm   — rebuild without clean (measures incremental compilation)
#   2. Cold   — clean + full build (measures from-scratch time)
#   3. Cold (no sccache) — clean + build without sccache
#   4. Cold (Dart only)   — clean + SKIP_NATIVE=1 (measures Flutter-only time)
#
# Each cold mode runs 'make clean' before its build so disk deltas are accurate.
# ==============================================================================
set -euo pipefail

echo "════════════════════════════════════════════════════"
echo "  Stack Wallet — Full Benchmark Suite"
echo "  $(date)"
echo "════════════════════════════════════════════════════"
echo ""

# Mode 1: Warm rebuild (no clean)
echo "━━━ Mode 1: Warm rebuild (incremental) ━━━"
bash bm/bench.sh --warm
echo ""

# Mode 2: Cold full build
echo "━━━ Mode 2: Cold build ━━━"
make clean 2>/dev/null || true
bash bm/bench.sh
echo ""

# Mode 3: Cold without sccache
echo "━━━ Mode 3: Cold build (no sccache) ━━━"
make clean 2>/dev/null || true
bash bm/bench.sh SCCACHE=0
echo ""

# Mode 4: Dart-only (skip native Rust)
echo "━━━ Mode 4: Dart-only build (SKIP_NATIVE=1) ━━━"
make clean 2>/dev/null || true
bash bm/bench.sh SKIP_NATIVE=1
echo ""

echo "════════════════════════════════════════════════════"
echo "  Done. Results: bm/results/$(hostname -s).csv"
echo "  View:  python3 bm/compare.py bm/results/"
echo "  PDF:   python3 bm/compare.py bm/results/ > report.md && ./bm/render.sh report.md"
echo "════════════════════════════════════════════════════"