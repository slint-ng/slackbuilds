#!/usr/bin/env bash
set -euo pipefail

scriptDir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)

# Keep this list focused on the piper-tts packaging chain.
packageList=(
  "l/python3-pathvalidate"
  "l/python3-distro"
  "l/python3-scikit-build"
  "l/python3-onnxruntime"
  "ap/piper-tts"
  "ap/piper-voices-common"
  "ap/piper-voices-en-us"
  "ap/piper-voices-en-gb"
)

for packagePath in "${packageList[@]}"; do
  printf 'Building %s\n' "$packagePath"
  "$scriptDir/build-package.sh" --skip-staged --only "$packagePath"
done
