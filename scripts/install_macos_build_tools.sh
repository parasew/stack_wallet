#!/usr/bin/env bash

# Safe to source (source script.sh) or execute directly (./script.sh)
if [ -n "${ZSH_VERSION:-}" ]; then
  if [[ "${ZSH_EVAL_CONTEXT:-}" == *file* ]]; then
    set -uo pipefail                           # sourced in zsh, don't -e
  else
    set -euo pipefail                          # executed in zsh
  fi
elif [ -n "${BASH_VERSION:-}" ]; then
  if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    set -uo pipefail                           # sourced in bash, don't -e
  else
    set -euo pipefail                          # executed in bash
  fi
else
  set -euo pipefail                            # unknown shell
fi
die() { echo "$@" >&2; return 1 2>/dev/null || exit 1; }

if [[ "$(uname -s)" != "Darwin" ]]; then
  die "This installer is for macOS only."
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
      die "Homebrew installation failed. Install manually: https://brew.sh"
    fi
  fi
fi

# rustup is keg-only in Homebrew (conflicts with rust), manually add to PATH
RUSTUP_BIN="/opt/homebrew/opt/rustup/bin"
if [[ -d "$RUSTUP_BIN" ]] && [[ ":$PATH:" != *":$RUSTUP_BIN:"* ]]; then
  export PATH="$RUSTUP_BIN:$PATH"
fi

echo "Checking Xcode..."

# Install xcodes CLI for automated Xcode installation (only used if Xcode.app isn't on disk)
ensure_xcodes() {
  if command -v xcodes >/dev/null 2>&1; then return 0; fi
  echo "Installing xcodes CLI for automated Xcode setup..."
  sudo mkdir -p /usr/local/bin
  curl -fsSL https://github.com/XcodesOrg/xcodes/releases/latest/download/xcodes.zip -o /tmp/xcodes.zip
  unzip -qo /tmp/xcodes.zip -d /tmp
  sudo mv /tmp/xcodes /usr/local/bin/xcodes
  sudo chmod +x /usr/local/bin/xcodes
  rm -f /tmp/xcodes.zip
}

if ls /Applications/Xcode*.app >/dev/null 2>&1; then
  # Xcode.app already on disk: just fix xcode-select if needed
  XCODE_APP="$(ls -d /Applications/Xcode*.app 2>/dev/null | head -1)"
  if ! xcode-select -p >/dev/null 2>&1 || [[ "$(xcode-select -p)" != *"/Xcode.app"* ]]; then
    echo "Xcode.app found at $XCODE_APP. Setting xcode-select path..."
    sudo xcode-select -s "$XCODE_APP/Contents/Developer"
  else
    echo "Xcode.app already configured."
  fi
elif xcode-select -p >/dev/null 2>&1; then
  echo "Command Line Tools found but Xcode.app is required for macOS builds. Installing Xcode..."
  ensure_xcodes
  xcodes install --latest --select
else
  echo "No developer tools found. Installing Xcode..."
  ensure_xcodes
  xcodes install --latest --select
fi

sudo xcodebuild -license accept 2>/dev/null || true
sudo xcodebuild -runFirstLaunch 2>/dev/null || true

echo "Installing Homebrew packages..."
brew install direnv rustup cmake meson ninja pkg-config gnu-sed cocoapods go protobuf autoconf automake libtool pandoc weasyprint toilet figlet sccache

echo "Installing Flutter cask..."
brew install --cask flutter

if ! command -v rustup >/dev/null 2>&1; then
  die "rustup not found in PATH. Check brew install."
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
