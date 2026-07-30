#!/usr/bin/env bash
# Patched copy of crypto_plugins/flutter_libmwc/scripts/windows/build_all.sh,
# applied at build time by scripts/windows/build_msys2_plugins.sh (same
# mechanism as the macOS patches in scripts/patches/). The MinGW runtime DLL
# copy falls back to the compiler's bin directory, because on
# MSYS2 'gcc -print-file-name' does not resolve these DLLs (they live in
# /mingw64/bin, outside gcc's library search path).

set -euo pipefail

if [ "${IS_ARM:-false}" = true ]; then
    echo "[ERROR] Native Windows ARM64 plugin builds are not supported yet." >&2
    echo "        Leave IS_ARM unset to build the supported x64 bundle on Windows 11 ARM." >&2
    exit 1
fi

rustup target add x86_64-pc-windows-gnu --toolchain 1.85.1

mkdir -p build
echo "$(git log -1 --pretty=format:%H) $(date)" >> build/git_commit_version.txt
VERSIONS_FILE=../../lib/git_versions.dart
EXAMPLE_VERSIONS_FILE=../../lib/git_versions_example.dart
if [ ! -f "$VERSIONS_FILE" ]; then
    cp "$EXAMPLE_VERSIONS_FILE" "$VERSIONS_FILE"
fi
COMMIT=$(git log -1 --pretty=format:"%H")
OS="WINDOWS"
sed -i "/\/\*${OS}_VERSION/c\\/\*${OS}_VERSION\*\/ const ${OS}_VERSION = \"$COMMIT\";" "$VERSIONS_FILE"
rm -rf build/rust
cp -r ../../rust build/rust
cd build/rust

# Honor CARGO_TARGET_DIR (the MSYS2 flow points it at a short path like
# C:\t\mwc; the default in-repo target dir risks Windows' 260-char path limit).
TARGET_DIR="${CARGO_TARGET_DIR:-target}"

echo "Building x86_64 version"
cargo build --target x86_64-pc-windows-gnu --release --lib

cp "$TARGET_DIR/x86_64-pc-windows-gnu/release/mwc_wallet.dll" ../libmwc_wallet.dll

# Copy MinGW runtime DLLs required by libmwc_wallet.dll.
copy_mingw_runtime_dll() {
    local name="$1" path
    path="$(x86_64-w64-mingw32-gcc -print-file-name="$name")"
    if [ "$path" = "$name" ] || [ ! -f "$path" ]; then
        # MSYS2: runtime DLLs live next to the compiler in /mingw64/bin.
        path="$(dirname "$(command -v x86_64-w64-mingw32-gcc)")/$name"
    fi
    if [ ! -f "$path" ]; then
        echo "[ERROR] Cannot locate MinGW runtime DLL: $name" >&2
        exit 1
    fi
    cp "$path" ../
}
copy_mingw_runtime_dll libstdc++-6.dll
copy_mingw_runtime_dll libgcc_s_seh-1.dll
