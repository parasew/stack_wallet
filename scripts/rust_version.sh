#!/usr/bin/env bash

set_rust_to_everything_else() {
  if rustup toolchain list | grep -q "1.89.0"; then
    rustup default 1.89.0
  else
    echo "Rust 1.89.0 toolchain is not installed..."
    echo "Bypassed by Nix"
  fi
}

set_rust_version_for_libepiccash() {
  if rustup toolchain list | grep -q "1.89.0"; then
    rustup default 1.89.0
  else
    echo "Rust version 1.89.0 is not installed. Please install it using 'rustup install 1.89.0'." >&2
    echo "Bypassed by Nix"
  fi
}

# Both libepiccash and libmwc use the same Rust 1.89.0 toolchain
set_rust_version_for_libmwc() {
  set_rust_version_for_libepiccash
}
