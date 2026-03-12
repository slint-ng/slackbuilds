#!/bin/bash

set -euo pipefail

pkgver=6.6.3
clang_bundle=libclang-release_130-based-linux-Ubuntu20.04-gcc9.3-x86_64
qt_tarball=qt-everywhere-src-${pkgver}.tar.xz
qt_url=https://download.qt.io/archive/qt/6.6/${pkgver}/single/${qt_tarball}
clang_archive=${clang_bundle}.7z
clang_url=https://download.qt.io/development_releases/prebuilt/libclang/${clang_archive}

download_if_missing() {
  local url="$1"
  local file="$2"

  if [ -r "$file" ]; then
    return 0
  fi

  curl -fsSLo "$file" "$url"
}

download_if_missing "$qt_url" "$qt_tarball"
download_if_missing "$clang_url" "$clang_archive"

printf '%s  %s\n' \
  0e2c9dd87cbc6768da2bfc7f776c272f "$qt_tarball" \
  1eb94ba35df4aa217cf485086215182a "$clang_archive" \
  | md5sum -c -
