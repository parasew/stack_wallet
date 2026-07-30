#!/usr/bin/env bash

set -x -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <platform>"
    exit 1
fi

APP_BUILD_PLATFORM=$1

# run icon and image generators
pushd "${APP_PROJECT_ROOT_DIR}"
YAML_FILE="${APP_PROJECT_ROOT_DIR}/scripts/app_config/platforms/${APP_BUILD_PLATFORM}/flutter_launcher_icons.yaml"

if [[ "${APP_BUILD_PLATFORM}" = 'windows' ]]; then
  command -v cygpath >/dev/null 2>&1 || {
    echo "[ERROR] cygpath is required for Windows builds. Run make from Git Bash." >&2
    exit 1
  }
  MSYS2_ARG_CONV_EXCL='*' cmd.exe /c flutter pub get
  WIN_PATH_VERSION=$(cygpath -w "${YAML_FILE}")
  # FIX: Changed dart run to flutter pub run
  MSYS2_ARG_CONV_EXCL='*' cmd.exe /c flutter pub run flutter_launcher_icons -f "${WIN_PATH_VERSION}"
  # not needed in windows
# MSYS2_ARG_CONV_EXCL='*' cmd.exe /c flutter pub run flutter_native_splash:create
else
  flutter pub get
  # FIX: Changed dart run to flutter pub run
  flutter pub run flutter_launcher_icons -f "${YAML_FILE}"

  if [[ "${APP_BUILD_PLATFORM}" = 'ios' || "${APP_BUILD_PLATFORM}" = 'android' ]]; then
    # FIX: Changed dart run to flutter pub run
    flutter pub run flutter_native_splash:create
  fi
fi
popd
