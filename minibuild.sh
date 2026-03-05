#!/usr/bin/env bash
set -euo pipefail

scriptDir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)

# Add only packages that need rebuilding for the current test cycle.
packageList=(
)

for packagePath in "${packageList[@]}"; do
  printf 'Building %s\n' "$packagePath"
  "$scriptDir/build-package.sh" --skip-staged --only "$packagePath"
done
