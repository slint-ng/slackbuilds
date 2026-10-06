#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
staging_dir=${STAGING_DIR:-/home/storm/staging}
log_root=${LOG_ROOT:-/tmp/slint-upgrade-builds-$(date +%Y%m%d-%H%M%S)}
do_apply=no
do_build=no
reset_staging=no

usage() {
  cat <<'EOF'
Usage: Maintenance-of-the-repository/prepare-upgrades.sh [options]

Check selected fast-moving Slint packages against upstream release sources.
By default this only reports local and upstream versions.

Options:
      --apply          Update low-risk package metadata before building.
                       Currently applies kernel, kernel-firmware, and yt-dlp.
      --build          Build packages whose local version is older than upstream.
                       Use with --apply to build the newly bumped versions.
      --reset-staging  Empty the staging directory before building.
  -s, --staging DIR    Stage built packages and .dep files in DIR.
      --log-dir DIR    Write build logs in DIR.
  -h, --help           Show this help.

Examples:
  Maintenance-of-the-repository/prepare-upgrades.sh
  Maintenance-of-the-repository/prepare-upgrades.sh --apply
  Maintenance-of-the-repository/prepare-upgrades.sh --apply --build --reset-staging
EOF
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

while (($#)); do
  case "$1" in
    --apply) do_apply=yes ;;
    --build) do_build=yes ;;
    --reset-staging) reset_staging=yes ;;
    -s|--staging)
      shift
      [[ $# -gt 0 ]] || die "--staging requires a directory"
      staging_dir=$1
      ;;
    --log-dir)
      shift
      [[ $# -gt 0 ]] || die "--log-dir requires a directory"
      log_root=$1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done

need awk
need curl
need git
need python3
need sed
need sort

cd "$repo_root"

slk_var() {
  local file=$1
  local name=$2
  awk -F= -v name="$name" '
    $1 ~ "^[[:space:]]*" name "[[:space:]]*$" {
      value=$0
      sub(/^[^=]*=/, "", value)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      gsub(/^["'\'']|["'\'']$/, "", value)
      print value
      exit
    }
  ' "$file"
}

kernel_local=$(slk_var k/kernel/SLKBUILD pkgver)
yt_dlp_local=$(slk_var ap/yt-dlp/SLKBUILD pkgver)
yt_dlp_ejs_local=$(slk_var l/yt-dlp-ejs/SLKBUILD pkgver)
rust_local=$(slk_var d/rust/SLKBUILD pkgver)
codex_local=$(slk_var d/codex/SLKBUILD pkgver)
orca_local=$(slk_var xap/orca/SLKBUILD pkgver)
firmware_local_date=$(awk -F= '/^_fwdate=/{print $2; exit}' a/kernel-firmware/SLKBUILD)
firmware_local_commit=$(awk -F= '/^_fwcommit=/{print $2; exit}' a/kernel-firmware/SLKBUILD)
firmware_local="${firmware_local_date}_${firmware_local_commit}"

kernel_json=$(curl -L --silent --show-error https://www.kernel.org/releases.json)
kernel_latest=$(
  python3 -c 'import json,sys; data=json.load(sys.stdin); print(data["latest_stable"]["version"])' \
    <<< "$kernel_json"
)
kernel_latest_eol=$(
  python3 -c 'import json, sys
local = sys.argv[1]
series = ".".join(local.split(".")[:2])
data = json.load(sys.stdin)
for release in data["releases"]:
    if release["version"].startswith(series + "."):
        print("yes" if release.get("iseol") else "no")
        break
else:
    print("unknown")' "$kernel_local" <<< "$kernel_json"
)

firmware_index=$(curl -L --silent --show-error https://www.kernel.org/pub/linux/kernel/firmware/)
firmware_latest_date=$(
  sed -nE 's/.*linux-firmware-([0-9]{8})\.tar\.xz.*/\1/p' <<< "$firmware_index" |
    sort -V |
    tail -n 1
)
firmware_latest_commit=$(
  git ls-remote https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git refs/heads/main |
    awk '{print substr($1,1,7)}'
)
firmware_latest="${firmware_latest_date}_${firmware_latest_commit}"

latest_git_tag() {
  local repo=$1
  local pattern=$2
  local strip=${3:-}
  git ls-remote --tags "$repo" "$pattern" |
    awk -F/ '{print $NF}' |
    sed 's/\^{}$//' |
    sed "s/^${strip}//" |
    grep -E '^[0-9]+([.][0-9]+){1,3}([.][0-9]+)?$' |
    sort -Vu |
    tail -n 1
}

yt_dlp_latest=$(latest_git_tag https://github.com/yt-dlp/yt-dlp.git 'refs/tags/*')
yt_dlp_ejs_latest=$(latest_git_tag https://github.com/yt-dlp/ejs.git 'refs/tags/*')
rust_toml=$(curl -L --silent --show-error https://static.rust-lang.org/dist/channel-rust-stable.toml)
rust_latest=$(
  awk -F'"' '/^\[pkg.rust\]/{inpkg=1; next} inpkg && /^version = /{split($2, v, " "); print v[1]; exit}' <<< "$rust_toml"
)
codex_latest=$(latest_git_tag https://github.com/openai/codex.git 'refs/tags/rust-v*' 'rust-v')
orca_index=$(curl -L --silent --show-error https://download.gnome.org/sources/orca/49/)
orca_latest=$(
  sed -nE 's/.*orca-([0-9]+[.][0-9]+([.][0-9]+)?)\.tar\.xz.*/\1/p' <<< "$orca_index" |
    sort -Vu |
    tail -n 1
)

version_lt() {
  [[ "$1" != "$2" ]] && [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n 1)" = "$1" ]]
}

declare -a build_paths=()
declare -a applyable_paths=()

record_status() {
  local name=$1
  local local_version=$2
  local latest_version=$3
  local path=${4:-}
  local applyable=${5:-no}
  local status=ok

  if version_lt "$local_version" "$latest_version"; then
    status=stale
    if [[ -n "$path" && "$applyable" = yes ]]; then
      build_paths+=("$path")
    fi
  fi
  if [[ -n "$path" && "$applyable" = yes ]]; then
    applyable_paths+=("$path")
  fi
  printf '%-18s %-22s %-22s %s\n' "$name" "$local_version" "$latest_version" "$status"
}

printf '%-18s %-22s %-22s %s\n' "package" "local" "upstream" "status"
printf '%-18s %-22s %-22s %s\n' "-------" "-----" "--------" "------"
record_status kernel "$kernel_local" "$kernel_latest" k/kernel-headers yes
record_status kernel-source "$kernel_local" "$kernel_latest" k/kernel-source yes
record_status kernel-image "$kernel_local" "$kernel_latest" k/kernel yes
record_status kernel-firmware "$firmware_local" "$firmware_latest" a/kernel-firmware yes
record_status yt-dlp "$yt_dlp_local" "$yt_dlp_latest" ap/yt-dlp yes
record_status yt-dlp-ejs "$yt_dlp_ejs_local" "$yt_dlp_ejs_latest" l/yt-dlp-ejs no
record_status rust "$rust_local" "$rust_latest" d/rust no
record_status codex "$codex_local" "$codex_latest" d/codex no
record_status orca "$orca_local" "$orca_latest" xap/orca no

if [[ "$kernel_latest_eol" = yes ]]; then
  printf '\nNote: local kernel series %s is marked EOL by kernel.org.\n' "${kernel_local%.*}"
fi

backup_file() {
  local file=$1
  local backup_dir

  backup_dir=".upgrade-backups/$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$backup_dir/$(dirname "$file")"
  cp -a "$file" "$backup_dir/$file"
}

replace_line() {
  local file=$1
  local pattern=$2
  local replacement=$3
  sed -i -E "s|$pattern|$replacement|" "$file"
}

if [[ "$do_apply" = yes ]]; then
  printf '\nApplying metadata updates for low-risk packages...\n'

  if version_lt "$kernel_local" "$kernel_latest"; then
    for file in k/kernel/SLKBUILD k/kernel-source/SLKBUILD k/kernel-headers/SLKBUILD; do
      backup_file "$file"
      replace_line "$file" '^pkgver=.*$' "pkgver=$kernel_latest"
      replace_line "$file" 'kernel/v[0-9]+[.]x/linux-\$\{pkgver\}[.]tar[.]xz' "kernel/v${kernel_latest%%.*}.x/linux-\${pkgver}.tar.xz"
    done
    if [[ ! -f "k/kernel/configs/config-$kernel_latest" ]]; then
      cp -a "k/kernel/configs/config-$kernel_local" "k/kernel/configs/config-$kernel_latest"
      printf 'Copied k/kernel/configs/config-%s to config-%s; review before build.\n' "$kernel_local" "$kernel_latest"
    fi
  fi

  if version_lt "$firmware_local_date" "$firmware_latest_date"; then
    backup_file a/kernel-firmware/SLKBUILD
    replace_line a/kernel-firmware/SLKBUILD '^_fwdate=.*$' "_fwdate=$firmware_latest_date"
    replace_line a/kernel-firmware/SLKBUILD '^_fwcommit=.*$' "_fwcommit=$firmware_latest_commit"
  fi

  if version_lt "$yt_dlp_local" "$yt_dlp_latest"; then
    tmp_tar=$(mktemp)
    yt_url="https://github.com/yt-dlp/yt-dlp/archive/${yt_dlp_latest}/yt-dlp-${yt_dlp_latest}.tar.gz"
    curl -L --silent --show-error -o "$tmp_tar" "$yt_url"
    yt_sha256=$(sha256sum "$tmp_tar" | awk '{print $1}')
    yt_md5=$(md5sum "$tmp_tar" | awk '{print $1}')
    rm -f "$tmp_tar"

    backup_file ap/yt-dlp/SLKBUILD
    backup_file ap/yt-dlp/yt-dlp.info
    replace_line ap/yt-dlp/SLKBUILD '^pkgver=.*$' "pkgver=$yt_dlp_latest"
    replace_line ap/yt-dlp/SLKBUILD "^sha256sums=.*$" "sha256sums=('$yt_sha256')"
    replace_line ap/yt-dlp/yt-dlp.info '^VERSION=.*$' "VERSION=\"$yt_dlp_latest\""
    replace_line ap/yt-dlp/yt-dlp.info '^DOWNLOAD=.*$' "DOWNLOAD=\"$yt_url\""
    replace_line ap/yt-dlp/yt-dlp.info '^MD5SUM=.*$' "MD5SUM=\"$yt_md5\""
  fi
fi

if [[ "$do_build" = yes ]]; then
  mkdir -p "$staging_dir" "$log_root"
  if [[ "$reset_staging" = yes ]]; then
    find "$staging_dir" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  fi

  if [[ ${#build_paths[@]} -eq 0 ]]; then
    build_paths=("${applyable_paths[@]}")
    printf '\nNo applyable stale packages were found; building current applyable targets.\n'
  fi

  printf '\nBuilding into %s\nLogs in %s\n' "$staging_dir" "$log_root"
  for package_path in "${build_paths[@]}"; do
    log_file="$log_root/${package_path//\//_}.log"
    printf 'Building %s ... log: %s\n' "$package_path" "$log_file"
    ./build-package.sh --no-install --only -s "$staging_dir" "$package_path" >"$log_file" 2>&1
  done
fi
