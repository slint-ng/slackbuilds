#!/usr/bin/env bash
set -euo pipefail

scriptDir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)

# Keep this list limited to packages changed in the current cleanup pass.
packageList=(
  "d/meson"
  "l/python3-pythran"
  "l/python3-setproctitle"
  "l/python3-dbus"
  "l/yt-dlp-ejs"
  "ap/translate-toolkit"
  "t/python3-gTTS"
  "ap/yt-dlp"
)

for packagePath in "${packageList[@]}"; do
  printf 'Building %s\n' "$packagePath"
  "$scriptDir/build-package.sh" --skip-staged --only "$packagePath"
done
