#!/usr/bin/env bash
# Keep Rust native-assets builds on the repository's Rust 1.90.0 policy.
#
# The pinned xelis_flutter revision carries a rust-toolchain.toml for 1.91.0,
# even though its source is compatible with 1.90.0 after the xelis-common
# patch below. flutter_libepiccash is also pinned below because its selected
# revision still requests Rust 1.89.0. Apply the edits after `flutter pub get`,
# because pub resolves git packages into its cache rather than the application
# checkout.
set -euo pipefail

PROJECT_ROOT="${APP_PROJECT_ROOT_DIR:-$PWD}"
PACKAGE_CONFIG="$PROJECT_ROOT/.dart_tool/package_config.json"

XELIS_PACKAGE_URI=""
if [ -f "$PACKAGE_CONFIG" ]; then
  XELIS_PACKAGE_URI=$(awk '
    /"name": "xelis_flutter"/ { found = 1; next }
    found && /"rootUri":/ {
      value = $0
      sub(/^[[:space:]]*"rootUri": "file:\/\//, "", value)
      sub(/"[,[:space:]]*$/, "", value)
      print value
      exit
    }
  ' "$PACKAGE_CONFIG")
fi

if [ -n "$XELIS_PACKAGE_URI" ]; then
  toolchain_file="${XELIS_PACKAGE_URI%/}/rust/rust-toolchain.toml"
  if [ ! -f "$toolchain_file" ]; then
    echo "[ERROR] xelis_flutter package has no Rust toolchain file: $toolchain_file" >&2
    exit 1
  fi
  case "$(sed -n 's/^[[:space:]]*channel[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$toolchain_file")" in
    1.90.0)
      echo "Xelis Rust toolchain already pinned to 1.90.0: $toolchain_file"
      ;;
    1.91.0)
      perl -0pi -e 's/channel = "1\.91\.0"/channel = "1.90.0"/' "$toolchain_file"
      echo "Pinned Xelis native-assets toolchain to Rust 1.90.0: $toolchain_file"
      ;;
    *)
      echo "[ERROR] Unexpected Xelis Rust toolchain in $toolchain_file" >&2
      exit 1
      ;;
  esac
else
  echo "xelis_flutter is not selected in package_config.json — skipping toolchain patch"
fi

EPICCASH_PACKAGE_URI=""
if [ -f "$PACKAGE_CONFIG" ]; then
  EPICCASH_PACKAGE_URI=$(awk '
    /"name": "flutter_libepiccash"/ { found = 1; next }
    found && /"rootUri":/ {
      value = $0
      sub(/^[[:space:]]*"rootUri": "file:\/\//, "", value)
      sub(/",?$/, "", value)
      print value
      exit
    }
  ' "$PACKAGE_CONFIG")
fi

if [ -n "$EPICCASH_PACKAGE_URI" ]; then
  toolchain_file="${EPICCASH_PACKAGE_URI%/}/rust/rust-toolchain.toml"
  if [ ! -f "$toolchain_file" ]; then
    echo "[ERROR] flutter_libepiccash has no Rust toolchain file: $toolchain_file" >&2
    exit 1
  fi
  case "$(sed -n 's/^[[:space:]]*channel[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$toolchain_file")" in
    1.90.0)
      echo "EpicCash Rust toolchain already pinned to 1.90.0: $toolchain_file"
      ;;
    1.89.0)
      perl -0pi -e 's/channel = "1\.89\.0"/channel = "1.90.0"/' "$toolchain_file"
      echo "Pinned EpicCash native-assets toolchain to Rust 1.90.0: $toolchain_file"
      ;;
    *)
      echo "[ERROR] Unexpected flutter_libepiccash Rust toolchain in $toolchain_file" >&2
      exit 1
      ;;
  esac
else
  echo "flutter_libepiccash is not selected in package_config.json — skipping toolchain patch"
fi

MWC_PACKAGE_URI=""
if [ -f "$PACKAGE_CONFIG" ]; then
  MWC_PACKAGE_URI=$(awk '
    /"name": "flutter_libmwc"/ { found = 1; next }
    found && /"rootUri":/ {
      value = $0
      sub(/^[[:space:]]*"rootUri": "file:\/\//, "", value)
      sub(/",?$/, "", value)
      print value
      exit
    }
  ' "$PACKAGE_CONFIG")
fi

if [ -n "$MWC_PACKAGE_URI" ]; then
  hook_file="${MWC_PACKAGE_URI%/}/hook/build.dart"
  if [ ! -f "$hook_file" ]; then
    echo "[ERROR] flutter_libmwc has no native-assets build hook: $hook_file" >&2
    exit 1
  fi
  if grep -Fq "Platform.environment['PROTOC']" "$hook_file"; then
    echo "MWC native-assets hook already forwards PROTOC: $hook_file"
  elif grep -Fq 'final environment = <String, String>{' "$hook_file"; then
    perl -0pi -e 's~(final environment = <String, String>\{\n)~$1      '\''PROTOC'\'': Platform.environment['\''PROTOC'\''] ?? '\''protoc'\'',\n~' "$hook_file"
    echo "Patched MWC native-assets hook to forward PROTOC: $hook_file"
  else
    echo "[ERROR] Unexpected flutter_libmwc hook structure: $hook_file" >&2
    exit 1
  fi
else
  echo "flutter_libmwc is not selected in package_config.json — skipping PROTOC hook patch"
fi

CARGO_HOME_DIR="${CARGO_HOME:-$HOME/.cargo}"
FILE=$(find "$CARGO_HOME_DIR/git/checkouts" -path '*/xelis_common/src/contract/opaque/crypto/proofs/range_proof.rs' -type f 2>/dev/null | head -1 || true)

if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
  echo "xelis-common range_proof.rs not found — skipping patch"
  exit 0
fi

perl -0777 -i -pe "s/let\s*\[left,\s*right\]\s*=\s*params\.get_disjoint_mut\(\[0,\s*1\]\)\s*\n\s*\.context\(\"disjoint mut\"\)\?;/let (left_slice, right_slice) = params.split_at_mut(1); let left = \&mut left_slice[0]; let right = \&mut right_slice[0];/g" "$FILE"

echo "Patched $FILE for Rust 1.90.0 compatibility"
