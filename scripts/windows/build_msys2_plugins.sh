#!/usr/bin/env bash
# Builds the x86_64-pc-windows-gnu crypto plugins (flutter_libepiccash,
# flutter_libmwc) natively on Windows inside an MSYS2 MINGW64 environment.
# Invoked by `make build-windows` as:
#   MSYSTEM=MINGW64 MSYS2_PATH_TYPE=inherit CHERE_INVOKED=1 bash.exe -l -c \
#     "cd <repo>/scripts/windows && bash build_msys2_plugins.sh"
# MSYS2_PATH_TYPE=inherit keeps the host rustup/cargo (1.85.1) reachable.

set -x -e

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# The supported Windows bundle is x64, including when built on Windows 11 ARM.
# Clear any inherited project-wide ARM switch so every bundled DLL has the same
# architecture and can run together under Windows' x64 emulation.
export IS_ARM=false

if [ "${MSYSTEM:-}" != "MINGW64" ]; then
    echo "[ERROR] This script must run in an MSYS2 MINGW64 environment." >&2
    echo "        See docs/building.md (Windows host) or run via 'make build-windows'." >&2
    exit 1
fi

if ! command -v x86_64-w64-mingw32-gcc >/dev/null 2>&1; then
    echo "[ERROR] MinGW-w64 gcc not found. Run scripts/windows/setup_msys2.sh first." >&2
    exit 1
fi

# The host rustup/cargo live in %USERPROFILE%\.cargo\bin. Recent MSYS2
# versions ignore MSYS2_PATH_TYPE=inherit and may not even pass USERPROFILE
# through the login shell (both observed on the 2026-06-11 installer), so
# probe several candidates and append the first that contains cargo (at the
# end, so MSYS2's own tools keep priority).
if ! command -v cargo >/dev/null 2>&1; then
    cargo_candidates=()
    [ -n "${USERPROFILE:-}" ] && cargo_candidates+=("$(cygpath -u "$USERPROFILE")/.cargo/bin")
    [ -n "${USERNAME:-}" ] && cargo_candidates+=("/c/Users/${USERNAME}/.cargo/bin")
    [ -n "${USER:-}" ] && cargo_candidates+=("/c/Users/${USER}/.cargo/bin")
    cargo_candidates+=("$HOME/.cargo/bin")
    for d in "${cargo_candidates[@]}"; do
        if [ -x "$d/cargo" ] || [ -x "$d/cargo.exe" ]; then
            export PATH="$PATH:$d"
            break
        fi
    done
fi

if ! command -v cargo >/dev/null 2>&1; then
    echo "[ERROR] cargo not found. Expected the host Rust toolchain on PATH or in" >&2
    printf '%s\n' '        %USERPROFILE%\.cargo\bin (install via rustup).' >&2
    exit 1
fi

# Windows caps absolute paths at 260 chars and the dependency builds
# (aws-lc-sys/jitterentropy) go ~200 chars deep. Cargo output is therefore
# redirected to a short out-of-repo target root (below); the repo path itself
# should still be reasonably short.
repo_root_win="$(cd ../.. && pwd -W)"
if [ "${#repo_root_win}" -gt 60 ]; then
    echo "[WARN] Repository path is long (${#repo_root_win} chars): ${repo_root_win}" >&2
    echo "       If builds fail with path/mkdir errors, move the repo to e.g. C:\\sw." >&2
fi

# Short out-of-repo cargo target root (override with STACK_CARGO_TARGET_ROOT).
# The in-repo default (crypto_plugins/<plugin>/scripts/windows/build/rust/target)
# alone eats ~75 chars and pushes aws-lc-sys object paths past the 260 limit
# even from a single-letter repo root. The patched plugin scripts honor
# CARGO_TARGET_DIR for their artifact copies.
STACK_CARGO_TARGET_ROOT="${STACK_CARGO_TARGET_ROOT:-C:/t}"
mkdir -p "$(cygpath -u "$STACK_CARGO_TARGET_ROOT")/epic" "$(cygpath -u "$STACK_CARGO_TARGET_ROOT")/mwc"

# Local patches: DLL-copy fallback for MSYS2 (gcc -print-file-name does not
# resolve the runtime DLLs here) and CARGO_TARGET_DIR support. Same mechanism
# as the macOS patches applied by the Makefile.
cp ../patches/flutter_libepiccash_windows_build_all.sh \
   ../../crypto_plugins/flutter_libepiccash/scripts/windows/build_all.sh
cp ../patches/flutter_libmwc_windows_build_all.sh \
   ../../crypto_plugins/flutter_libmwc/scripts/windows/build_all.sh
chmod +x ../../crypto_plugins/flutter_libepiccash/scripts/windows/build_all.sh \
         ../../crypto_plugins/flutter_libmwc/scripts/windows/build_all.sh

# Clean stale plugin build dirs from previous runs: rerunning the stock scripts
# with an existing build/ nests a second rust/ copy inside it. Compiled deps
# are preserved in the external CARGO_TARGET_DIR, so this stays cheap.
rm -rf ../../crypto_plugins/flutter_libepiccash/scripts/windows/build/rust \
       ../../crypto_plugins/flutter_libmwc/scripts/windows/build/rust

# Deterministic linker for the windows-gnu cargo target.
export CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER=x86_64-w64-mingw32-gcc
# randomx-rust's build.rs tests cfg!(target_env="msvc"), which reflects the
# BUILD HOST, so on a Windows/MSVC host it skips the `-l stdc++` directive its
# Linux cross-build branch emits. Link the C++ runtime explicitly; the DLL is
# bundled with the app via the libmwc plugin. Harmless for links that do not
# need it.
export CARGO_TARGET_X86_64_PC_WINDOWS_GNU_RUSTFLAGS="${CARGO_TARGET_X86_64_PC_WINDOWS_GNU_RUSTFLAGS:-} -C link-arg=-lstdc++"
# bindgen (randomx, croaring) needs libclang.
export LIBCLANG_PATH="${LIBCLANG_PATH:-/mingw64/bin}"
# CMake 4.x removed compatibility with cmake_minimum_required < 3.5 (RandomX).
export CMAKE_POLICY_VERSION_MINIMUM="${CMAKE_POLICY_VERSION_MINIMUM:-3.5}"
# The default "MinGW Makefiles" generator refuses to run when sh.exe is on
# PATH, which is always true inside MSYS2.
export CMAKE_GENERATOR="${CMAKE_GENERATOR:-Ninja}"

# shellcheck source=scripts/rust_version.sh
source "$SCRIPT_DIR/../rust_version.sh"
set_rust_version_for_libepiccash
(cd ../../crypto_plugins/flutter_libepiccash/scripts/windows && CARGO_TARGET_DIR="$STACK_CARGO_TARGET_ROOT/epic" ./build_all.sh)
set_rust_version_for_libmwc
(cd ../../crypto_plugins/flutter_libmwc/scripts/windows && CARGO_TARGET_DIR="$STACK_CARGO_TARGET_ROOT/mwc" ./build_all.sh)

echo "Done building native Windows (MSYS2/MinGW) plugins"
