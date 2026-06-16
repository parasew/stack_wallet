#!/usr/bin/env bash
# ==============================================================================
# bench.sh — Simple build benchmark for stack_wallet
#
# Usage:
#   bash bm/bench.sh                    # cold build with sccache (default)
#   bash bm/bench.sh --warm             # warm rebuild (no clean)
#   bash bm/bench.sh SCCACHE=0          # cold, without sccache
#   bash bm/bench.sh SKIP_NATIVE=1      # cold, Dart only
#   bash bm/bench.sh --warm SCCACHE=0   # warm, without sccache
#
# Output: bm/results/<hostname>.csv
# ==============================================================================
set -euo pipefail

HOST="$(hostname -s 2>/dev/null || echo unknown)"
OUTDIR="bm/results"
mkdir -p "$OUTDIR"
OUTFILE="${OUTDIR}/${HOST}.csv"

WARM=0
LABEL=""
MAKE_FLAGS=""

# Parse args
while [ $# -gt 0 ]; do
  case "$1" in
    --warm) WARM=1; shift ;;
    --label) LABEL="$2"; shift 2 ;;
    *) MAKE_FLAGS="$MAKE_FLAGS $1"; shift ;;
  esac
done

# Detect platform
case "$(uname -s)" in
  Darwin)  BUILD_TARGET="build-macos" ;;
  Linux)   BUILD_TARGET="build-linux" ;;
  *)       echo "Unknown platform: $(uname -s)"; exit 1 ;;
esac

# Auto-generate label
if [ -z "$LABEL" ]; then
  if [ $WARM -eq 1 ]; then
    LABEL="warm"
  else
    LABEL="cold"
  fi
fi

# Detect sccache state from flags
if echo "$MAKE_FLAGS" | grep -q "SCCACHE=0"; then
  LABEL="${LABEL}-no-sccache"
fi
if echo "$MAKE_FLAGS" | grep -q "SKIP_NATIVE=1"; then
  LABEL="${LABEL}-skip-native"
fi

DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "=== Benchmark: ${LABEL} ==="
echo "Host: $HOST  |  Date: $(date)  |  Target: ${BUILD_TARGET}"
echo "Flags:${MAKE_FLAGS:- (none)}"
echo ""

# Disk before
DISK_BEFORE=$(du -sk . 2>/dev/null | cut -f1)

# Clean unless warm
if [ $WARM -eq 0 ]; then
  echo "--- Cleaning ---"
  make clean 2>&1 | tail -1
fi

# Build
echo "--- Building (make ${BUILD_TARGET}${MAKE_FLAGS}) ---"
START=$(date +%s)
make ${BUILD_TARGET} ${MAKE_FLAGS} 2>&1 | tail -5
RC=$?
END=$(date +%s)
WALL=$((END - START))

# Disk after
DISK_AFTER=$(du -sk . 2>/dev/null | cut -f1)
DISK_DELTA=$((DISK_AFTER - DISK_BEFORE))

# Write CSV header if new file
if [ ! -f "$OUTFILE" ]; then
  echo "label,host,platform,date,warm,flags,wall_sec,success,disk_total_kb,disk_delta_kb" > "$OUTFILE"
fi

echo "${LABEL},${HOST},$(uname -s),${DATE},${WARM},${MAKE_FLAGS## },${WALL},$((RC == 0 ? 1 : 0)),${DISK_AFTER},${DISK_DELTA}" >> "$OUTFILE"

echo ""
if [ $RC -eq 0 ]; then
  echo "✓ Build succeeded in ${WALL}s ($((WALL/60))m $((WALL%60))s)"
else
  echo "✗ Build FAILED after ${WALL}s"
fi
echo "Results appended: $OUTFILE"

# Show last 3 runs
echo ""
echo "=== All results for $HOST ==="
column -t -s, "$OUTFILE" 2>/dev/null || cat "$OUTFILE"