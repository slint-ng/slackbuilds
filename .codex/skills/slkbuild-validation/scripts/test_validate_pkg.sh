#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
validator="${script_dir}/validate_pkg.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

home_dir="${tmpdir}/home"
pkgver="20260110_06a743f"
pkg_arch="noarch"
pkg_rel="1slint"
pkg_name="firmware-installer"
pkg_dir="${home_dir}/slkbuilds/k/${pkg_name}"
stage_dir="${pkg_dir}/stage"
pkg_file="${pkg_dir}/${pkg_name}-${pkgver}-${pkg_arch}-${pkg_rel}.txz"
md5_file="${pkg_file%.txz}.md5"
log_file="${pkg_dir}/build-${pkg_name}.log"

mkdir -p "${stage_dir}/install"
mkdir -p "${stage_dir}/usr/src/${pkg_name}-${pkgver}"
mkdir -p "${stage_dir}/usr/doc/${pkg_name}-${pkgver}"
mkdir -p "${stage_dir}/lib/firmware"

cat > "${stage_dir}/install/slack-desc" <<'EOF'
firmware-installer: firmware-installer (test fixture)
EOF

cat > "${stage_dir}/usr/src/${pkg_name}-${pkgver}/SLKBUILD" <<'EOF'
pkgname=firmware-installer
EOF

cat > "${stage_dir}/usr/doc/${pkg_name}-${pkgver}/WHENCE.linux-firmware" <<'EOF'
firmware metadata
EOF

mkdir -p "$pkg_dir"
tar -C "$stage_dir" -cJf "$pkg_file" install usr lib
(cd "$pkg_dir" && md5sum "$(basename "$pkg_file")" > "$(basename "$md5_file")")

cat > "$log_file" <<EOF
Slackware package ${pkg_file} created.
EOF

if ! output="$(HOME="$home_dir" bash "$validator" "k/${pkg_name}")"; then
  printf '%s\n' "$output"
  echo "FAIL: validator should pass for firmware-installer fixture."
  exit 1
fi

if printf '%s\n' "$output" | grep -Fq "linux-firmware/WHENCE"; then
  printf '%s\n' "$output"
  echo "FAIL: firmware-installer check still requires linux-firmware/WHENCE."
  exit 1
fi

if ! printf '%s\n' "$output" | grep -Fq "PASS: installer docs -> usr/doc/${pkg_name}-${pkgver}/WHENCE.linux-firmware"; then
  printf '%s\n' "$output"
  echo "FAIL: installer docs payload check missing."
  exit 1
fi

if ! printf '%s\n' "$output" | grep -Fq "Verdict"; then
  printf '%s\n' "$output"
  echo "FAIL: validator output missing Verdict section."
  exit 1
fi

if ! printf '%s\n' "$output" | grep -Fq -- "- PASS"; then
  printf '%s\n' "$output"
  echo "FAIL: validator verdict should be PASS."
  exit 1
fi

no_rg_bin="${tmpdir}/no-rg-bin"
mkdir -p "$no_rg_bin"
required_commands=(bash basename cut find grep head mktemp printf rm sed sort tar xz)

for cmd in "${required_commands[@]}"; do
  cmd_path="$(command -v "$cmd" || true)"
  if [[ -z "$cmd_path" ]]; then
    echo "FAIL: required command not found for no-rg test: ${cmd}"
    exit 1
  fi
  ln -s "$cmd_path" "${no_rg_bin}/${cmd}"
done

if ! output_no_rg="$(HOME="$home_dir" PATH="$no_rg_bin" bash "$validator" "k/${pkg_name}")"; then
  printf '%s\n' "$output_no_rg"
  echo "FAIL: validator should pass when rg is unavailable."
  exit 1
fi

if ! printf '%s\n' "$output_no_rg" | grep -Fq "Success marker present: yes"; then
  printf '%s\n' "$output_no_rg"
  echo "FAIL: fallback mode did not detect the success marker."
  exit 1
fi

if ! printf '%s\n' "$output_no_rg" | grep -Fq -- "- PASS"; then
  printf '%s\n' "$output_no_rg"
  echo "FAIL: fallback mode verdict should be PASS."
  exit 1
fi

echo "PASS: firmware-installer regression fixture validates successfully."
