#!/bin/bash

set -x -e

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

APP="${1:-stack_wallet}"

source "${SCRIPT_DIR}/../rust_version.sh"

if [[ "$APP" = "stack_wallet" ]]; then
    set_rust_version_for_libepiccash
    (cd "${ROOT_DIR}/crypto_plugins/flutter_libepiccash/scripts/macos" && ./build_all.sh ) &
    pid_libepiccash=$!
    # Both Epic Cash and MWC use Rust 1.89.0 — no toolchain switch needed
    (cd "${ROOT_DIR}/crypto_plugins/flutter_libmwc/scripts/macos" && ./build_all.sh ) &
    pid_libmwc=$!

    # A bare `wait` always exits 0, so `set -e` cannot see a failed background
    # job: a plugin build could die (e.g. missing cbindgen) while this script
    # still reported success, and the missing framework then surfaced minutes
    # later as "Undefined symbols for architecture arm64" at app link time.
    # Wait per-PID instead so each build's exit status propagates, and report
    # both results before failing.
    build_status=0
    wait "$pid_libepiccash" || { echo "[ERROR] flutter_libepiccash macOS build failed." >&2; build_status=1; }
    wait "$pid_libmwc" || { echo "[ERROR] flutter_libmwc macOS build failed." >&2; build_status=1; }
    if [ "$build_status" -ne 0 ]; then
        echo "[ERROR] Native plugin build failed; see the errors above." >&2
        exit 1
    fi
fi

# Frostdart removed from native build (Cargokit handles it via ffiPlugin:true)
echo "Done building native plugins"
