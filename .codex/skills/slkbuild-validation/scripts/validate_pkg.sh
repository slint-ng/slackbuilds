#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  validate_pkg.sh <pkg-path>

Examples:
  validate_pkg.sh k/sof-firmware
  validate_pkg.sh /home/alice/slkbuilds/k/sof-firmware
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 1 ]]; then
  usage
  exit 2
fi

input_path="$1"
mount_root="$HOME/slkbuilds"

if [[ "$input_path" = /* ]]; then
  pkgdir="${input_path%/}"
else
  pkgdir="${mount_root}/${input_path%/}"
fi

if [[ ! -d "$pkgdir" ]]; then
  echo "Artifacts"
  echo "- Package directory: $pkgdir"
  echo "- ERROR: package directory does not exist."
  echo
  echo "Verdict"
  echo "- FAIL"
  echo
  echo "Next Action"
  echo "- Provide a valid package directory under ~/slkbuilds."
  exit 1
fi

latest_file() {
  local dir="$1"
  local pattern="$2"
  find "$dir" -maxdepth 1 -type f -name "$pattern" -printf '%T@ %p\n' 2>/dev/null \
    | sort -nr \
    | head -n 1 \
    | cut -d' ' -f2-
}

log_file="$(latest_file "$pkgdir" 'build-*.log')"
txz_file="$(latest_file "$pkgdir" '*.txz')"
md5_file=""
expected_md5=""

fail_reasons=()
hard_hits_filtered=""
hard_hits_benign=""
has_success_marker="no"

if [[ -z "$log_file" ]]; then
  fail_reasons+=("Missing build log (build-*.log).")
fi

if [[ -z "$txz_file" ]]; then
  fail_reasons+=("Missing package artifact (*.txz).")
else
  expected_md5="${txz_file%.txz}.md5"
  if [[ -f "$expected_md5" ]]; then
    md5_file="$expected_md5"
  else
    md5_file="$(latest_file "$pkgdir" '*.md5')"
    fail_reasons+=("Missing matching md5 file for $(basename "$txz_file").")
  fi
fi

if [[ -n "$log_file" ]]; then
  hard_hits="$(rg -n -i 'build\(\) failed|cannot open input file|no such file|fatal error|\bfatal:|error:' "$log_file" || true)"
  if [[ -n "$hard_hits" ]]; then
    benign_re="rmdir: failed to remove 'usr/doc[^']*': No such file or directory"
    hard_hits_benign="$(printf '%s\n' "$hard_hits" | rg -i "$benign_re" || true)"
    hard_hits_filtered="$(printf '%s\n' "$hard_hits" | rg -v -i "$benign_re" || true)"
    if [[ -n "$hard_hits_filtered" ]]; then
      fail_reasons+=("Hard failure markers found in build log.")
    fi
  fi

  if rg -q 'Slackware package .* created\.' "$log_file" || rg -q 'Package has been built\.' "$log_file"; then
    has_success_marker="yes"
  else
    fail_reasons+=("Success marker missing from build log.")
  fi
fi

tmp_tar_index=""
pkgname_dir="$(basename "$pkgdir")"
parsed_pkgname="$pkgname_dir"
pkgver=""
payload_checks=()

add_payload_check() {
  local path="$1"
  local label="$2"
  if grep -Fxq "$path" "$tmp_tar_index"; then
    payload_checks+=("PASS: $label -> $path")
  else
    payload_checks+=("FAIL: $label -> $path")
    fail_reasons+=("Missing payload path: $path")
  fi
}

if [[ -n "$txz_file" ]]; then
  tmp_tar_index="$(mktemp)"
  trap '[[ -n "$tmp_tar_index" && -f "$tmp_tar_index" ]] && rm -f "$tmp_tar_index"' EXIT
  tar -tf "$txz_file" >"$tmp_tar_index"

  txz_base="$(basename "$txz_file" .txz)"
  txz_rel="${txz_base##*-}"
  txz_no_rel="${txz_base%-"${txz_rel}"}"
  txz_arch="${txz_no_rel##*-}"
  txz_name_ver="${txz_base%-"${txz_arch}"-"${txz_rel}"}"

  if [[ "$txz_name_ver" == "$txz_base" ]]; then
    fail_reasons+=("Could not parse package version from txz name: ${txz_base}.txz")
  elif [[ "$txz_name_ver" == "${pkgname_dir}-"* ]]; then
    parsed_pkgname="$pkgname_dir"
    pkgver="${txz_name_ver#"${pkgname_dir}"-}"
  elif [[ "$txz_name_ver" == *-* ]]; then
    parsed_pkgname="${txz_name_ver%-*}"
    pkgver="${txz_name_ver##*-}"
  else
    fail_reasons+=("Could not parse package name/version from txz name: ${txz_base}.txz")
  fi

  add_payload_check "install/slack-desc" "slack-desc present"
  if [[ -n "$pkgver" ]]; then
    add_payload_check "usr/src/${parsed_pkgname}-${pkgver}/SLKBUILD" "packaged SLKBUILD present"
  fi

  case "$parsed_pkgname" in
    amd-microcode)
      add_payload_check "boot/amd-ucode.img" "amd microcode earlyfw image"
      add_payload_check "usr/doc/amd-microcode-${pkgver}/README.Debian" "amd microcode docs"
      ;;
    intel-microcode)
      add_payload_check "boot/intel-ucode.img" "intel microcode earlyfw image"
      add_payload_check "lib/firmware/intel-ucode/" "intel microcode tree"
      ;;
    dkms)
      add_payload_check "usr/sbin/dkms" "dkms binary"
      add_payload_check "usr/lib/dkms/" "dkms runtime dir"
      ;;
    iucode_tool)
      add_payload_check "usr/sbin/iucode_tool" "iucode_tool binary"
      ;;
    sof-firmware)
      add_payload_check "lib/firmware/intel/sof/" "SOF firmware tree"
      add_payload_check "lib/firmware/intel/sof-tplg/" "SOF topology tree"
      ;;
    b43-firmware)
      add_payload_check "lib/firmware/b43/" "b43 firmware tree"
      ;;
    kernel-firmware-installer|firmware-installer)
      add_payload_check "linux-firmware/WHENCE" "firmware metadata bundle"
      add_payload_check "lib/firmware/" "installer firmware payload"
      if [[ "$parsed_pkgname" == "firmware-installer" ]]; then
        add_payload_check "usr/doc/firmware-installer-${pkgver}/WHENCE.linux-firmware" "installer docs"
      else
        add_payload_check "usr/doc/kernel-firmware-${pkgver}/WHENCE.linux-firmware" "installer docs"
      fi
      ;;
    zd1211-firmware)
      add_payload_check "lib/firmware/zd1211/" "zd1211 firmware tree"
      ;;
  esac
fi

if [[ ${#fail_reasons[@]} -eq 0 ]]; then
  verdict="PASS"
else
  verdict="FAIL"
fi

echo "Artifacts"
echo "- Package directory: $pkgdir"
echo "- Build log: ${log_file:-MISSING}"
echo "- Package artifact: ${txz_file:-MISSING}"
echo "- MD5 file: ${md5_file:-MISSING}"
echo

echo "Log Health"
echo "- Success marker present: $has_success_marker"
if [[ -n "$hard_hits_filtered" ]]; then
  echo "- Hard-failure hits:"
  printf '%s\n' "$hard_hits_filtered" | sed 's/^/  /'
else
  echo "- Hard-failure hits: none"
fi
if [[ -n "$hard_hits_benign" ]]; then
  echo "- Benign hits ignored:"
  printf '%s\n' "$hard_hits_benign" | sed 's/^/  /'
fi
echo

echo "Payload Checks"
if [[ ${#payload_checks[@]} -eq 0 ]]; then
  echo "- Not run (missing package artifact)."
else
  for check in "${payload_checks[@]}"; do
    echo "- $check"
  done
fi
echo

echo "Verdict"
echo "- $verdict"
echo

echo "Next Action"
if [[ "$verdict" == "PASS" ]]; then
  echo "- None."
  exit 0
fi

echo "- First failing reason: ${fail_reasons[0]}"
if [[ -n "$hard_hits_filtered" ]]; then
  first_hit="$(printf '%s\n' "$hard_hits_filtered" | head -n 1)"
  echo "- Inspect and fix: $first_hit"
elif [[ -z "$txz_file" ]]; then
  echo "- Re-run slkbuild and ensure a .txz is produced."
else
  echo "- Fix the issue above, then rebuild and re-run validation."
fi

exit 1
