#!/usr/bin/env bash
# ==============================================================================
# run_all.sh — Cold → warm pairs, ordered from simplest to most optimized.
#
# Run order:
#   A. Cold no-sccache  → clean + build without sccache (baseline)
#   B. Warm no-sccache  → rebuild after A (CARGO_TARGET_DIR benefit only)
#   C. Cold sccache     → clean + build with sccache
#   D. Warm sccache     → rebuild after C (sccache + CARGO_TARGET_DIR benefit)
#   E. Cold Dart-only   → clean + SKIP_NATIVE=1 (no Rust at all)
#   F. Warm Dart-only   → rebuild after E (Flutter incremental)
# ==============================================================================
set -euo pipefail

HOST="$(hostname -s 2>/dev/null || echo unknown)"
echo "════════════════════════════════════════════════════"
echo "  Stack Wallet — Full Benchmark Suite"
echo "  Host: $HOST  |  $(date)"
echo "════════════════════════════════════════════════════"
echo ""

# A ━━━ Cold without sccache ━━━
echo "━━━ A: Cold build (no sccache) ━━━"
make clean 2>/dev/null || true
bash bm/bench.sh --label cold-nosccache SCCACHE=0
echo ""

# B ━━━ Warm after cold no-sccache (CARGO_TARGET_DIR only) ━━━
echo "━━━ B: Warm rebuild (no sccache, CARGO_TARGET_DIR cache hit) ━━━"
bash bm/bench.sh --warm --label warm-nosccache SCCACHE=0
echo ""

# C ━━━ Cold with sccache ━━━
echo "━━━ C: Cold build (with sccache) ━━━"
make clean 2>/dev/null || true
bash bm/bench.sh --label cold-sccache SCCACHE=1
echo ""

# D ━━━ Warm after cold sccache (sccache + target dir) ━━━
echo "━━━ D: Warm rebuild (sccache + CARGO_TARGET_DIR cache hit) ━━━"
bash bm/bench.sh --warm --label warm-sccache SCCACHE=1
echo ""

# E ━━━ Cold Dart-only ━━━
echo "━━━ E: Cold build (Dart only, SKIP_NATIVE=1) ━━━"
make clean 2>/dev/null || true
bash bm/bench.sh --label cold-dart-only SKIP_NATIVE=1
echo ""

# F ━━━ Warm Dart-only ━━━
echo "━━━ F: Warm rebuild (Dart only) ━━━"
bash bm/bench.sh --warm --label warm-dart-only SKIP_NATIVE=1
echo ""

echo "════════════════════════════════════════════════════"
echo "  Done. Results: bm/results/$HOST.csv"
echo "  View:  python3 bm/compare.py bm/results/"
echo "  PDF:   python3 bm/compare.py bm/results/ > report.md && ./bm/render.sh report.md"
echo "════════════════════════════════════════════════════"