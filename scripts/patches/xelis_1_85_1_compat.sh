#!/usr/bin/env bash
# Replace nightly-only get_disjoint_mut with stable split_at_mut in xelis-common.
# This makes xelis compile on Rust 1.89.0 (and any Rust >= 1.0), eliminating
# the need for a dual-toolchain build.
set -euo pipefail

CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
FILE=$(find "$CARGO_HOME/git/checkouts" -path '*/xelis_common/src/contract/opaque/crypto/proofs/range_proof.rs' 2>/dev/null | head -1)

if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
  echo "xelis-common range_proof.rs not found — skipping patch"
  exit 0
fi

perl -0777 -i -pe "s/let\s*\[left,\s*right\]\s*=\s*params\.get_disjoint_mut\(\[0,\s*1\]\)\s*\n\s*\.context\(\"disjoint mut\"\)\?;/let (left_slice, right_slice) = params.split_at_mut(1); let left = \&mut left_slice[0]; let right = \&mut right_slice[0];/g" "$FILE"

echo "Patched $FILE for Rust 1.89.0 compatibility"