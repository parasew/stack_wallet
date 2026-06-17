#!/usr/bin/env bash
# ==============================================================================
# run_all.sh — Full benchmark suite with cold→warm pairs for cache delta
#
# Modes (each cold mode has a follow-up warm rebuild to measure cache hit):
#   1. Warm            — incremental rebuild (baseline warm)
#   2. Cold sccache    → clean + build with sccache
#   2b. Warm (cached)  — rebuild after cold sccache (measures sccache hit)
#   3. Cold no-sccache → clean + build without sccache
#   3b. Warm (no cache)— rebuild after cold no-sccache
#   4. Cold Dart-only  → clean + SKIP_NATIVE=1
#   4b. Warm Dart-only — rebuild after cold SKIP_NATIVE=1
#
# Total: 7 measurements. Each cold mode separated by make clean.
# ==============================================================================
set -euo pipefail

HOST="$(hostname -s 2>/dev/null || echo unknown)"
echo "════════════════════════════════════════════════════"
echo "  Stack Wallet — Full Benchmark Suite"
echo "  Host: $HOST  |  $(date)"
echo "════════════════════════════════════════════════════"
echo ""

# ━━━ Mode 1: Warm (incremental, no clean) ━━━
echo "━━━ 1/7: Warm rebuild (incremental) ━━━"
bash bm/bench.sh --warm --label warm
echo ""

# ━━━ Mode 2: Cold with sccache ━━━
echo "━━━ 2/7: Cold build (sccache on) ━━━"
make clean 2>/dev/null || true
bash bm/bench.sh --label cold-sccache SCCACHE=1
echo ""

# ━━━ Mode 2b: Warm after cold sccache (cache hit delta) ━━━
echo "━━━ 3/7: Warm rebuild (sccache cache hit) ━━━"
bash bm/bench.sh --warm --label warm-sccache
echo ""

# ━━━ Mode 3: Cold without sccache ━━━
echo "━━━ 4/7: Cold build (no sccache) ━━━"
make clean 2>/dev/null || true
bash bm/bench.sh --label cold-nosccache SCCACHE=0
echo ""

# ━━━ Mode 3b: Warm after cold no-sccache ━━━
echo "━━━ 5/7: Warm rebuild (no sccache) ━━━"
bash bm/bench.sh --warm --label warm-nosccache SCCACHE=0
echo ""

# ━━━ Mode 4: Cold Dart-only ━━━
echo "━━━ 6/7: Cold build (Dart only, SKIP_NATIVE=1) ━━━"
make clean 2>/dev/null || true
bash bm/bench.sh --label cold-dart-only SKIP_NATIVE=1
echo ""

# ━━━ Mode 4b: Warm Dart-only ━━━
echo "━━━ 7/7: Warm rebuild (Dart only) ━━━"
bash bm/bench.sh --warm --label warm-dart-only SKIP_NATIVE=1
echo ""

echo "════════════════════════════════════════════════════"
echo "  Done. Results: bm/results/$HOST.csv"
echo "  View:  python3 bm/compare.py bm/results/"
echo "  PDF:   python3 bm/compare.py bm/results/ > report.md && ./bm/render.sh report.md"
echo "════════════════════════════════════════════════════"