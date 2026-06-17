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
    echo "Homebrew not found. Installing..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [[ -x /opt/homebrew/bin/brew ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
      eval "$(/usr/local/bin/brew shellenv)"
    else
      echo "Homebrew installation failed. Install manually: https://brew.sh"
      exit 1
    fi
  fi
fi

# rustup is keg-only in Homebrew (conflicts with rust), manually add to PATH
RUSTUP_BIN="/opt/homebrew/opt/rustup/bin"
if [[ -d "$RUSTUP_BIN" ]] && [[ ":$PATH:" != *":$RUSTUP_BIN:"* ]]; then
  export PATH="$RUSTUP_BIN:$PATH"
fi

echo "Checking Xcode..."

# Install xcodes CLI for automated Xcode installation
ensure_xcodes() {
  if command -v xcodes >/dev/null 2>&1; then return 0; fi
  echo "Installing xcodes CLI for automated Xcode setup..."
  mkdir -p /usr/local/bin
  curl -fsSL https://github.com/XcodesOrg/xcodes/releases/latest/download/xcodes.zip -o /tmp/xcodes.zip
  unzip -qo /tmp/xcodes.zip -d /tmp
  sudo mv /tmp/xcodes /usr/local/bin/xcodes
  sudo chmod +x /usr/local/bin/xcodes
  rm -f /tmp/xcodes.zip
}

if ! xcode-select -p >/dev/null 2>&1; then
  echo "Xcode not found. Installing via xcodes..."
  ensure_xcodes
  xcodes install --latest --select
elif [[ "$(xcode-select -p)" != *"/Xcode.app"* ]]; then
  echo "Command Line Tools installed instead of Xcode. Installing Xcode via xcodes..."
  ensure_xcodes
  xcodes install --latest --select
fi

sudo xcodebuild -license accept 2>/dev/null || true
sudo xcodebuild -runFirstLaunch 2>/dev/null || true

echo "Installing Homebrew packages..."
brew install direnv rustup cmake meson ninja pkg-config gnu-sed cocoapods go protobuf autoconf automake libtool

echo "Installing Flutter cask..."
brew install --cask flutter

if ! command -v rustup >/dev/null 2>&1; then
  echo "rustup not found in PATH. Check brew install."
  exit 1
fi

echo "Ensuring Rust 1.85.1 single toolchain..."
rustup toolchain install 1.85.1
rustup default 1.85.1
rustup target add aarch64-apple-darwin x86_64-apple-darwin aarch64-apple-ios --toolchain 1.85.1 >/dev/null 2>&1 || true

# cargo/rustc live in ~/.cargo/bin after rustup installs a toolchain
export PATH="$HOME/.cargo/bin:$PATH"
source "$HOME/.cargo/env" 2>/dev/null || true

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
echo "Done."

# Add PATH entries to ~/.zshrc if not already present
if [ -f "$HOME/.zshrc" ]; then
  grep -qF 'brew shellenv' "$HOME/.zshrc" 2>/dev/null || \
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$HOME/.zshrc"
  grep -qF '$HOME/.cargo/bin' "$HOME/.zshrc" 2>/dev/null || \
    echo 'export PATH="/opt/homebrew/opt/rustup/bin:$HOME/.cargo/bin:$PATH"' >> "$HOME/.zshrc"
  echo "→ PATH added to ~/.zshrc for future terminals"
else
  echo "→ Add these to your shell profile for permanent PATH setup:"
  echo '  eval "$(/opt/homebrew/bin/brew shellenv)"'
  echo '  export PATH="/opt/homebrew/opt/rustup/bin:$HOME/.cargo/bin:$PATH"'
fi
