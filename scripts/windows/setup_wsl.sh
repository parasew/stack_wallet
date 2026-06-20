#!/usr/bin/env bash

set -ex

echo "=== Stack Wallet WSL2 Environment Setup ==="
echo "This script installs all dependencies needed to build Windows plugins in WSL."

# --- Base build tools ---
echo "--- Installing base build packages..."
sudo apt-get update
sudo apt-get install -y \
  curl unzip automake build-essential file pkg-config git python3 python3-pip \
  libtool cmake libgit2-dev clang llvm lld g++ gcc gperf xsltproc \
  meson ninja-build nasm valac docbook-xsl \
  autoconf libtinfo6 libncurses5-dev libncursesw5-dev zlib1g-dev \
  libopencv-dev python3-typogrify gobject-introspection \
  libgirepository1.0-dev liblzma-dev

# --- GUI libs ---
echo "--- Installing GUI libraries..."
sudo apt-get install -y \
  libgtk2.0-dev libgtk-3-dev libglib2.0-dev

# --- Crypto / system libs ---
echo "--- Installing crypto libraries..."
sudo apt-get install -y \
  libssl-dev libgcrypt20-dev libsecret-1-dev

# --- MinGW cross-compilers (for Windows DLL builds from WSL) ---
echo "--- Installing MinGW cross-compilers..."
sudo apt-get install -y \
  clang gcc-mingw-w64-x86-64 g++-mingw-w64-x86-64

# --- Android cross-compile libs (for Android builds in WSL) ---
echo "--- Installing Android cross-compile libs..."
sudo apt-get install -y libc6-dev-i386

# --- Python packages (pinned for build_app.sh compatibility) ---
echo "--- Installing Python packages..."
pip3 install --upgrade --break-system-packages \
  meson==0.64.1 markdown==3.4.1 markupsafe==2.1.1 \
  jinja2==3.1.2 pygments==2.13.0 toml==0.10.2 tomli==2.0.1

# --- Rust (single toolchain: 1.85.1) ---
echo "--- Installing Rust 1.85.1..."
if ! command -v rustup >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain 1.85.1
  source "$HOME/.cargo/env"
else
  rustup toolchain install 1.85.1
  rustup default 1.85.1
fi

echo "--- Adding Rust Windows GNU target..."
rustup target add x86_64-pc-windows-gnu --toolchain 1.85.1

# --- Go ---
echo "--- Installing Go..."
if ! command -v go >/dev/null 2>&1; then
  echo "[WARN] Go not found. Install Go manually: https://go.dev/doc/install"
  echo "  Expected version: >= 1.24 for mwebd build support."
else
  echo "Go $(go version) found."
fi

# --- cargo-ndk ---
echo "--- Installing cargo-ndk..."
cargo install cargo-ndk || true

echo ""
echo "=== WSL2 setup complete ==="
echo "Next steps:"
echo "  1. Ensure the repo is accessible from WSL at /mnt/c/path/to/stack_wallet"
echo "  2. Run: cd /mnt/c/path/to/stack_wallet/scripts/windows && ./build_wsl_plugins_only.sh"
echo "  3. Or use the full build from the Windows host: make build-windows"