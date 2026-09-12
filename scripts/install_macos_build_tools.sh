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

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
bash "$SCRIPT_DIR/install_xcode.sh"

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

# Homebrew's rustup formula is keg-only and does not necessarily create the
# cargo/rustc shims in ~/.cargo/bin — `rustup toolchain install` alone may leave
# that directory absent, which means no `cargo` on PATH in this shell or any
# future one. Create the shims via rustup-init when they are missing.
if [ ! -x "$HOME/.cargo/bin/cargo" ]; then
  echo "cargo shims missing in ~/.cargo/bin; creating them via rustup-init..."
  if command -v rustup-init >/dev/null 2>&1; then
    rustup-init -y --no-modify-path --default-toolchain 1.85.1 || true
  else
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
      | sh -s -- -y --no-modify-path --default-toolchain 1.85.1 || true
  fi
fi

# cargo/rustc live in ~/.cargo/bin after rustup installs a toolchain
export PATH="$HOME/.cargo/bin:$PATH"
source "$HOME/.cargo/env" 2>/dev/null || true

if ! command -v cargo >/dev/null 2>&1; then
  die "cargo still not on PATH after rustup setup. Run 'rustup-init -y' manually, then re-run this script."
fi

echo "Installing Rust CLI build tools..."
# cbindgen is mandatory: both macOS crypto plugin builds generate their C
# headers with it. Do not swallow a failure here — a missing cbindgen otherwise
# only surfaces much later as undefined symbols when Xcode links the app.
if ! cargo install cbindgen; then
  die "cbindgen install failed. Fix this before running 'make build-macos' (it is required to generate the plugin C headers)."
fi
# cargo-lipo is unmaintained and only needed for fat iOS builds: warn, don't fail.
cargo install cargo-lipo || echo "[WARN] cargo-lipo install failed (only needed for iOS lipo builds)."

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

# Re-verify explicitly: when this script is sourced, `set -e` is intentionally
# off, so an earlier failure would not have stopped execution.
if command -v cbindgen >/dev/null 2>&1; then
  cbindgen --version
else
  echo "[ERROR] cbindgen not found in PATH. 'make build-macos' cannot generate the"
  echo "        plugin C headers and will fail. Install it with: cargo install cbindgen"
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

# Persist PATH entries for future terminals. Create ~/.zshrc when missing: a
# vanilla macOS install ships without one, and this block used to skip silently
# in that case — leaving new shells unable to find cargo/rustup/cbindgen and
# making `source`ing this script the only way to get a usable environment.
ZSHRC="$HOME/.zshrc"
if [ ! -f "$ZSHRC" ]; then
  touch "$ZSHRC"
  echo "→ Created $ZSHRC (macOS ships without one)"
fi
grep -qF 'brew shellenv' "$ZSHRC" 2>/dev/null || \
  echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$ZSHRC"
grep -qF '$HOME/.cargo/bin' "$ZSHRC" 2>/dev/null || \
  echo 'export PATH="/opt/homebrew/opt/rustup/bin:$HOME/.cargo/bin:$PATH"' >> "$ZSHRC"
echo "→ PATH entries ensured in $ZSHRC"
echo "  Open a new terminal (or run: source $ZSHRC) before 'make build-macos'."
