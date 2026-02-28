#!/usr/bin/env bash
set -euo pipefail

script_path="${BASH_SOURCE[0]}"
script_dir="${script_path%/*}"
if [[ "$script_dir" == "$script_path" ]]; then
  script_dir="."
fi
script_dir="$(cd "$script_dir" && pwd)"
references_dir="${script_dir}/../references"
default_slapt_getrc="/etc/slapt-get/slapt-getrc"
default_manifest_allowlist="${references_dir}/manifest-allowlist.txt"

usage() {
  cat <<'EOF'
Usage:
  validate_pkg.sh [--require-baseline] [--baseline <package>] [--slapt-getrc <path>] <pkg-path>

Examples:
  validate_pkg.sh k/sof-firmware
  validate_pkg.sh --require-baseline a/dcron
  validate_pkg.sh --baseline /tmp/dcron-4.5-x86_64-1.txz a/dcron
  validate_pkg.sh /home/sektor/projects/slackbuilds/k/sof-firmware
EOF
}

require_baseline="no"
baseline_arg=""
slapt_getrc="${SLKBUILD_VALIDATION_SLAPT_GETRC:-$default_slapt_getrc}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --require-baseline)
      require_baseline="yes"
      shift
      ;;
    --baseline)
      if [[ $# -lt 2 ]]; then
        usage
        exit 2
      fi
      baseline_arg="$2"
      shift 2
      ;;
    --slapt-getrc)
      if [[ $# -lt 2 ]]; then
        usage
        exit 2
      fi
      slapt_getrc="$2"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -*)
      usage
      exit 2
      ;;
    *)
      break
      ;;
  esac
done

if [[ $# -ne 1 ]]; then
  usage
  exit 2
fi

input_path="$1"
validation_root="/home/sektor/projects/slackbuilds"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

if [[ "$input_path" = /* ]]; then
  pkgdir="${input_path%/}"
else
  pkgdir="${validation_root}/${input_path%/}"
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
  echo "- Provide a valid package directory under ${validation_root}."
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

txz_file="$(latest_file "$pkgdir" '*.txz')"
pkgname_dir="$(basename "$pkgdir")"
parsed_pkgname="$pkgname_dir"
pkgver=""
txz_base=""
txz_arch=""
log_file=""
log_selection_reason="missing"
md5_file=""
expected_md5=""
baseline_pkg=""
baseline_source="not-run"
baseline_note="not-run"
manifest_status="not-run"
manifest_diff_mode="not-run"
pkgdiff_excerpt=""
manifest_allowed_count=0
manifest_unexpected_additions=""
manifest_unexpected_removals=""
manifest_allow_add_patterns=()
manifest_allow_remove_patterns=()
workingdir="${SLKBUILD_VALIDATION_WORKINGDIR:-}"
manifest_allowlist_files=("$default_manifest_allowlist")
tmp_tar_index="${tmpdir}/package-manifest.txt"
tmp_tar_listing="${tmpdir}/package-listing.txt"
tmp_baseline_index="${tmpdir}/baseline-manifest.txt"
tmp_pkgdiff_output="${tmpdir}/pkgdiff-output.txt"

fail_reasons=()
hard_hits_actionable=""
hard_hits_soft=""
hard_hits_benign=""
has_success_marker="no"
use_rg="no"

if command -v rg >/dev/null 2>&1; then
  use_rg="yes"
fi

search_ci_with_lineno() {
  local pattern="$1"
  local file="$2"
  if [[ "$use_rg" == "yes" ]]; then
    rg -n -i "$pattern" "$file" || true
  else
    grep -n -i -E "$pattern" "$file" || true
  fi
}

filter_ci() {
  local pattern="$1"
  if [[ "$use_rg" == "yes" ]]; then
    rg -i "$pattern" || true
  else
    grep -i -E "$pattern" || true
  fi
}

filter_ci_invert() {
  local pattern="$1"
  if [[ "$use_rg" == "yes" ]]; then
    rg -v -i "$pattern" || true
  else
    grep -v -i -E "$pattern" || true
  fi
}

has_log_marker() {
  local pattern="$1"
  local file="$2"
  if [[ "$use_rg" == "yes" ]]; then
    rg -q "$pattern" "$file"
  else
    grep -q -E "$pattern" "$file"
  fi
}

select_log_file() {
  local dir="$1"
  local txz="$2"
  local parsed_name="$3"
  local parsed_ver="$4"
  local candidate=""
  local txz_base_local=""

  if [[ -n "$txz" ]]; then
    txz_base_local="$(basename "$txz" .txz)"
    candidate="$dir/build-${txz_base_local}.log"
    if [[ -f "$candidate" ]]; then
      printf '%s|%s\n' "$candidate" "artifact-name"
      return
    fi

    if [[ -n "$parsed_name" && -n "$parsed_ver" ]]; then
      candidate="$(latest_file "$dir" "build-${parsed_name}-${parsed_ver}-*.log")"
      if [[ -n "$candidate" ]]; then
        printf '%s|%s\n' "$candidate" "pkgver-prefix"
        return
      fi
    fi

    if [[ -n "$parsed_name" ]]; then
      candidate="$dir/build-${parsed_name}.log"
      if [[ -f "$candidate" ]]; then
        printf '%s|%s\n' "$candidate" "pkgname"
        return
      fi
    fi
  fi

  candidate="$(latest_file "$dir" 'build-*.log')"
  if [[ -n "$candidate" ]]; then
    printf '%s|%s\n' "$candidate" "latest"
  else
    printf '|%s\n' "missing"
  fi
}

fetch_to_path() {
  local source="$1"
  local dest="$2"

  case "$source" in
    file://*)
      cp -f "${source#file://}" "$dest"
      ;;
    *)
      if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$source" -o "$dest"
      elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$dest" "$source"
      else
        return 1
      fi
      ;;
  esac
}

parse_slapt_getrc() {
  local config_path="$1"
  local line=""
  local source=""

  slapt_sources=()

  if [[ ! -f "$config_path" ]]; then
    return
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "${line:0:1}" == "#" ]] && continue

    case "$line" in
      WORKINGDIR=*)
        if [[ -z "${SLKBUILD_VALIDATION_WORKINGDIR:-}" ]]; then
          workingdir="${line#WORKINGDIR=}"
        fi
        ;;
      SOURCE=*)
        source="${line#SOURCE=}"
        source="${source%:*}"
        slapt_sources+=("$source")
        ;;
    esac
  done <"$config_path"
}

find_cached_baseline() {
  local dir="$1"
  local candidate=""

  [[ -z "$dir" || ! -d "$dir" ]] && return 1

  candidate="$(
    find "$dir" -type f -printf '%T@ %p\n' 2>/dev/null \
      | sort -nr \
      | while read -r _ts path; do
          case "$(basename "$path")" in
            "${parsed_pkgname}-${pkgver}-${txz_arch}-"*.txz|\
            "${parsed_pkgname}-${pkgver}-${txz_arch}-"*.tgz|\
            "${parsed_pkgname}-${pkgver}-${txz_arch}-"*.tlz|\
            "${parsed_pkgname}-${pkgver}-${txz_arch}-"*.tbz|\
            "${parsed_pkgname}-${pkgver}-${txz_arch}-"*.tbr)
              printf '%s\n' "$path"
              break
              ;;
          esac
        done
  )"

  [[ -n "$candidate" ]] || return 1
  baseline_pkg="$candidate"
  baseline_source="cache"
  baseline_note="matched cache under ${dir}"
  return 0
}

find_baseline_in_source() {
  local source="$1"
  local source_id="$2"
  local packages_txt="${tmpdir}/packages-${source_id}.txt"
  local packages_url="${source%/}/PACKAGES.TXT"
  local -a match=()
  local location=""
  local pkgfile=""
  local baseline_url=""

  fetch_to_path "$packages_url" "$packages_txt" || return 1

  mapfile -t match < <(
    awk -v pkg="$parsed_pkgname" -v ver="$pkgver" -v arch="$txz_arch" '
      function maybe_emit() {
        if (name == "" || location == "") {
          return
        }
        pattern = "^" pkg "-" ver "-" arch "-[^[:space:]]+\\.(txz|tgz|tlz|tbz|tbr)$"
        if (name ~ pattern) {
          gsub(/^\.\//, "", location)
          print location
          print name
          exit
        }
      }
      /^PACKAGE NAME:/ { maybe_emit(); name = $3; location = ""; next }
      /^PACKAGE LOCATION:/ { location = $3; next }
      /^$/ { maybe_emit(); name = ""; location = ""; next }
      END { maybe_emit() }
    ' "$packages_txt"
  )

  [[ ${#match[@]} -ge 2 ]] || return 1

  location="${match[0]}"
  pkgfile="${match[1]}"

  if [[ -n "$location" && "$location" != "." ]]; then
    baseline_url="${source%/}/${location%/}/${pkgfile}"
  else
    baseline_url="${source%/}/${pkgfile}"
  fi

  baseline_pkg="${tmpdir}/${pkgfile}"
  fetch_to_path "$baseline_url" "$baseline_pkg" || return 1
  baseline_source="download"
  baseline_note="fetched from ${source}"
  return 0
}

resolve_baseline_package() {
  local provided="$1"
  local source_index=0

  if [[ -n "$provided" ]]; then
    case "$provided" in
      file://*|http://*|https://*)
        baseline_pkg="${tmpdir}/$(basename "$provided")"
        if fetch_to_path "$provided" "$baseline_pkg"; then
          baseline_source="provided"
          baseline_note="fetched from explicit baseline source"
          return 0
        fi
        baseline_pkg=""
        return 1
        ;;
      *)
        if [[ -f "$provided" ]]; then
          baseline_pkg="$provided"
          baseline_source="provided"
          baseline_note="explicit baseline path"
          return 0
        fi
        return 1
        ;;
    esac
  fi

  parse_slapt_getrc "$slapt_getrc"

  if find_cached_baseline "$workingdir"; then
    return 0
  fi

  for source in "${slapt_sources[@]:-}"; do
    source_index=$((source_index + 1))
    if find_baseline_in_source "$source" "$source_index"; then
      return 0
    fi
  done

  baseline_pkg=""
  return 1
}

load_manifest_allowlist() {
  local allowlist_file=""
  local package_allowlist="${references_dir}/manifest-allowlist.d/${parsed_pkgname}.txt"
  local line=""
  local prefix=""

  manifest_allow_add_patterns=()
  manifest_allow_remove_patterns=()
  manifest_allowlist_files=("$default_manifest_allowlist")

  if [[ -f "$package_allowlist" ]]; then
    manifest_allowlist_files+=("$package_allowlist")
  fi
  if [[ -f "${pkgdir}/manifest-allowlist.txt" ]]; then
    manifest_allowlist_files+=("${pkgdir}/manifest-allowlist.txt")
  fi

  for allowlist_file in "${manifest_allowlist_files[@]}"; do
    [[ -f "$allowlist_file" ]] || continue
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -z "$line" || "${line:0:1}" == "#" ]] && continue
      line="${line//@PKGNAME@/$parsed_pkgname}"
      line="${line//@PKGVER@/$pkgver}"
      prefix="${line:0:1}"
      case "$prefix" in
        +)
          manifest_allow_add_patterns+=("${line:1}")
          ;;
        -)
          manifest_allow_remove_patterns+=("${line:1}")
          ;;
        *)
          manifest_allow_add_patterns+=("$line")
          ;;
      esac
    done <"$allowlist_file"
  done
}

manifest_path_allowed() {
  local mode="$1"
  local path="$2"
  local pattern=""
  local -a patterns=()

  if [[ "$mode" == "add" ]]; then
    patterns=("${manifest_allow_add_patterns[@]}")
    path="$2"
  else
    patterns=("${manifest_allow_remove_patterns[@]}")
    path="$2"
  fi

  for pattern in "${patterns[@]}"; do
    if [[ "$path" =~ $pattern ]]; then
      return 0
    fi
  done
  return 1
}

run_manifest_diff() {
  local added_file="${tmpdir}/manifest-added.txt"
  local removed_file="${tmpdir}/manifest-removed.txt"
  local path=""

  if [[ -z "$txz_file" ]]; then
    manifest_status="not-run"
    baseline_note="package artifact missing"
    return
  fi

  if [[ "$require_baseline" != "yes" && -z "$baseline_arg" ]]; then
    manifest_status="not-run"
    baseline_note="baseline diff not requested"
    return
  fi

  if ! resolve_baseline_package "$baseline_arg"; then
    manifest_status="missing-baseline"
    baseline_note="no baseline package found for ${parsed_pkgname}-${pkgver}-${txz_arch}"
    if [[ "$require_baseline" == "yes" ]]; then
      fail_reasons+=("Baseline package unavailable for manifest diff.")
    fi
    return
  fi

  load_manifest_allowlist

  tar -tf "$baseline_pkg" | sed 's#^\./##' | sort -u >"$tmp_baseline_index"
  tar -tf "$txz_file" | sed 's#^\./##' | sort -u >"$tmp_tar_index"

  if command -v pkgdiff >/dev/null 2>&1; then
    pkgdiff -a "$baseline_pkg" "$txz_file" >"$tmp_pkgdiff_output" 2>&1 || true
    manifest_diff_mode="pkgdiff -a"
  else
    diff -u "$tmp_baseline_index" "$tmp_tar_index" >"$tmp_pkgdiff_output" 2>&1 || true
    manifest_diff_mode="diff -u manifest"
  fi

  comm -13 "$tmp_baseline_index" "$tmp_tar_index" >"$added_file"
  comm -23 "$tmp_baseline_index" "$tmp_tar_index" >"$removed_file"

  while IFS= read -r path || [[ -n "$path" ]]; do
    [[ -z "$path" ]] && continue
    if manifest_path_allowed add "$path"; then
      manifest_allowed_count=$((manifest_allowed_count + 1))
    else
      manifest_unexpected_additions+="${path}"$'\n'
    fi
  done <"$added_file"

  while IFS= read -r path || [[ -n "$path" ]]; do
    [[ -z "$path" ]] && continue
    if manifest_path_allowed remove "$path"; then
      manifest_allowed_count=$((manifest_allowed_count + 1))
    else
      manifest_unexpected_removals+="${path}"$'\n'
    fi
  done <"$removed_file"

  if [[ -n "$manifest_unexpected_additions" || -n "$manifest_unexpected_removals" ]]; then
    manifest_status="fail"
    fail_reasons+=("Manifest diff against baseline package found unexpected changes.")
  else
    manifest_status="pass"
  fi

  if [[ -s "$tmp_pkgdiff_output" ]]; then
    pkgdiff_excerpt="$(sed -n '1,40p' "$tmp_pkgdiff_output")"
  fi
}

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
fi

log_choice="$(select_log_file "$pkgdir" "$txz_file" "$parsed_pkgname" "$pkgver")"
log_file="${log_choice%%|*}"
log_selection_reason="${log_choice#*|}"

if [[ -z "$log_file" ]]; then
  fail_reasons+=("Missing build log (build-*.log).")
fi

if [[ -n "$log_file" ]]; then
  if has_log_marker 'Slackware package .* created\.' "$log_file" \
    || has_log_marker 'Package has been built\.' "$log_file"; then
    has_success_marker="yes"
  else
    fail_reasons+=("Success marker missing from build log.")
  fi

  hard_failure_re='build\(\) failed|cannot open input file|no such file|fatal error|(^|[^[:alnum:]_])fatal:|error:'
  critical_with_success_re='build\(\) failed|cannot open input file|cannot stat|fatal error|(^|[^[:alnum:]_])fatal:|^ERROR:'
  hard_hits="$(search_ci_with_lineno "$hard_failure_re" "$log_file")"
  if [[ -n "$hard_hits" ]]; then
    benign_re="rmdir: failed to remove 'usr/doc[^']*': No such file or directory|collect2: error: ld returned [0-9]+ exit status"
    hard_hits_benign="$(printf '%s\n' "$hard_hits" | filter_ci "$benign_re")"
    hard_hits_non_benign="$(printf '%s\n' "$hard_hits" | filter_ci_invert "$benign_re")"
    if [[ -n "$hard_hits_non_benign" ]]; then
      if [[ "$has_success_marker" == "yes" ]]; then
        hard_hits_actionable="$(printf '%s\n' "$hard_hits_non_benign" | filter_ci "$critical_with_success_re")"
        hard_hits_soft="$(printf '%s\n' "$hard_hits_non_benign" | filter_ci_invert "$critical_with_success_re")"
      else
        hard_hits_actionable="$hard_hits_non_benign"
      fi
    fi
    if [[ -n "$hard_hits_actionable" ]]; then
      fail_reasons+=("Hard failure markers found in build log.")
    fi
  fi
fi

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

lookup_payload_file_size() {
  local path="$1"
  awk -v want="$path" '
    {
      entry = $0
      sub(/^[^ ]+ +[^ ]+ +[0-9]+ +[^ ]+ +[^ ]+ +/, "", entry)
      sub(/^\.\//, "", entry)
      if (entry == want) {
        print $3
        exit
      }
    }
  ' "$tmp_tar_listing"
}

add_payload_nonempty_file_check() {
  local path="$1"
  local label="$2"
  local file_size=""

  if ! grep -Fxq "$path" "$tmp_tar_index"; then
    payload_checks+=("FAIL: $label -> $path")
    fail_reasons+=("Missing payload path: $path")
    return
  fi

  file_size="$(lookup_payload_file_size "$path")"
  if [[ "$file_size" =~ ^[0-9]+$ ]] && [[ "$file_size" -gt 0 ]]; then
    payload_checks+=("PASS: $label -> $path")
  else
    payload_checks+=("FAIL: $label -> $path")
    fail_reasons+=("Empty payload file: $path")
  fi
}

if [[ -n "$txz_file" ]]; then
  tar -tf "$txz_file" | sed 's#^\./##' >"$tmp_tar_index"
  tar -tvf "$txz_file" >"$tmp_tar_listing"

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
      add_payload_check "usr/lib/dkms/dkms_autoinstaller" "dkms autoinstaller helper"
      add_payload_check "usr/lib/dkms/common.postinst" "dkms postinst helper"
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
    kernel)
      add_payload_check "boot/vmlinuz-${pkgver}" "kernel image"
      add_payload_check "lib/modules/${pkgver}/" "kernel modules tree"
      ;;
    kernel-headers)
      add_payload_check "usr/include/" "kernel headers include root"
      add_payload_check "usr/include/asm-x86/" "kernel headers arch include"
      ;;
    kernel-source)
      add_payload_check "usr/src/linux-${pkgver}/" "kernel source tree"
      ;;
    modules-installer)
      add_payload_check "lib/modules/${pkgver}/" "installer modules tree"
      ;;
    kernel-firmware)
      add_payload_check "lib/firmware/" "kernel firmware tree"
      add_payload_check "usr/doc/kernel-firmware-${pkgver}/WHENCE.linux-firmware" "kernel firmware docs"
      ;;
    kernel-firmware-installer)
      add_payload_check "linux-firmware/WHENCE" "firmware metadata bundle"
      add_payload_check "lib/firmware/" "installer firmware payload"
      add_payload_check "usr/doc/kernel-firmware-${pkgver}/WHENCE.linux-firmware" "installer docs"
      ;;
    firmware-installer)
      add_payload_check "lib/firmware/" "installer firmware payload"
      add_payload_check "usr/doc/firmware-installer-${pkgver}/WHENCE.linux-firmware" "installer docs"
      ;;
    zd1211-firmware)
      add_payload_check "lib/firmware/zd1211/" "zd1211 firmware tree"
      ;;
    codex)
      add_payload_nonempty_file_check "usr/bin/codex" "codex binary"
      add_payload_nonempty_file_check "usr/share/bash-completion/completions/codex" "codex bash completion"
      add_payload_nonempty_file_check "usr/share/zsh/site-functions/_codex" "codex zsh completion"
      add_payload_nonempty_file_check "usr/share/fish/vendor_completions.d/codex.fish" "codex fish completion"
      ;;
  esac
fi

run_manifest_diff

if [[ ${#fail_reasons[@]} -eq 0 ]]; then
  verdict="PASS"
else
  verdict="FAIL"
fi

echo "Artifacts"
echo "- Package directory: $pkgdir"
echo "- Build log: ${log_file:-MISSING}"
echo "- Log selection: $log_selection_reason"
echo "- Package artifact: ${txz_file:-MISSING}"
echo "- MD5 file: ${md5_file:-MISSING}"
echo

echo "Log Health"
echo "- Success marker present: $has_success_marker"
if [[ -n "$hard_hits_actionable" ]]; then
  echo "- Hard-failure hits:"
  printf '%s\n' "$hard_hits_actionable" | sed 's/^/  /'
else
  echo "- Hard-failure hits: none"
fi
if [[ -n "$hard_hits_benign" ]]; then
  echo "- Benign hits ignored:"
  printf '%s\n' "$hard_hits_benign" | sed 's/^/  /'
fi
if [[ -n "$hard_hits_soft" ]]; then
  echo "- Non-fatal error-pattern hits (success marker present):"
  printf '%s\n' "$hard_hits_soft" | sed 's/^/  /'
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

echo "Manifest Diff"
echo "- Baseline requirement: $require_baseline"
echo "- Baseline package: ${baseline_pkg:-NOT FOUND}"
echo "- Baseline source: $baseline_source"
echo "- Baseline note: $baseline_note"
echo "- Diff mode: $manifest_diff_mode"
case "$manifest_status" in
  pass)
    echo "- Status: PASS"
    echo "- Allowed manifest deltas ignored: $manifest_allowed_count"
    echo "- Unexpected additions: none"
    echo "- Unexpected removals: none"
    ;;
  fail)
    echo "- Status: FAIL"
    echo "- Allowed manifest deltas ignored: $manifest_allowed_count"
    if [[ -n "$manifest_unexpected_additions" ]]; then
      echo "- Unexpected additions:"
      printf '%s' "$manifest_unexpected_additions" | sed 's/^/  /'
    else
      echo "- Unexpected additions: none"
    fi
    if [[ -n "$manifest_unexpected_removals" ]]; then
      echo "- Unexpected removals:"
      printf '%s' "$manifest_unexpected_removals" | sed 's/^/  /'
    else
      echo "- Unexpected removals: none"
    fi
    ;;
  missing-baseline)
    echo "- Status: NOT RUN"
    echo "- Reason: baseline package unavailable"
    ;;
  *)
    echo "- Status: NOT RUN"
    echo "- Reason: $baseline_note"
    ;;
esac
if [[ -n "$pkgdiff_excerpt" ]]; then
  echo "- Diff excerpt:"
  printf '%s\n' "$pkgdiff_excerpt" | sed 's/^/  /'
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
if [[ -n "$hard_hits_actionable" ]]; then
  first_hit="$(printf '%s\n' "$hard_hits_actionable" | head -n 1)"
  echo "- Inspect and fix: $first_hit"
elif [[ -z "$txz_file" ]]; then
  echo "- Re-run slkbuild and ensure a .txz is produced."
else
  echo "- Fix the issue above, then rebuild and re-run validation."
fi

exit 1
