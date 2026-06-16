#!/usr/bin/env bash

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This installer is for macOS only."
  exit 1
fi

# Homebrew may not be in PATH after a fresh install
if ! command -v brew >/dev/null 2>&1; then
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  else
    echo "Homebrew is required. Install it first: https://brew.sh"
    echo 'After installing, run: eval "$(/opt/homebrew/bin/brew shellenv)"'
    exit 1
  fi
fi

# rustup is keg-only in Homebrew (conflicts with rust), manually add to PATH
RUSTUP_BIN="/opt/homebrew/opt/rustup/bin"
if [[ -d "$RUSTUP_BIN" ]] && [[ ":$PATH:" != *":$RUSTUP_BIN:"* ]]; then
  export PATH="$RUSTUP_BIN:$PATH"
fi

# cargo/rustc live in ~/.cargo/bin after rustup-init
if [[ -f "$HOME/.cargo/env" ]]; then
  source "$HOME/.cargo/env"
fi

echo "Checking Xcode..."
if ! xcode-select -p >/dev/null 2>&1; then
  echo "Xcode not found. Download from https://developer.apple.com/xcode/ or the App Store."
  echo "After installing, run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  exit 1
fi
if [[ "$(xcode-select -p)" != *"/Xcode.app"* ]]; then
  echo "Wrong Xcode path selected. Fixing..."
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
fi
sudo xcodebuild -license accept 2>/dev/null || true

echo "Installing Homebrew packages..."
brew install direnv rustup-init cmake meson ninja pkg-config gnu-sed cocoapods go protobuf autoconf automake libtool

echo "Installing Flutter cask..."
brew install --cask flutter

if ! command -v rustup >/dev/null 2>&1; then
  echo "Initializing Rust toolchain..."
  if command -v rustup-init >/dev/null 2>&1; then
    rustup-init -y
  else
    echo "rustup-init not found. Try: brew install rustup"
    exit 1
  fi
  # rustup-init adds cargo/rustc to PATH via ~/.cargo/env
  if [[ -f "$HOME/.cargo/env" ]]; then
    source "$HOME/.cargo/env"
  fi
fi

echo "Ensuring Rust 1.85.1 single toolchain..."
rustup toolchain install 1.85.1
rustup default 1.85.1
rustup target add aarch64-apple-darwin x86_64-apple-darwin aarch64-apple-ios --toolchain 1.85.1 >/dev/null 2>&1 || true

echo "Installing Rust CLI build tools..."
cargo install cargo-lipo cbindgen || true

echo "Verifying toolchain..."
if command -v flutter >/dev/null 2>&1; then
  flutter --version
else
  echo "flutter not found in PATH. Add Flutter bin to your shell profile."
fi

if command -v dart >/dev/null 2>&1; then
  dart --version
else
  echo "dart not found in PATH. It should come with Flutter."
fi

rustup --version
rustc --version
rustup run 1.85.1 rustc --version
pod --version
go version
autoreconf --version | head -n 1 || true
aclocal --version | head -n 1 || true

echo ""
echo "Done. To make these tools permanent, add to ~/.zshrc:"
echo ""
echo '  eval "$(/opt/homebrew/bin/brew shellenv)"'
echo '  export PATH="/opt/homebrew/opt/rustup/bin:$HOME/.cargo/bin:$PATH"'
echo '  export PATH="/opt/homebrew/opt/gnu-sed/libexec/gnubin:$PATH"    # for gsed'
