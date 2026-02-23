#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
validator="${script_dir}/validate_pkg.sh"
validation_root="/home/sektor/projects/slackbuilds"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

fixture_root="${tmpdir}/fixtures"
pkgver="20260110_06a743f"
pkg_arch="noarch"
pkg_rel="1slint"
pkg_name="firmware-installer"
pkg_dir="${fixture_root}/k/${pkg_name}"
stage_dir="${pkg_dir}/stage"
pkg_file="${pkg_dir}/${pkg_name}-${pkgver}-${pkg_arch}-${pkg_rel}.txz"
md5_file="${pkg_file%.txz}.md5"
log_file="${pkg_dir}/build-${pkg_name}.log"
txz_log_file="${pkg_dir}/build-${pkg_name}-${pkgver}-${pkg_arch}-${pkg_rel}.log"
noise_log_file="${pkg_dir}/build-unrelated.log"
missing_probe="__codex_validation_probe__/$(basename "$tmpdir")"
missing_probe_path="${validation_root}/${missing_probe}"

if output_missing="$(bash "$validator" "$missing_probe" 2>&1)"; then
  printf '%s\n' "$output_missing"
  echo "FAIL: missing relative probe should fail."
  exit 1
fi

if ! printf '%s\n' "$output_missing" | grep -Fq "Package directory: ${missing_probe_path}"; then
  printf '%s\n' "$output_missing"
  echo "FAIL: relative package probe did not resolve under repo validation root."
  exit 1
fi

if ! printf '%s\n' "$output_missing" | grep -Fq "Provide a valid package directory under ${validation_root}."; then
  printf '%s\n' "$output_missing"
  echo "FAIL: missing-path guidance did not mention the repo validation root."
  exit 1
fi

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

if ! output="$(bash "$validator" "$pkg_dir")"; then
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

cat > "$txz_log_file" <<EOF
selftest error: simulated non-fatal probe result
Slackware package ${pkg_file} created.
EOF

# Make unrelated log newer to ensure the validator is not "latest log" only.
sleep 1
cat > "$noise_log_file" <<'EOF'
build() failed
ERROR: unrelated scratch build
EOF

if ! output_matched_log="$(bash "$validator" "$pkg_dir")"; then
  printf '%s\n' "$output_matched_log"
  echo "FAIL: validator should pass when artifact-matched build log is valid."
  exit 1
fi

if ! printf '%s\n' "$output_matched_log" | grep -Fq "Build log: ${txz_log_file}"; then
  printf '%s\n' "$output_matched_log"
  echo "FAIL: validator did not choose the artifact-matched build log."
  exit 1
fi

if ! printf '%s\n' "$output_matched_log" | grep -Fq "Log selection: artifact-name"; then
  printf '%s\n' "$output_matched_log"
  echo "FAIL: validator did not report artifact-name log selection."
  exit 1
fi

if ! printf '%s\n' "$output_matched_log" | grep -Fq "Non-fatal error-pattern hits (success marker present):"; then
  printf '%s\n' "$output_matched_log"
  echo "FAIL: validator did not report non-fatal error-pattern hits."
  exit 1
fi

if ! printf '%s\n' "$output_matched_log" | grep -Fq -- "- PASS"; then
  printf '%s\n' "$output_matched_log"
  echo "FAIL: validator should keep non-fatal probe errors as PASS."
  exit 1
fi

no_rg_bin="${tmpdir}/no-rg-bin"
mkdir -p "$no_rg_bin"
required_commands=(awk bash basename cut find grep head mktemp printf rm sed sort tar xz)

for cmd in "${required_commands[@]}"; do
  cmd_path="$(command -v "$cmd" || true)"
  if [[ -z "$cmd_path" ]]; then
    echo "FAIL: required command not found for no-rg test: ${cmd}"
    exit 1
  fi
  ln -s "$cmd_path" "${no_rg_bin}/${cmd}"
done

if ! output_no_rg="$(PATH="$no_rg_bin" bash "$validator" "$pkg_dir")"; then
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

codex_pkg_name="codex"
codex_pkgver="0.104.0"
codex_pkg_arch="x86_64"
codex_pkg_rel="1slint"
codex_pkg_dir="${fixture_root}/d/${codex_pkg_name}"
codex_stage_dir="${codex_pkg_dir}/stage"
codex_pkg_file="${codex_pkg_dir}/${codex_pkg_name}-${codex_pkgver}-${codex_pkg_arch}-${codex_pkg_rel}.txz"
codex_md5_file="${codex_pkg_file%.txz}.md5"
codex_log_file="${codex_pkg_dir}/build-${codex_pkg_name}-${codex_pkgver}-${codex_pkg_arch}-${codex_pkg_rel}.log"

create_codex_fixture() {
  local include_binary="$1"
  local empty_fish_completion="$2"

  rm -rf "$codex_pkg_dir"
  mkdir -p "${codex_stage_dir}/install"
  mkdir -p "${codex_stage_dir}/usr/src/${codex_pkg_name}-${codex_pkgver}"
  mkdir -p "${codex_stage_dir}/usr/bin"
  mkdir -p "${codex_stage_dir}/usr/share/bash-completion/completions"
  mkdir -p "${codex_stage_dir}/usr/share/zsh/site-functions"
  mkdir -p "${codex_stage_dir}/usr/share/fish/vendor_completions.d"
  mkdir -p "${codex_pkg_dir}"

  cat > "${codex_stage_dir}/install/slack-desc" <<'EOF'
codex: codex (test fixture)
EOF

  cat > "${codex_stage_dir}/usr/src/${codex_pkg_name}-${codex_pkgver}/SLKBUILD" <<'EOF'
pkgname=codex
EOF

  if [[ "$include_binary" == "yes" ]]; then
    cat > "${codex_stage_dir}/usr/bin/codex" <<'EOF'
#!/bin/sh
echo codex
EOF
    chmod 755 "${codex_stage_dir}/usr/bin/codex"
  fi

  cat > "${codex_stage_dir}/usr/share/bash-completion/completions/codex" <<'EOF'
_codex() { :; }
EOF

  cat > "${codex_stage_dir}/usr/share/zsh/site-functions/_codex" <<'EOF'
#compdef codex
_arguments '*: :->args'
EOF

  if [[ "$empty_fish_completion" == "yes" ]]; then
    : > "${codex_stage_dir}/usr/share/fish/vendor_completions.d/codex.fish"
  else
    cat > "${codex_stage_dir}/usr/share/fish/vendor_completions.d/codex.fish" <<'EOF'
complete -c codex -f
EOF
  fi

  tar -C "$codex_stage_dir" -cJf "$codex_pkg_file" install usr
  (cd "$codex_pkg_dir" && md5sum "$(basename "$codex_pkg_file")" > "$(basename "$codex_md5_file")")
}

create_codex_fixture "yes" "no"
cat > "$codex_log_file" <<EOF
Slackware package ${codex_pkg_file} created.
EOF

if ! output_codex_pass="$(bash "$validator" "$codex_pkg_dir")"; then
  printf '%s\n' "$output_codex_pass"
  echo "FAIL: validator should pass for codex fixture with complete payload."
  exit 1
fi

if ! printf '%s\n' "$output_codex_pass" | grep -Fq "PASS: codex binary -> usr/bin/codex"; then
  printf '%s\n' "$output_codex_pass"
  echo "FAIL: codex binary payload check missing."
  exit 1
fi

if ! printf '%s\n' "$output_codex_pass" | grep -Fq -- "- PASS"; then
  printf '%s\n' "$output_codex_pass"
  echo "FAIL: codex complete payload fixture should PASS."
  exit 1
fi

create_codex_fixture "no" "yes"
cat > "$codex_log_file" <<EOF
Slackware package ${codex_pkg_file} created.
EOF

if output_codex_payload_fail="$(bash "$validator" "$codex_pkg_dir")"; then
  printf '%s\n' "$output_codex_payload_fail"
  echo "FAIL: validator should fail when codex payload is missing/empty."
  exit 1
fi

if ! printf '%s\n' "$output_codex_payload_fail" | grep -Fq "FAIL: codex binary -> usr/bin/codex"; then
  printf '%s\n' "$output_codex_payload_fail"
  echo "FAIL: missing codex binary was not reported as FAIL."
  exit 1
fi

if ! printf '%s\n' "$output_codex_payload_fail" | grep -Fq "FAIL: codex fish completion -> usr/share/fish/vendor_completions.d/codex.fish"; then
  printf '%s\n' "$output_codex_payload_fail"
  echo "FAIL: empty codex fish completion was not reported as FAIL."
  exit 1
fi

create_codex_fixture "yes" "no"
cat > "$codex_log_file" <<EOF
install: cannot stat 'target/release/codex': No such file or directory
Slackware package ${codex_pkg_file} created.
EOF

if output_codex_log_fail="$(bash "$validator" "$codex_pkg_dir")"; then
  printf '%s\n' "$output_codex_log_fail"
  echo "FAIL: validator should fail on cannot-stat install errors even with success marker."
  exit 1
fi

if ! printf '%s\n' "$output_codex_log_fail" | grep -Fq "Hard-failure hits:"; then
  printf '%s\n' "$output_codex_log_fail"
  echo "FAIL: cannot-stat regression should report hard-failure hits."
  exit 1
fi

if ! printf '%s\n' "$output_codex_log_fail" | grep -Fq "cannot stat"; then
  printf '%s\n' "$output_codex_log_fail"
  echo "FAIL: cannot-stat regression did not include matching log evidence."
  exit 1
fi

echo "PASS: firmware-installer and codex regression fixtures validate expected behavior."
