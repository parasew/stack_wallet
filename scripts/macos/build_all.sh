#!/bin/bash

set -x -e

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

APP="${1:-stack_wallet}"

source "${SCRIPT_DIR}/../rust_version.sh"

if [[ "$APP" = "stack_wallet" ]]; then
    set_rust_version_for_libepiccash
    (cd "${ROOT_DIR}/crypto_plugins/flutter_libepiccash/scripts/macos" && ./build_all.sh ) &
    # Both Epic Cash and MWC use Rust 1.85.1 — no toolchain switch needed
    (cd "${ROOT_DIR}/crypto_plugins/flutter_libmwc/scripts/macos" && ./build_all.sh ) &
    wait
fi

# Frostdart removed from native build (Cargokit handles it via ffiPlugin:true)
echo "Done building native plugins"
