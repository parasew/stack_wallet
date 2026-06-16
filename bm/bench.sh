#!/usr/bin/env bash
# ==============================================================================
# bench.sh — Simple build benchmark for stack_wallet
#
# Usage (one-liner to share):
#   bash bm/bench.sh
#   bash bm/bench.sh SCCACHE=0
#   bash bm/bench.sh SKIP_NATIVE=1
#
# Output: bm/results/<label>_<hostname>_<date>.csv
# ==============================================================================
set -euo pipefail

LABEL="${1:-default}"
HOST="$(hostname -s 2>/dev/null || echo unknown)"
DATE="$(date -u +%Y%m%d-%H%M%S)"
OUTDIR="bm/results"
mkdir -p "$OUTDIR"
OUTFILE="${OUTDIR}/${LABEL}_${HOST}_${DATE}.csv"

echo "=== Benchmark: ${LABEL} ==="
echo "Host: $HOST"
echo "Date: $(date)"
echo ""

# Flags to pass to make
MAKE_FLAGS="${*:-}"
if [ -n "$MAKE_FLAGS" ]; then
  echo "Extra flags: $MAKE_FLAGS"
  MAKE_FLAGS="${MAKE_FLAGS}"
else
  MAKE_FLAGS=""
fi

# Measure disk before
DISK_BEFORE=$(du -sk . 2>/dev/null | cut -f1)

# Clean first
echo "--- Cleaning ---"
make clean 2>&1 | tail -1

# Time the build
echo "--- Building (make build-macos ${MAKE_FLAGS}) ---"
START=$(date +%s)
make build-macos ${MAKE_FLAGS} 2>&1 | tail -5
RC=${PIPESTATUS[0]}
END=$(date +%s)
WALL=$((END - START))

# Measure disk after
DISK_AFTER=$(du -sk . 2>/dev/null | cut -f1)
DISK_BUILD=$(du -sk build/ .cargo-target/ .build-home/ .pub-cache/ 2>/dev/null | awk '{s+=$1} END {print s}')
DISK_DELTA=$((DISK_AFTER - DISK_BEFORE))

# Output
echo ""
if [ $RC -eq 0 ]; then
  echo "✓ Build succeeded in ${WALL}s"
else
  echo "✗ Build FAILED after ${WALL}s"
fi

# Write CSV
echo "label,host,date,flags,wall_sec,success,disk_total_kb,disk_delta_kb,disk_build_kb" > "$OUTFILE"
echo "${LABEL},${HOST},${DATE},${MAKE_FLAGS},${WALL},$((RC == 0 ? 1 : 0)),${DISK_AFTER},${DISK_DELTA},${DISK_BUILD}" >> "$OUTFILE"

echo ""
echo "Results: $OUTFILE"
cat "$OUTFILE"
