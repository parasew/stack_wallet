#!/usr/bin/env bash

set -euo pipefail

echo "=== Stack Wallet MSYS2 Environment Setup ==="
echo "Installs the MinGW-w64 toolchain and build tools needed to compile the"
echo "windows-gnu crypto plugins (flutter_libepiccash, flutter_libmwc) natively"
echo "on Windows. Run this from an MSYS2 shell (any subsystem), e.g.:"
printf '%s\n' "  C:\\msys64\\usr\\bin\\bash.exe -lc '/c/path/to/stack_wallet/scripts/windows/setup_msys2.sh'"
echo ""

if ! command -v pacman >/dev/null 2>&1; then
    echo "[ERROR] pacman not found. This script must run inside MSYS2." >&2
    echo "        Install MSYS2 first: winget install MSYS2.MSYS2" >&2
    exit 1
fi

# --- MSYS2 packages ---
# msys make + perl: required by openssl-src (the plugins build vendored OpenSSL).
# mingw-w64-x86_64-gcc: C/C++ compiler and linker for the x86_64-pc-windows-gnu
#   Rust target (provides x86_64-w64-mingw32-gcc); also supplies the MinGW
#   runtime DLLs (libstdc++-6.dll, libgcc_s_seh-1.dll) bundled with libmwc.
# mingw-w64-x86_64-clang: provides libclang.dll for bindgen (randomx, croaring).
# mingw-w64-x86_64-cmake + ninja + make: RandomX is built via the cmake crate.
# nasm: optional assembly routines in vendored OpenSSL.
echo "--- Installing MSYS2 packages..."
pacman -S --needed --noconfirm \
  git make perl tar unzip \
  mingw-w64-x86_64-gcc \
  mingw-w64-x86_64-clang \
  mingw-w64-x86_64-cmake \
  mingw-w64-x86_64-make \
  mingw-w64-x86_64-ninja \
  mingw-w64-x86_64-nasm

# NOTE: do NOT install rust or go via pacman. The build uses the Windows-host
# rustup toolchain (1.85.1) and host Go; the Makefile invokes this environment
# with MSYS2_PATH_TYPE=inherit so those host tools stay reachable.

# --- Rust windows-gnu target (host rustup) ---
# The host rustup lives in %USERPROFILE%\.cargo\bin. Recent MSYS2 versions do
# not reliably inherit the Windows PATH (MSYS2_PATH_TYPE=inherit is ignored),
# so append it explicitly instead of relying on inheritance.
echo "--- Adding Rust x86_64-pc-windows-gnu target to host toolchain 1.85.1..."
if ! command -v rustup >/dev/null 2>&1 && [ -n "${USERPROFILE:-}" ]; then
    host_cargo_bin="$(cygpath -u "$USERPROFILE")/.cargo/bin"
    export PATH="$PATH:$host_cargo_bin"
fi
if command -v rustup >/dev/null 2>&1; then
    rustup target add x86_64-pc-windows-gnu --toolchain 1.85.1
else
    echo "[WARN] Host rustup not found. Add the target manually from PowerShell or Git Bash:"
    echo "         rustup target add x86_64-pc-windows-gnu --toolchain 1.85.1"
fi

# --- Sanity probes ---
echo ""
echo "--- Verifying tools..."
for probe in \
    "/mingw64/bin/x86_64-w64-mingw32-gcc --version" \
    "/mingw64/bin/clang --version" \
    "/mingw64/bin/cmake --version" \
    "/mingw64/bin/ninja --version" \
    "perl -v" \
    "make -v"; do
    tool="${probe%% *}"
    if $probe >/dev/null 2>&1; then
        echo "[OK] $tool ($($probe 2>/dev/null | head -n1))"
    else
        echo "[ERROR] $tool failed to run" >&2
        exit 1
    fi
done

echo ""
echo "=== MSYS2 setup complete ==="
echo "Next steps:"
echo "  1. Ensure the host tools are installed (scripts/install_windows_build_tools.ps1)."
echo "  2. Build from Git Bash in the repo root: make build-windows VERSION=x.y.z BUILD_NUM=nnn"
