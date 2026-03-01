#!/bin/bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 /path/to/pkgtools-<ver>-<arch>-<rel>.t?z" >&2
  exit 2
fi

baseline_pkg=$1
out_dir=$(pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

langs=(de el es fa fr id it nb nl pl pt_BR pt_PT ru sv tr uk)
pages=(explodepkg installpkg makepkg pkgtool removepkg upgradepkg)

case "$baseline_pkg" in
  *.txz|*.tgz|*.tlz|*.tbz|*.tbr) ;;
  *)
    echo "Expected a Slackware package archive, got: $baseline_pkg" >&2
    exit 2
    ;;
esac

if [ ! -f "$baseline_pkg" ]; then
  echo "Baseline package not found: $baseline_pkg" >&2
  exit 1
fi

mkdir -p "$tmpdir/root" "$tmpdir/manpages-l10n"
tar -C "$tmpdir/root" -xf "$baseline_pkg"
chmod 0755 "$tmpdir/manpages-l10n"
touch -d "@0" "$tmpdir/manpages-l10n"

for lang in "${langs[@]}"; do
  for page in "${pages[@]}"; do
    src="$tmpdir/root/usr/man/$lang/man8/$page.8.gz"
    dst="$tmpdir/manpages-l10n/$lang.$page"
    if [ ! -f "$src" ]; then
      echo "Missing localized manpage in baseline package: $src" >&2
      exit 1
    fi
    gzip -dc "$src" > "$dst"
    chmod 0644 "$dst"
    touch -d "@0" "$dst"
  done
done

tar --sort=name --mtime="@0" --owner=0 --group=0 --numeric-owner \
  -C "$tmpdir" -cJf "$out_dir/manpages-l10n.tar.xz" manpages-l10n
echo "Wrote $out_dir/manpages-l10n.tar.xz"
