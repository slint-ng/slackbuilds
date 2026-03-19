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

write_dep_file() {
  local dep_path="$1"
  cat > "$dep_path" <<'EOF'
aaa_libraries|gcc
EOF
}

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
write_dep_file "${pkg_file%.txz}.dep"

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

if ! printf '%s\n' "$output" | grep -Fq "Depfile status: present"; then
  printf '%s\n' "$output"
  echo "FAIL: validator did not report the matching depfile."
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
  write_dep_file "${codex_pkg_file%.txz}.dep"
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

symlink_pkg_name="symlink-demo"
symlink_pkg_ver="1.0"
symlink_pkg_arch="x86_64"
symlink_pkg_rel="1slint"
symlink_pkg_dir="${fixture_root}/l/${symlink_pkg_name}"
symlink_stage_dir="${symlink_pkg_dir}/stage"
symlink_pkg_file="${symlink_pkg_dir}/${symlink_pkg_name}-${symlink_pkg_ver}-${symlink_pkg_arch}-${symlink_pkg_rel}.txz"
symlink_md5_file="${symlink_pkg_file%.txz}.md5"
symlink_log_file="${symlink_pkg_dir}/build-${symlink_pkg_name}-${symlink_pkg_ver}-${symlink_pkg_arch}-${symlink_pkg_rel}.log"

rm -rf "$symlink_pkg_dir"
mkdir -p "${symlink_stage_dir}/install"
mkdir -p "${symlink_stage_dir}/usr/src/${symlink_pkg_name}-${symlink_pkg_ver}"
mkdir -p "${symlink_stage_dir}/usr/lib64"
mkdir -p "$symlink_pkg_dir"

cat > "${symlink_stage_dir}/install/slack-desc" <<'EOF'
symlink-demo: symlink-demo (doinst symlink fixture)
EOF

cat > "${symlink_stage_dir}/install/doinst.sh" <<'EOF'
( cd usr/lib64 ; ln -sf libsymlink-demo.so.1.2.3 libsymlink-demo.so.1 )
( cd usr/lib64 ; ln -sf libsymlink-demo.so.1 libsymlink-demo.so )
EOF

cat > "${symlink_stage_dir}/usr/src/${symlink_pkg_name}-${symlink_pkg_ver}/SLKBUILD" <<'EOF'
pkgname=symlink-demo
EOF

cat > "${symlink_stage_dir}/usr/lib64/libsymlink-demo.so.1.2.3" <<'EOF'
fake elf payload
EOF

tar -C "$symlink_stage_dir" -cJf "$symlink_pkg_file" install usr
(cd "$symlink_pkg_dir" && md5sum "$(basename "$symlink_pkg_file")" > "$(basename "$symlink_md5_file")")
write_dep_file "${symlink_pkg_file%.txz}.dep"

cat > "$symlink_log_file" <<EOF
Slackware package ${symlink_pkg_file} created.
EOF

if ! output_symlink_note="$(bash "$validator" "$symlink_pkg_dir")"; then
  printf '%s\n' "$output_symlink_note"
  echo "FAIL: validator should pass for doinst symlink fixture."
  exit 1
fi

if ! printf '%s\n' "$output_symlink_note" | grep -Fq "Post-install library symlinks recreated by doinst.sh:"; then
  printf '%s\n' "$output_symlink_note"
  echo "FAIL: validator did not report the doinst symlink note header."
  exit 1
fi

if ! printf '%s\n' "$output_symlink_note" | grep -Fq "usr/lib64/libsymlink-demo.so.1 -> libsymlink-demo.so.1.2.3"; then
  printf '%s\n' "$output_symlink_note"
  echo "FAIL: validator did not explain the SONAME symlink recreated by doinst.sh."
  exit 1
fi

if ! printf '%s\n' "$output_symlink_note" | grep -Fq "raw txz scans can miss these SONAME symlinks before installation"; then
  printf '%s\n' "$output_symlink_note"
  echo "FAIL: validator did not explain why the doinst symlink note matters."
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

baseline_repo_root="${tmpdir}/baseline-repo"
baseline_slapt_getrc="${tmpdir}/baseline-slapt-getrc"
mkdir -p "$baseline_repo_root" "${tmpdir}/baseline-cache"

create_packages_txt() {
  local repo_dir="$1"
  local package_file="$2"

  cat > "${repo_dir}/PACKAGES.TXT" <<EOF
PACKAGE NAME:  $(basename "$package_file")
PACKAGE LOCATION:  .

EOF
}

cat > "$baseline_slapt_getrc" <<EOF
WORKINGDIR=${tmpdir}/baseline-cache
SOURCE=file://${baseline_repo_root}:PREFERRED
EOF

baseline_stage_dir="${tmpdir}/baseline-stage"
rm -rf "$baseline_stage_dir"
mkdir -p "${baseline_stage_dir}/install"
mkdir -p "${baseline_stage_dir}/usr/doc/${pkg_name}-${pkgver}"
mkdir -p "${baseline_stage_dir}/lib/firmware"

cat > "${baseline_stage_dir}/install/slack-desc" <<'EOF'
firmware-installer: firmware-installer (baseline fixture)
EOF

cat > "${baseline_stage_dir}/usr/doc/${pkg_name}-${pkgver}/WHENCE.linux-firmware" <<'EOF'
firmware metadata
EOF

baseline_pkg_file="${baseline_repo_root}/${pkg_name}-${pkgver}-${pkg_arch}-${pkg_rel}.txz"
tar -C "$baseline_stage_dir" -cJf "$baseline_pkg_file" install usr lib
create_packages_txt "$baseline_repo_root" "$baseline_pkg_file"

if ! output_manifest_pass="$(SLKBUILD_VALIDATION_SLAPT_GETRC="$baseline_slapt_getrc" bash "$validator" --require-baseline "$pkg_dir")"; then
  printf '%s\n' "$output_manifest_pass"
  echo "FAIL: validator should pass manifest diff when only allowed usr/src additions differ."
  exit 1
fi

if ! printf '%s\n' "$output_manifest_pass" | grep -Fq "Baseline source: download"; then
  printf '%s\n' "$output_manifest_pass"
  echo "FAIL: validator did not report downloaded baseline source."
  exit 1
fi

if ! printf '%s\n' "$output_manifest_pass" | grep -Fq "Status: PASS"; then
  printf '%s\n' "$output_manifest_pass"
  echo "FAIL: manifest diff pass case did not report PASS."
  exit 1
fi

if ! printf '%s\n' "$output_manifest_pass" | grep -Fq "Allowed manifest deltas ignored: 3"; then
  printf '%s\n' "$output_manifest_pass"
  echo "FAIL: manifest diff pass case did not ignore the expected usr/src additions."
  exit 1
fi

manifest_pkg_name="manifest-demo"
manifest_pkg_ver="1.0"
manifest_pkg_arch="x86_64"
manifest_pkg_rel="1slint"
manifest_pkg_dir="${fixture_root}/n/${manifest_pkg_name}"
manifest_stage_dir="${manifest_pkg_dir}/stage"
manifest_pkg_file="${manifest_pkg_dir}/${manifest_pkg_name}-${manifest_pkg_ver}-${manifest_pkg_arch}-${manifest_pkg_rel}.txz"
manifest_md5_file="${manifest_pkg_file%.txz}.md5"
manifest_log_file="${manifest_pkg_dir}/build-${manifest_pkg_name}-${manifest_pkg_ver}-${manifest_pkg_arch}-${manifest_pkg_rel}.log"
manifest_baseline_stage="${tmpdir}/manifest-baseline-stage"
manifest_baseline_pkg="${baseline_repo_root}/${manifest_pkg_name}-${manifest_pkg_ver}-${manifest_pkg_arch}-${manifest_pkg_rel}.txz"

rm -rf "$manifest_pkg_dir" "$manifest_stage_dir" "$manifest_baseline_stage"
mkdir -p "${manifest_stage_dir}/install"
mkdir -p "${manifest_stage_dir}/usr/src/${manifest_pkg_name}-${manifest_pkg_ver}"
mkdir -p "${manifest_stage_dir}/usr/bin"
mkdir -p "${manifest_pkg_dir}"

cat > "${manifest_stage_dir}/install/slack-desc" <<'EOF'
manifest-demo: manifest-demo (manifest diff fixture)
EOF

cat > "${manifest_stage_dir}/usr/src/${manifest_pkg_name}-${manifest_pkg_ver}/SLKBUILD" <<'EOF'
pkgname=manifest-demo
EOF

cat > "${manifest_stage_dir}/usr/bin/manifest-demo" <<'EOF'
#!/bin/sh
echo manifest-demo
EOF
chmod 755 "${manifest_stage_dir}/usr/bin/manifest-demo"

tar -C "$manifest_stage_dir" -cJf "$manifest_pkg_file" install usr
(cd "$manifest_pkg_dir" && md5sum "$(basename "$manifest_pkg_file")" > "$(basename "$manifest_md5_file")")
write_dep_file "${manifest_pkg_file%.txz}.dep"

cat > "$manifest_log_file" <<EOF
Slackware package ${manifest_pkg_file} created.
EOF

mkdir -p "${manifest_baseline_stage}/install"
mkdir -p "${manifest_baseline_stage}/usr/bin"
mkdir -p "${manifest_baseline_stage}/usr/share"

cat > "${manifest_baseline_stage}/install/slack-desc" <<'EOF'
manifest-demo: manifest-demo (baseline manifest diff fixture)
EOF

cat > "${manifest_baseline_stage}/usr/bin/manifest-demo" <<'EOF'
#!/bin/sh
echo manifest-demo
EOF
chmod 755 "${manifest_baseline_stage}/usr/bin/manifest-demo"

cat > "${manifest_baseline_stage}/usr/share/legacy.txt" <<'EOF'
legacy payload
EOF

tar -C "$manifest_baseline_stage" -cJf "$manifest_baseline_pkg" install usr
create_packages_txt "$baseline_repo_root" "$manifest_baseline_pkg"

if output_manifest_fail="$(SLKBUILD_VALIDATION_SLAPT_GETRC="$baseline_slapt_getrc" bash "$validator" --require-baseline "$manifest_pkg_dir")"; then
  printf '%s\n' "$output_manifest_fail"
  echo "FAIL: validator should fail manifest diff when baseline files disappear."
  exit 1
fi

if ! printf '%s\n' "$output_manifest_fail" | grep -Fq "Unexpected removals:"; then
  printf '%s\n' "$output_manifest_fail"
  echo "FAIL: manifest diff failure did not report unexpected removals."
  exit 1
fi

if ! printf '%s\n' "$output_manifest_fail" | grep -Fq "usr/share/legacy.txt"; then
  printf '%s\n' "$output_manifest_fail"
  echo "FAIL: manifest diff failure did not include the missing baseline path."
  exit 1
fi

manifest_shift_pkg_name="manifest-shift"
manifest_shift_pkg_ver="1.0"
manifest_shift_pkg_arch="x86_64"
manifest_shift_pkg_rel="1slint"
manifest_shift_pkg_dir="${fixture_root}/n/${manifest_shift_pkg_name}"
manifest_shift_stage_dir="${manifest_shift_pkg_dir}/stage"
manifest_shift_pkg_file="${manifest_shift_pkg_dir}/${manifest_shift_pkg_name}-${manifest_shift_pkg_ver}-${manifest_shift_pkg_arch}-${manifest_shift_pkg_rel}.txz"
manifest_shift_md5_file="${manifest_shift_pkg_file%.txz}.md5"
manifest_shift_log_file="${manifest_shift_pkg_dir}/build-${manifest_shift_pkg_name}-${manifest_shift_pkg_ver}-${manifest_shift_pkg_arch}-${manifest_shift_pkg_rel}.log"
manifest_shift_baseline_stage="${tmpdir}/manifest-shift-baseline-stage"
manifest_shift_baseline_pkg="${baseline_repo_root}/${manifest_shift_pkg_name}-${manifest_shift_pkg_ver}-${manifest_shift_pkg_arch}-${manifest_shift_pkg_rel}.txz"

rm -rf "$manifest_shift_pkg_dir" "$manifest_shift_stage_dir" "$manifest_shift_baseline_stage"
mkdir -p "${manifest_shift_stage_dir}/install"
mkdir -p "${manifest_shift_stage_dir}/usr/src/${manifest_shift_pkg_name}-${manifest_shift_pkg_ver}"
mkdir -p "${manifest_shift_stage_dir}/usr/bin"
mkdir -p "${manifest_shift_stage_dir}/etc/rc.d"
mkdir -p "${manifest_shift_pkg_dir}"

cat > "${manifest_shift_stage_dir}/install/slack-desc" <<'EOF'
manifest-shift: manifest-shift (allowlisted rename fixture)
EOF

cat > "${manifest_shift_stage_dir}/usr/src/${manifest_shift_pkg_name}-${manifest_shift_pkg_ver}/SLKBUILD" <<'EOF'
pkgname=manifest-shift
EOF

cat > "${manifest_shift_stage_dir}/usr/bin/manifest-shift" <<'EOF'
#!/bin/sh
echo manifest-shift
EOF
chmod 755 "${manifest_shift_stage_dir}/usr/bin/manifest-shift"

cat > "${manifest_shift_stage_dir}/etc/rc.d/rc.manifest.new" <<'EOF'
#!/bin/sh
echo shifted
EOF
chmod 755 "${manifest_shift_stage_dir}/etc/rc.d/rc.manifest.new"

cat > "${manifest_shift_pkg_dir}/manifest-allowlist.txt" <<'EOF'
+^etc/rc\.d/rc\.manifest\.new$
-^etc/rc\.d/rc\.manifest$
EOF

tar -C "$manifest_shift_stage_dir" -cJf "$manifest_shift_pkg_file" install usr etc
(cd "$manifest_shift_pkg_dir" && md5sum "$(basename "$manifest_shift_pkg_file")" > "$(basename "$manifest_shift_md5_file")")
write_dep_file "${manifest_shift_pkg_file%.txz}.dep"

cat > "$manifest_shift_log_file" <<EOF
Slackware package ${manifest_shift_pkg_file} created.
EOF

mkdir -p "${manifest_shift_baseline_stage}/install"
mkdir -p "${manifest_shift_baseline_stage}/usr/bin"
mkdir -p "${manifest_shift_baseline_stage}/etc/rc.d"

cat > "${manifest_shift_baseline_stage}/install/slack-desc" <<'EOF'
manifest-shift: manifest-shift (allowlisted rename baseline fixture)
EOF

cat > "${manifest_shift_baseline_stage}/usr/bin/manifest-shift" <<'EOF'
#!/bin/sh
echo manifest-shift
EOF
chmod 755 "${manifest_shift_baseline_stage}/usr/bin/manifest-shift"

cat > "${manifest_shift_baseline_stage}/etc/rc.d/rc.manifest" <<'EOF'
#!/bin/sh
echo shifted
EOF
chmod 755 "${manifest_shift_baseline_stage}/etc/rc.d/rc.manifest"

tar -C "$manifest_shift_baseline_stage" -cJf "$manifest_shift_baseline_pkg" install usr etc
create_packages_txt "$baseline_repo_root" "$manifest_shift_baseline_pkg"

if ! output_manifest_shift_pass="$(SLKBUILD_VALIDATION_SLAPT_GETRC="$baseline_slapt_getrc" bash "$validator" --require-baseline "$manifest_shift_pkg_dir")"; then
  printf '%s\n' "$output_manifest_shift_pass"
  echo "FAIL: validator should pass allowlisted manifest replacements."
  exit 1
fi

if ! printf '%s\n' "$output_manifest_shift_pass" | grep -Fq "Allowed manifest deltas ignored: 5"; then
  printf '%s\n' "$output_manifest_shift_pass"
  echo "FAIL: allowlisted manifest replacement did not count expected ignored deltas."
  exit 1
fi

if ! printf '%s\n' "$output_manifest_shift_pass" | grep -Fq "Status: PASS"; then
  printf '%s\n' "$output_manifest_shift_pass"
  echo "FAIL: allowlisted manifest replacement should pass."
  exit 1
fi

manifest_plus_pkg_name="manifest++"
manifest_plus_pkg_ver="1.0"
manifest_plus_pkg_arch="x86_64"
manifest_plus_pkg_rel="1slint"
manifest_plus_pkg_dir="${fixture_root}/n/${manifest_plus_pkg_name}"
manifest_plus_stage_dir="${manifest_plus_pkg_dir}/stage"
manifest_plus_pkg_file="${manifest_plus_pkg_dir}/${manifest_plus_pkg_name}-${manifest_plus_pkg_ver}-${manifest_plus_pkg_arch}-${manifest_plus_pkg_rel}.txz"
manifest_plus_md5_file="${manifest_plus_pkg_file%.txz}.md5"
manifest_plus_log_file="${manifest_plus_pkg_dir}/build-${manifest_plus_pkg_name}-${manifest_plus_pkg_ver}-${manifest_plus_pkg_arch}-${manifest_plus_pkg_rel}.log"
manifest_plus_baseline_stage="${tmpdir}/manifest-plus-baseline-stage"
manifest_plus_baseline_pkg="${baseline_repo_root}/${manifest_plus_pkg_name}-${manifest_plus_pkg_ver}-${manifest_plus_pkg_arch}-${manifest_plus_pkg_rel}.txz"

rm -rf "$manifest_plus_pkg_dir" "$manifest_plus_stage_dir" "$manifest_plus_baseline_stage"
mkdir -p "${manifest_plus_stage_dir}/install"
mkdir -p "${manifest_plus_stage_dir}/usr/src/${manifest_plus_pkg_name}-${manifest_plus_pkg_ver}"
mkdir -p "${manifest_plus_stage_dir}/usr/bin"
mkdir -p "${manifest_plus_pkg_dir}"

cat > "${manifest_plus_stage_dir}/install/slack-desc" <<'EOF'
manifest++: manifest++ (regex literal manifest fixture)
EOF

cat > "${manifest_plus_stage_dir}/usr/src/${manifest_plus_pkg_name}-${manifest_plus_pkg_ver}/SLKBUILD" <<'EOF'
pkgname=manifest++
EOF

cat > "${manifest_plus_stage_dir}/usr/bin/manifest++" <<'EOF'
#!/bin/sh
echo manifest++
EOF
chmod 755 "${manifest_plus_stage_dir}/usr/bin/manifest++"

tar -C "$manifest_plus_stage_dir" -cJf "$manifest_plus_pkg_file" install usr
(cd "$manifest_plus_pkg_dir" && md5sum "$(basename "$manifest_plus_pkg_file")" > "$(basename "$manifest_plus_md5_file")")
write_dep_file "${manifest_plus_pkg_file%.txz}.dep"

cat > "$manifest_plus_log_file" <<EOF
Slackware package ${manifest_plus_pkg_file} created.
EOF

mkdir -p "${manifest_plus_baseline_stage}/install"
mkdir -p "${manifest_plus_baseline_stage}/usr/bin"

cat > "${manifest_plus_baseline_stage}/install/slack-desc" <<'EOF'
manifest++: manifest++ (regex literal baseline fixture)
EOF

cat > "${manifest_plus_baseline_stage}/usr/bin/manifest++" <<'EOF'
#!/bin/sh
echo manifest++
EOF
chmod 755 "${manifest_plus_baseline_stage}/usr/bin/manifest++"

tar -C "$manifest_plus_baseline_stage" -cJf "$manifest_plus_baseline_pkg" install usr
create_packages_txt "$baseline_repo_root" "$manifest_plus_baseline_pkg"

if ! output_manifest_plus_pass="$(SLKBUILD_VALIDATION_SLAPT_GETRC="$baseline_slapt_getrc" bash "$validator" --require-baseline "$manifest_plus_pkg_dir")"; then
  printf '%s\n' "$output_manifest_plus_pass"
  echo "FAIL: validator should treat plus signs in package names as literal allowlist substitutions."
  exit 1
fi

if ! printf '%s\n' "$output_manifest_plus_pass" | grep -Fq "Allowed manifest deltas ignored: 3"; then
  printf '%s\n' "$output_manifest_plus_pass"
  echo "FAIL: literal package-name allowlist substitution did not ignore the expected usr/src additions."
  exit 1
fi

if ! printf '%s\n' "$output_manifest_plus_pass" | grep -Fq "Status: PASS"; then
  printf '%s\n' "$output_manifest_plus_pass"
  echo "FAIL: literal package-name allowlist substitution should pass."
  exit 1
fi

echo "PASS: firmware-installer and codex regression fixtures validate expected behavior."
