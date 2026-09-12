#!/usr/bin/env bash
# Patched copy of crypto_plugins/flutter_libepiccash/scripts/windows/build_all.sh,
# applied at build time by scripts/windows/build_msys2_plugins.sh. The artifact
# copy honors CARGO_TARGET_DIR, which the MSYS2 flow points at a short path
# (e.g. C:\t\epic) because the default in-repo target dir produces object paths
# beyond Windows' 260-char limit (aws-lc-sys/jitterentropy).

set -euo pipefail

if [ "${IS_ARM:-false}" = true ]; then
    echo "[ERROR] Native Windows ARM64 plugin builds are not supported yet." >&2
    echo "        Leave IS_ARM unset to build the supported x64 bundle on Windows 11 ARM." >&2
    exit 1
fi

rustup target add x86_64-pc-windows-gnu --toolchain 1.89.0

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

TARGET_DIR="${CARGO_TARGET_DIR:-target}"

echo "Building x86_64 version"
# randomx-rust's build.rs tests cfg!(target_env="msvc"), which reflects the
# HOST (msvc here), so it emits a link-search path of .../build/Release even
# though the Ninja-built librandomx.a lands in .../build. If the link fails,
# copy the archive to the expected location and relink (incremental, fast).
if ! cargo build --target x86_64-pc-windows-gnu --release --lib; then
    for d in "$TARGET_DIR"/x86_64-pc-windows-gnu/release/build/randomx-*/out/build; do
        if [ -f "$d/librandomx.a" ] && [ ! -f "$d/Release/librandomx.a" ]; then
            mkdir -p "$d/Release"
            cp "$d/librandomx.a" "$d/Release/"
            echo "Applied randomx link-path fix-up in $d"
        fi
    done
    cargo build --target x86_64-pc-windows-gnu --release --lib
fi

cp "$TARGET_DIR/x86_64-pc-windows-gnu/release/epic_cash_wallet.dll" ../libepic_cash_wallet.dll
