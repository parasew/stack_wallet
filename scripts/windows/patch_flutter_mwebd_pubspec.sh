#!/usr/bin/env bash
# Stack Wallet uses mwebd.exe as a subprocess on Windows, not the FFI DLL, so
# libmwebd.dll is not needed. Strip the upstream flutter_mwebd plugin's
# 'windows: ffiPlugin' declaration from the cached package so its separate FFI
# build never runs. Idempotent; port of the CI workaround in
# .github/workflows/build.yaml ("Patch flutter_mwebd to skip Windows FFI build").
set -euo pipefail

to_posix() {
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -u "$1"
    else
        echo "$1"
    fi
}

candidates=()
if [ -n "${PUB_CACHE:-}" ]; then
    candidates+=("$(to_posix "$PUB_CACHE")/hosted/pub.dev")
fi
if [ -n "${LOCALAPPDATA:-}" ]; then
    candidates+=("$(to_posix "$LOCALAPPDATA")/Pub/Cache/hosted/pub.dev")
fi

plugin_dir=""
for cache_root in "${candidates[@]}"; do
    [ -d "$cache_root" ] || continue
    plugin_dir=$(find "$cache_root" -maxdepth 1 -type d -name 'flutter_mwebd-*' -print -quit)
    [ -n "$plugin_dir" ] && break
done

if [ -z "$plugin_dir" ] || [ ! -f "$plugin_dir/pubspec.yaml" ]; then
    echo "[ERROR] Could not locate flutter_mwebd in the pub cache." >&2
    echo "        Searched: ${candidates[*]:-<none>}" >&2
    echo "        Run 'flutter pub get' first." >&2
    exit 1
fi

pubspec="$plugin_dir/pubspec.yaml"
if grep -qE '^      windows:$' "$pubspec"; then
    # -i.bak keeps this portable between GNU and BSD sed (repo convention).
    sed -i.bak '/^      windows:$/,/^        ffiPlugin: true$/d' "$pubspec"
    rm -f "$pubspec.bak"
    echo "Patched $pubspec (removed windows ffiPlugin declaration)"
else
    echo "Already patched: $pubspec"
fi
