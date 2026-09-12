#!/usr/bin/env bash

# Installs/selects full Xcode.app. This is split out from
# install_macos_build_tools.sh because Xcode acquisition is orthogonal to
# whether the rest of the toolchain comes from Homebrew or Nix: neither can
# provide Xcode itself (Apple's license forbids redistributing it), so this
# script must run for both kinds of setups, not just the Homebrew one.
#
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

# xcodes resolves Xcode download links via Apple's App Store Connect API, which
# has intermittently broken (returns 404 on every version, not just the one
# requested) independent of xcodes' own version. When that happens, fall back
# to installing Xcode from the Mac App Store instead, which uses a different
# distribution path and isn't affected by the same outage. This needs
# Homebrew for `mas` itself regardless of whether the rest of the toolchain
# is Homebrew- or Nix-provided -- there is no Nix package for `mas`.
install_xcode_via_mas() {
  echo "xcodes failed to download Xcode; falling back to the Mac App Store (mas)..."
  if ! command -v mas >/dev/null 2>&1; then
    if ! command -v brew >/dev/null 2>&1; then
      echo "[ERROR] Homebrew not found; can't install 'mas' automatically. Install Homebrew (https://brew.sh) or 'mas' some other way, then re-run this script." >&2
      return 1
    fi
    brew install mas
  fi
  # mas has no scriptable sign-in or account-status check; it acts as whatever
  # Apple ID is already signed into the App Store app, and its own error
  # message is the only signal if that's not set up.
  if ! mas install 497799835; then # Xcode
    echo "[ERROR] 'mas install' failed. If it's a sign-in error, open App Store.app, sign in with your Apple ID, then re-run this script." >&2
    return 1
  fi
  XCODE_APP="$(ls -d /Applications/Xcode*.app 2>/dev/null | head -1)"
  [[ -n "$XCODE_APP" ]] && sudo xcode-select -s "$XCODE_APP/Contents/Developer"
}

install_xcode() {
  ensure_xcodes
  if ! xcodes install --latest --select; then
    install_xcode_via_mas
  fi
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
  install_xcode
else
  echo "No developer tools found. Installing Xcode..."
  install_xcode
fi

sudo xcodebuild -license accept 2>/dev/null || true
sudo xcodebuild -runFirstLaunch 2>/dev/null || true
