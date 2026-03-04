#!/usr/bin/env bash
set -euo pipefail

scriptDir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)

# Keep this list in build order. Add more category/package entries as needed.
packageList=(
  "d/python3"
  "d/python3-setuptools"
  "d/python3-pip"
  "l/python3-setproctitle"
  "l/python-tomli3.11"
  "l/pyparsing3.11"
  "l/python-importlib_metadata3.11"
  "xap/fontforge"
  "xap/orca"
  "xap/cthulhu"
)

for packagePath in "${packageList[@]}"; do
  printf 'Building %s\n' "$packagePath"
  "$scriptDir/build-package.sh" --skip-staged --only "$packagePath"
done
