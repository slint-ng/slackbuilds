#!/bin/bash

VERSION=${VERSION:-0.25.3}
SOURCE_TARBALL="v$VERSION.tar.gz"
SOURCE_DIR="tree-sitter-$VERSION"
VENDORED_DIR="tree-sitter-vendored-$VERSION"

if [ ! -r "$SOURCE_TARBALL" ]; then
  echo "ERROR: $SOURCE_TARBALL not found"
  exit 1
fi

# Let's get the timestamp correct as long as we're here:
touch -d "$(tar tvf "$SOURCE_TARBALL" | head -n 1 | cut -d 0 -f 2- | cut -d ' ' -f 2-3)" "$SOURCE_TARBALL"

# Clear any existing stuff out:
rm -rf "$SOURCE_DIR" "$VENDORED_DIR" ./*.tar

# Extract the original tarball:
tar xf "$SOURCE_TARBALL"

# Vendor it:
(
cd "$SOURCE_DIR" || exit 1
  if ! [ -f /usr/bin/cargo-vendor-filterer ]; then
    echo "WARNING: Creating unfiltered vendor libs tarball!"
    cargo vendor
  else
    cargo vendor-filterer --platform="x86_64-unknown-linux-gnu" --platform="i686-unknown-linux-gnu"
  fi
)
mv "$SOURCE_DIR" "$VENDORED_DIR"

# Tar up the vendored version:
tar cf "$VENDORED_DIR.tar" "$VENDORED_DIR"
plzip -9 "$VENDORED_DIR.tar"

# Clean up:
rm -rf "$VENDORED_DIR"
