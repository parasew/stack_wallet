#!/usr/bin/env bash

set -x -e

source ../rust_version.sh
set_rust_version_for_libepiccash
(cd ../../crypto_plugins/flutter_libepiccash/scripts/windows && ./build_all.sh)
set_rust_version_for_libmwc
(cd ../../crypto_plugins/flutter_libmwc/scripts/windows && ./build_all.sh)

echo "Done building WSL-only plugins"