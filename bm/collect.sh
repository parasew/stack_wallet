#!/usr/bin/env bash
# ==============================================================================
# collect.sh: Measure disk usage and artifact sizes independent of benchmarks
# Usage: ./bm/collect.sh [--outdir DIR] [--baseline NAME]
#
# Outputs a CSV with per-directory and per-artifact sizes.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/targets.sh"

OUTDIR="${BM_OUTDIR:-$REPO_ROOT/bm/results}"
BASELINE="${BM_BASELINE:-current}"
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
PLATFORM="$(detect_platform)"
HOSTNAME="$(hostname -s 2>/dev/null || echo "unknown")"

main() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --outdir)   OUTDIR="$2"; shift ;;
      --baseline) BASELINE="$2"; shift ;;
      *)          echo "Unknown: $1"; exit 1 ;;
    esac
    shift
  done

  mkdir -p "$OUTDIR"
  local csv="$OUTDIR/sizes_${BASELINE}.csv"

  echo "=== Collecting sizes ($BASELINE, $PLATFORM, $TIMESTAMP) ===" >&2

  # Header
  {
    printf "baseline,platform,hostname,date,metric,value_kb,note\n"
    echo "${BASELINE},${PLATFORM},${HOSTNAME},${TIMESTAMP},git_commit,$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo unknown),"
  } > "$csv"

  # Disk directories
  for d in "${DISK_DIRS[@]}"; do
    local path="$REPO_ROOT/$d"
    local label="disk_$(echo "$d" | tr '/.' '_')"
    if [ -d "$path" ] || [ -f "$path" ]; then
      local sz
      sz="$(du -sk "$path" 2>/dev/null | cut -f1 || echo 0)"
      echo "${BASELINE},${PLATFORM},${HOSTNAME},${TIMESTAMP},${label},${sz}," >> "$csv"
    else
      echo "${BASELINE},${PLATFORM},${HOSTNAME},${TIMESTAMP},${label},0,missing" >> "$csv"
    fi
  done

  # Artifacts
  for a in "${ARTIFACTS[@]}"; do
    local path="$REPO_ROOT/$a"
    local label="artifact_$(basename "$a" | sed 's/\.[^.]*$//' | tr '.-' '_')"
    if [ -e "$path" ]; then
      local sz
      sz="$(du -sk "$path" 2>/dev/null | cut -f1 || echo 0)"
      echo "${BASELINE},${PLATFORM},${HOSTNAME},${TIMESTAMP},${label},${sz}," >> "$csv"
    else
      echo "${BASELINE},${PLATFORM},${HOSTNAME},${TIMESTAMP},${label},0,missing" >> "$csv"
    fi
  done

  # Total project
  local total
  total="$(du -sk "$REPO_ROOT" 2>/dev/null | cut -f1 || echo 0)"
  echo "${BASELINE},${PLATFORM},${HOSTNAME},${TIMESTAMP},total_project,${total}," >> "$csv"

  # Rust target dirs aggregate
  local rust_total=0
  for d in crypto_plugins/*/target crypto_plugins/*/rust/target crypto_plugins/*/src/serai/target; do
    if [ -d "$REPO_ROOT/$d" ]; then
      local sz
      sz="$(du -sk "$REPO_ROOT/$d" 2>/dev/null | cut -f1 || echo 0)"
      rust_total=$((rust_total + sz))
    fi
  done
  echo "${BASELINE},${PLATFORM},${HOSTNAME},${TIMESTAMP},rust_targets_aggregate,${rust_total}," >> "$csv"

  # Toolchain sizes
  for tc_dir in .rustup-home .cargo-home; do
    if [ -d "$REPO_ROOT/$tc_dir" ]; then
      local tc_label="toolchain_${tc_dir#.}"
      local tc_sz
      tc_sz="$(du -sk "$REPO_ROOT/$tc_dir" 2>/dev/null | cut -f1 || echo 0)"
      echo "${BASELINE},${PLATFORM},${HOSTNAME},${TIMESTAMP},${tc_label},${tc_sz},installed_toolchains" >> "$csv"

      # Breakdown: list each toolchain
      if [ "$tc_dir" = ".rustup-home" ] && [ -d "$REPO_ROOT/$tc_dir/toolchains" ]; then
        for tc in "$REPO_ROOT/$tc_dir/toolchains"/*/; do
          local tc_name
          tc_name="$(basename "$tc")"
          local tc_sz
          tc_sz="$(du -sk "$tc" 2>/dev/null | cut -f1 || echo 0)"
          echo "${BASELINE},${PLATFORM},${HOSTNAME},${TIMESTAMP},rustup_toolchain_${tc_name},${tc_sz},installed" >> "$csv"
        done
      fi
    fi
  done

  echo "--- Sizes written to $csv ---" >&2
}

main "$@"
