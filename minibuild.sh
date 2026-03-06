#!/usr/bin/env bash
set -euo pipefail

scriptDir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)

# Add only packages that need rebuilding for the current test cycle.
packageList=(
  "l/python3-attrs"
  "l/python3-automat"
  "l/python3-pyasn1"
  "l/python3-pyasn1-modules"
  "l/python3-idna"
  "l/python3-incremental"
  "l/python3-zope-interface"
  "l/python3-hyperlink"
  "l/python3-humanize"
  "l/python-zipp"
  "l/python-pep517"
  "l/python-pep517_3.11"
  "l/python3-importlib-metadata"
  "l/python3-click"
  "l/python3-calver"
  "l/python3-hatchling"
  "l/python3-chardet"
  "l/python3-cryptography"
  "l/python3-openssl"
  "l/python3-pynacl"
  "l/python3-service-identity"
  "l/python3-twisted"
  "l/python3-txtorcon"
  "l/python3-autobahn"
  "l/python3-mouseinfo"
  "l/python3-tqdm"
  "l/pybind11"
  "ap/fenrir"
  "ap/ulauncher"
)

for packagePath in "${packageList[@]}"; do
  printf 'Building %s\n' "$packagePath"
  "$scriptDir/build-package.sh" --skip-staged --only "$packagePath"
done
