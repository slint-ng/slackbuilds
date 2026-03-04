#!/usr/bin/env bash
set -euo pipefail

show_usage() {
  cat <<'EOF'
Usage: build-package.sh [options] <category/package>

Build a package and any missing repository dependencies described by .dep files.
New artifacts are added to the staging directory without removing existing ones.
Use --reset without a package path to clear staged artifacts and exit.

Options:
      --dependencies       Print the recursive dependency closure and exit.
  -f, --full               Rebuild the full in-repo dependency closure.
      --only               Build only the requested package and skip dependency resolution.
      --reset              Remove existing staged package artifacts before building.
      --skip PKGNAME       Treat a package as already satisfied. Repeatable.
  -k, --skip-staged        Skip packages that already have artifacts in staging.
  -s, --staging-dir DIR    Staging directory relative to repo root (default: staging).
  -n, --no-install         Build and stage packages without installing them.
  -h, --help               Show this help text.
EOF
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  local commandName=$1

  command -v "$commandName" >/dev/null 2>&1 || die "missing required command: $commandName"
}

trim_whitespace() {
  local value=$1

  value=${value#"${value%%[![:space:]]*}"}
  value=${value%"${value##*[![:space:]]}"}
  printf '%s\n' "$value"
}

trim_trailing_slash() {
  local value=$1

  while [[ "$value" != "/" && "$value" == */ ]]; do
    value=${value%/}
  done

  printf '%s\n' "$value"
}

resolve_absolute_path() {
  local pathValue=$1

  if [[ -d "$pathValue" ]]; then
    (cd "$pathValue" && pwd -P)
  else
    (cd "$(dirname "$pathValue")" && printf '%s/%s\n' "$(pwd -P)" "$(basename "$pathValue")")
  fi
}

normalize_repo_path() {
  local pathValue=$1
  local absolutePath=""
  local relativePath=""

  pathValue=$(trim_trailing_slash "$pathValue")
  [[ "$pathValue" != /* ]] || die "package path must be relative to the worktree root"

  absolutePath=$(resolve_absolute_path "${repoRoot}/${pathValue}")
  [[ -d "$absolutePath" ]] || die "package directory not found: $pathValue"

  case "$absolutePath" in
    "$repoRoot")
      die "package path must point to a package directory below the worktree root"
      ;;
    "$repoRoot"/*)
      relativePath=${absolutePath#"$repoRoot"/}
      ;;
    *)
      die "package path escapes the worktree root: $pathValue"
      ;;
  esac

  printf '%s\n' "$relativePath"
}

normalize_staging_path() {
  local pathValue=$1
  local -a pathSegments=()
  local pathSegment=""

  pathValue=$(trim_trailing_slash "$pathValue")
  [[ -n "$pathValue" ]] || die "staging directory must not be empty"

  if [[ "$pathValue" = /* ]]; then
    printf '%s\n' "$pathValue"
    return
  fi

  IFS='/' read -r -a pathSegments <<< "$pathValue"
  for pathSegment in "${pathSegments[@]}"; do
    [[ -n "$pathSegment" ]] || continue
    [[ "$pathSegment" != "." ]] || die "staging directory must not contain '.' path segments"
    [[ "$pathSegment" != ".." ]] || die "staging directory must not contain '..' path segments"
  done

  printf '%s\n' "${repoRoot}/${pathValue}"
}

latest_file() {
  local searchDir=$1

  find "$searchDir" -maxdepth 1 -type f \
    \( -name '*.txz' -o -name '*.tgz' -o -name '*.tbz' -o -name '*.tlz' \) \
    -printf '%T@ %p\n' 2>/dev/null \
    | sort -nr \
    | head -n 1 \
    | cut -d' ' -f2-
}

pkg_base_from_file() {
  local fileName=$1

  fileName=${fileName%.txz}
  fileName=${fileName%.tgz}
  fileName=${fileName%.tbz}
  fileName=${fileName%.tlz}

  printf '%s\n' "$fileName"
}

latest_matching_file() {
  local searchDir=$1
  local filePattern=$2

  find "$searchDir" -maxdepth 1 -type f \
    \( -name "$filePattern.txz" -o -name "$filePattern.tgz" -o -name "$filePattern.tbz" -o -name "$filePattern.tlz" \) \
    -printf '%T@ %p\n' 2>/dev/null \
    | sort -nr \
    | head -n 1 \
    | cut -d' ' -f2-
}

parse_pkgname() {
  local slkbuildPath=$1
  local packageDir
  local assignmentText=""
  local packageName=""

  packageDir=$(dirname "$slkbuildPath")
  assignmentText=$(
    sed -nE 's/^[[:space:]]*(export[[:space:]]+)?pkgname[[:space:]]*=(.*)$/\2/p' "$slkbuildPath" \
      | head -n 1
  )
  [[ -n "$assignmentText" ]] || die "could not parse pkgname from $slkbuildPath"

  packageName=$(
    cd "$packageDir" && \
      bash -c 'set -eo pipefail; assignmentText=$1; set +u; eval "pkgname=${assignmentText}"; printf "%s\n" "${pkgname:-}"' _ "$assignmentText"
  ) || die "could not parse pkgname from $slkbuildPath"

  [[ -n "$packageName" ]] || die "could not parse pkgname from $slkbuildPath"
  printf '%s\n' "$packageName"
}

find_depfile() {
  local packageDir=$1
  local packageName=$2
  local -a artifactCandidates=()
  local -a allCandidates=()
  local depFile=""

  while IFS= read -r depFile; do
    artifactCandidates+=("$depFile")
  done < <(
    find "$packageDir" -maxdepth 1 -type f -name "${packageName}-*.dep" -print | sort
  )

  if (( ${#artifactCandidates[@]} == 1 )); then
    printf '%s\n' "${artifactCandidates[0]}"
    return
  fi

  if (( ${#artifactCandidates[@]} > 1 )); then
    die "multiple artifact-style depfiles found for ${packageName}: ${artifactCandidates[*]}"
  fi

  depFile="${packageDir}/${packageName}.dep"
  if [[ -f "$depFile" ]]; then
    printf '%s\n' "$depFile"
    return
  fi

  while IFS= read -r depFile; do
    allCandidates+=("$depFile")
  done < <(
    find "$packageDir" -maxdepth 1 -type f -name '*.dep' -print | sort
  )

  if (( ${#allCandidates[@]} == 1 )); then
    printf '%s\n' "${allCandidates[0]}"
    return
  fi

  if (( ${#allCandidates[@]} == 0 )); then
    return
  fi

  die "multiple .dep files found for package ${packageDirByRelative[${packageDir}]}: ${allCandidates[*]}"
}

read_dependencies() {
  local depFilePath=$1
  local arrayName=$2
  local rawValue=""
  local trimmedValue=""
  local -n dependencyRef=$arrayName

  dependencyRef=()
  [[ -n "$depFilePath" ]] || return 0

  while IFS= read -r rawValue; do
    trimmedValue=$(trim_whitespace "$rawValue")
    [[ -n "$trimmedValue" ]] || continue
    dependencyRef+=("$trimmedValue")
  done < <(tr ',\n' '\n' < "$depFilePath")
}

read_slkbuild_array() {
  local slkbuildPath=$1
  local arrayName=$2
  local arrayRefName=$3
  local packageDir=""
  local rawValue=""
  local trimmedValue=""
  local -n valueRef=$arrayRefName

  valueRef=()
  [[ -f "$slkbuildPath" ]] || return 0

  packageDir=$(dirname "$slkbuildPath")
  while IFS= read -r rawValue; do
    trimmedValue=$(trim_whitespace "$rawValue")
    [[ -n "$trimmedValue" ]] || continue
    valueRef+=("$trimmedValue")
  done < <(
    cd "$packageDir" && \
      bash -c '
        set +eu
        source ./SLKBUILD >/dev/null 2>&1
        arrayName=$1
        items=()
        eval "items=(\"\${${arrayName}[@]}\")"
        for item in "${items[@]}"; do
          printf "%s\n" "$item"
        done
      ' _ "$arrayName"
  )
}

append_unique_values() {
  local targetArrayName=$1
  shift
  local candidateValue=""
  local present=false
  local existingValue=""
  local -n targetRef=$targetArrayName

  for candidateValue in "$@"; do
    [[ -n "$candidateValue" ]] || continue
    present=false
    for existingValue in "${targetRef[@]}"; do
      if [[ "$existingValue" == "$candidateValue" ]]; then
        present=true
        break
      fi
    done
    [[ "$present" == true ]] && continue
    targetRef+=("$candidateValue")
  done
}

load_package_dependencies() {
  local packageDir=$1
  local packageName=$2
  local arrayName=$3
  local depFilePath=""
  local -a depFileDependencies=()
  local -a slkbuildDepends=()
  local -a slkbuildMakeDepends=()
  # shellcheck disable=SC2178
  declare -n dependencyRef=$arrayName

  dependencyRef=()

  depFilePath=$(find_depfile "$packageDir" "$packageName")
  if [[ -n "${packageNameByDir[${packageDir}]:-}" ]]; then
    packageDepfileByDir["$packageDir"]=$depFilePath
    read_slkbuild_array "${packageDir}/SLKBUILD" depends slkbuildDepends
    read_slkbuild_array "${packageDir}/SLKBUILD" makedepends slkbuildMakeDepends
  fi

  read_dependencies "$depFilePath" depFileDependencies

  append_unique_values dependencyRef "${depFileDependencies[@]}"
  append_unique_values dependencyRef "${slkbuildDepends[@]}"
  append_unique_values dependencyRef "${slkbuildMakeDepends[@]}"
}

skip_requested() {
  local packageName=$1
  local skippedName=""

  for skippedName in "${skippedPackages[@]}"; do
    if [[ "$skippedName" == "$packageName" ]]; then
      return 0
    fi
  done

  return 1
}

build_repo_index() {
  local slkbuildPath=""
  local packageDir=""
  local packageName=""
  local relativePath=""

  while IFS= read -r slkbuildPath; do
    packageDir=$(dirname "$slkbuildPath")
    packageName=$(parse_pkgname "$slkbuildPath")
    relativePath=${packageDir#"$repoRoot"/}

    if [[ -n "${packageDirByName[${packageName}]:-}" && "${packageDirByName[${packageName}]}" != "$packageDir" ]]; then
      if [[ -n "${duplicatePackageDirsByName[${packageName}]:-}" ]]; then
        duplicatePackageDirsByName["$packageName"]+=$'\n'
      fi
      duplicatePackageDirsByName["$packageName"]+="$packageDir"
      continue
    fi

    packageDirByName["$packageName"]=$packageDir
    packageNameByDir["$packageDir"]=$packageName
    packageDirByRelative["$packageDir"]=$relativePath
  done < <(
    find "$repoRoot" -mindepth 2 -maxdepth 3 -type f -name 'SLKBUILD' \
      -not -path "$repoRoot/.git/*" \
      -not -path "$repoRoot/templates/*" \
      -not -path "$repoRoot/staging/*" \
      | sort
  )
}

build_legacy_index() {
  local slackBuildPath=""
  local packageDir=""
  local packageName=""
  local relativePath=""

  while IFS= read -r slackBuildPath; do
    packageDir=$(dirname "$slackBuildPath")
    packageName=$(basename "$slackBuildPath" .SlackBuild)
    relativePath=${packageDir#"$repoRoot"/}

    if [[ -z "${legacyPackageDirByName[${packageName}]:-}" ]]; then
      legacyPackageDirByName["$packageName"]=$packageDir
      legacyPackageDirByRelative["$packageDir"]=$relativePath
      continue
    fi

    if [[ "${legacyPackageDirByName[${packageName}]}" == "$packageDir" ]]; then
      continue
    fi

    if [[ -n "${duplicateLegacyPackageDirsByName[${packageName}]:-}" ]]; then
      duplicateLegacyPackageDirsByName["$packageName"]+=$'\n'
    fi
    duplicateLegacyPackageDirsByName["$packageName"]+="$packageDir"
  done < <(
    find "$repoRoot" -mindepth 2 -maxdepth 3 -type f -name '*.SlackBuild' \
      -not -path "$repoRoot/.git/*" \
      -not -path "$repoRoot/templates/*" \
      -not -path "$repoRoot/staging/*" \
      | sort
  )
}

is_installed() {
  local packageName=$1
  local pattern=""

  if [[ "$packageName" == "slapt-get" ]]; then
    return 0
  fi

  pattern="${installedDbDir}/${packageName}-*"
  compgen -G "$pattern" >/dev/null 2>&1
}

provider_for_package() {
  local packageName=$1
  local duplicateDirsText=${duplicatePackageDirsByName[${packageName}]:-}
  local providerList=""
  local duplicateDir=""

  [[ -n "${packageDirByName[${packageName}]:-}" ]] || return 1

  if [[ -n "$duplicateDirsText" ]]; then
    providerList=${packageDirByRelative[${packageDirByName[${packageName}]}]}
    while IFS= read -r duplicateDir; do
      [[ -n "$duplicateDir" ]] || continue
      providerList+=", ${duplicateDir#"$repoRoot"/}"
    done <<< "$duplicateDirsText"
    die "multiple repository packages provide ${packageName}: ${providerList}"
  fi

  printf '%s\n' "${packageDirByName[${packageName}]}"
}

legacy_provider_for_package() {
  local packageName=$1
  local duplicateDirsText=${duplicateLegacyPackageDirsByName[${packageName}]:-}
  local providerList=""
  local duplicateDir=""

  [[ -n "${legacyPackageDirByName[${packageName}]:-}" ]] || return 1

  if [[ -n "$duplicateDirsText" ]]; then
    providerList=${legacyPackageDirByRelative[${legacyPackageDirByName[${packageName}]}]}
    while IFS= read -r duplicateDir; do
      [[ -n "$duplicateDir" ]] || continue
      providerList+=", ${duplicateDir#"$repoRoot"/}"
    done <<< "$duplicateDirsText"
    die "multiple legacy SlackBuild packages provide ${packageName}: ${providerList}"
  fi

  printf '%s\n' "${legacyPackageDirByName[${packageName}]}"
}

resolve_dependency_provider() {
  local dependencyToken=$1
  local -a dependencyChoices=()
  local dependencyChoice=""
  local trimmedChoice=""
  local repoChoice=""
  local repoPath=""
  local legacyPath=""
  local installedChoice=""

  IFS='|' read -r -a dependencyChoices <<< "$dependencyToken"

  for dependencyChoice in "${dependencyChoices[@]}"; do
    trimmedChoice=$(trim_whitespace "$dependencyChoice")
    [[ -n "$trimmedChoice" ]] || continue

    if skip_requested "$trimmedChoice"; then
      installedChoice=$trimmedChoice
      continue
    fi

    if [[ -z "$installedChoice" ]] && is_installed "$trimmedChoice"; then
      installedChoice=$trimmedChoice
    fi

    if [[ -z "$repoChoice" ]]; then
      repoPath=$(provider_for_package "$trimmedChoice" || true)
      if [[ -n "$repoPath" ]]; then
        repoChoice=$trimmedChoice
        continue
      fi
    fi

    legacyPath=$(legacy_provider_for_package "$trimmedChoice" || true)
    if [[ -n "$legacyPath" ]]; then
      die "package ${trimmedChoice} exists only as legacy SlackBuild at ${legacyPackageDirByRelative[${legacyPath}]}; convert it to SLKBUILD first"
    fi
  done

  if [[ "$fullBuild" == true ]]; then
    if [[ -n "$repoChoice" ]]; then
      printf 'repo:%s\n' "$repoChoice"
      return
    fi

    if [[ -n "$installedChoice" ]]; then
      printf 'installed:%s\n' "$installedChoice"
      return
    fi
  else
    if [[ -n "$installedChoice" ]]; then
      printf 'installed:%s\n' "$installedChoice"
      return
    fi

    if [[ -n "$repoChoice" ]]; then
      printf 'repo:%s\n' "$repoChoice"
      return
    fi
  fi

  die "Could not find package ${dependencyToken} in current repository"
}

format_cycle() {
  local packageDir=$1
  local startIndex=0
  local currentIndex=0
  local cycleText=""

  for currentIndex in "${!packageStack[@]}"; do
    if [[ "${packageStack[${currentIndex}]}" == "$packageDir" ]]; then
      startIndex=$currentIndex
      break
    fi
  done

  for (( currentIndex=startIndex; currentIndex<${#packageStack[@]}; currentIndex++ )); do
    if [[ -n "$cycleText" ]]; then
      cycleText+=$' -> '
    fi
    cycleText+="${packageNameByDir[${packageStack[${currentIndex}]}]}"
  done

  if [[ -n "$cycleText" ]]; then
    cycleText+=$' -> '
  fi
  cycleText+="${packageNameByDir[${packageDir}]}"

  printf '%s\n' "$cycleText"
}

resolve_dependency_for_listing() {
  local dependencyToken=$1
  local -a dependencyChoices=()
  local dependencyChoice=""
  local trimmedChoice=""

  IFS='|' read -r -a dependencyChoices <<< "$dependencyToken"

  for dependencyChoice in "${dependencyChoices[@]}"; do
    trimmedChoice=$(trim_whitespace "$dependencyChoice")
    [[ -n "$trimmedChoice" ]] || continue

    if [[ -n "${packageDirByName[${trimmedChoice}]:-}" && -z "${duplicatePackageDirsByName[${trimmedChoice}]:-}" ]]; then
      printf 'repo:%s\n' "$trimmedChoice"
      return
    fi

    if [[ -n "${legacyPackageDirByName[${trimmedChoice}]:-}" && -z "${duplicateLegacyPackageDirsByName[${trimmedChoice}]:-}" ]]; then
      printf 'legacy:%s\n' "$trimmedChoice"
      return
    fi
  done

  printf 'leaf:%s\n' "$dependencyToken"
}

collect_dependency_closure() {
  local packageDir=$1
  local packageName=$2
  local visitKey="${packageDir}|${packageName}"
  local -a dependencyNames=()
  local dependencyName=""
  local resolution=""
  local dependencyPkgName=""
  local providerDir=""

  [[ -z "${dependencyVisitState[${visitKey}]:-}" ]] || return 0
  dependencyVisitState["$visitKey"]="visited"

  load_package_dependencies "$packageDir" "$packageName" dependencyNames

  for dependencyName in "${dependencyNames[@]}"; do
    resolution=$(resolve_dependency_for_listing "$dependencyName")

    case "$resolution" in
      repo:*)
        dependencyPkgName=${resolution#repo:}
        append_unique_values dependencyOutput "$dependencyPkgName"
        providerDir=${packageDirByName[${dependencyPkgName}]}
        collect_dependency_closure "$providerDir" "$dependencyPkgName"
        ;;
      legacy:*)
        dependencyPkgName=${resolution#legacy:}
        append_unique_values dependencyOutput "$dependencyPkgName"
        providerDir=${legacyPackageDirByName[${dependencyPkgName}]}
        collect_dependency_closure "$providerDir" "$dependencyPkgName"
        ;;
      leaf:*)
        append_unique_values dependencyOutput "${resolution#leaf:}"
        ;;
    esac
  done
}

visit_package() {
  local packageDir=$1
  local packageName=${packageNameByDir[${packageDir}]}
  local currentState=${packageVisitState[${packageDir}]:-}
  local depFilePath=""
  local -a dependencyNames=()
  local -a depFileDependencies=()
  local -a slkbuildDepends=()
  local -a slkbuildMakeDepends=()
  local dependencyName=""
  local resolution=""
  local providerName=""

  case "$currentState" in
    completed)
      return
      ;;
    visiting)
      die "Dependency cycle detected: $(format_cycle "$packageDir")"
      ;;
  esac

  packageVisitState["$packageDir"]="visiting"
  packageStack+=("$packageDir")

  load_package_dependencies "$packageDir" "$packageName" dependencyNames

  for dependencyName in "${dependencyNames[@]}"; do
    resolution=$(resolve_dependency_provider "$dependencyName")
    if [[ "$resolution" == repo:* ]]; then
      providerName=${resolution#repo:}
      visit_package "${packageDirByName[${providerName}]}"
    fi
  done

  unset 'packageStack[${#packageStack[@]}-1]'
  packageVisitState["$packageDir"]="completed"
  buildQueue+=("$packageDir")
}

build_package() {
  local packageDir=$1
  local packageName=${packageNameByDir[${packageDir}]}
  local logPath="${packageDir}/build-${packageName}.log"
  local artifactPath=""
  local depFilePath=""

  printf 'Building %s\n' "${packageDirByRelative[${packageDir}]}"
  pushd "$packageDir" >/dev/null || die "failed to enter package directory: ${packageDirByRelative[${packageDir}]}"
  if ! fakeroot slkbuild -X 2>&1 | tee "$logPath"; then
    popd >/dev/null || true
    die "Build failed for ${packageDirByRelative[${packageDir}]}; see ${logPath}"
  fi
  popd >/dev/null || die "failed to return from package directory: ${packageDirByRelative[${packageDir}]}"

  artifactPath=$(latest_file "$packageDir")
  [[ -n "$artifactPath" ]] || die "No package artifact produced for ${packageDirByRelative[${packageDir}]}"

  depFilePath="${artifactPath%.*}.dep"
  if [[ ! -f "$depFilePath" ]]; then
    depFilePath=${packageDepfileByDir[${packageDir}]:-}
  fi

  if [[ -n "$depFilePath" && ! -f "$depFilePath" ]]; then
    die "No depfile found for built artifact ${artifactPath}"
  fi

  builtArtifactByDir["$packageDir"]=$artifactPath
  builtDepfileByDir["$packageDir"]=$depFilePath
}

install_package() {
  local packageDir=$1
  local artifactPath=${builtArtifactByDir[${packageDir}]}

  [[ "$noInstall" == false ]] || return 0

  printf 'Installing %s\n' "$(basename "$artifactPath")"
  sudo upgradepkg --install-new "$artifactPath" >/dev/null \
    || die "Install failed for ${artifactPath}"
}

ensure_staging_dir() {
  mkdir -p "$stagingDir"
}

reset_staging_dir() {
  find "$stagingDir" -mindepth 1 -maxdepth 1 -type f \
    \( -name '*.txz' -o -name '*.tgz' -o -name '*.tbz' -o -name '*.tlz' -o -name '*.dep' \) \
    -delete
}

stage_artifacts() {
  local packageDir=$1
  local artifactPath=${builtArtifactByDir[${packageDir}]}
  local depFilePath=${builtDepfileByDir[${packageDir}]:-}

  cp -f "$artifactPath" "$stagingDir/"
  if [[ -n "$depFilePath" ]]; then
    cp -f "$depFilePath" "$stagingDir/"
  fi
}

filter_staged_packages() {
  local packageDir=""
  local packageName=""
  local stagedArtifactPath=""
  local -a filteredQueue=()

  [[ "$skipStaged" == true ]] || return 0

  for packageDir in "${buildQueue[@]}"; do
    packageName=${packageNameByDir[${packageDir}]}
    stagedArtifactPath=$(latest_matching_file "$stagingDir" "${packageName}-*")
    if [[ -n "$stagedArtifactPath" ]]; then
      printf 'Skipping %s; staged artifact already exists: %s\n' \
        "${packageDirByRelative[${packageDir}]}" "$(basename "$stagedArtifactPath")"
      continue
    fi
    filteredQueue+=("$packageDir")
  done

  buildQueue=("${filteredQueue[@]}")
}

stop_sudo_keepalive() {
  if [[ -n "$sudoKeepalivePid" ]]; then
    kill "$sudoKeepalivePid" >/dev/null 2>&1 || true
    wait "$sudoKeepalivePid" >/dev/null 2>&1 || true
    sudoKeepalivePid=""
  fi
}

cleanup() {
  stop_sudo_keepalive
}

start_sudo_keepalive() {
  [[ "$noInstall" == false ]] || return 0

  sudo -v || die "failed to acquire sudo privileges for package installation"

  while true; do
    sudo -n -v >/dev/null 2>&1 || exit 0
    sleep 60
  done &
  sudoKeepalivePid=$!
}

repoRoot=$(cd "$(dirname "$0")" && pwd -P)
dependenciesOnly=false
fullBuild=false
onlyTarget=false
noInstall=false
resetStaging=false
skipStaged=false
stagingDir="${repoRoot}/staging"
packagePath=""
installedDbDir=/var/log/packages
sudoKeepalivePid=""
declare -a buildQueue=()
declare -a dependencyOutput=()
declare -a packageStack=()
declare -a skippedPackages=()
declare -A packageDirByName=()
declare -A packageNameByDir=()
declare -A packageDirByRelative=()
declare -A legacyPackageDirByName=()
declare -A legacyPackageDirByRelative=()
declare -A duplicateLegacyPackageDirsByName=()
declare -A duplicatePackageDirsByName=()
declare -A dependencyVisitState=()
declare -A packageVisitState=()
declare -A packageDepfileByDir=()
declare -A builtArtifactByDir=()
declare -A builtDepfileByDir=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dependencies)
      dependenciesOnly=true
      shift
      ;;
    -f|--full)
      fullBuild=true
      shift
      ;;
    --only)
      onlyTarget=true
      shift
      ;;
    --reset)
      resetStaging=true
      shift
      ;;
    --skip)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      skippedPackages+=("$2")
      shift 2
      ;;
    -k|--skip-staged)
      skipStaged=true
      shift
      ;;
    -s|--staging-dir)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      stagingDir=$(normalize_staging_path "$2")
      shift 2
      ;;
    -n|--no-install)
      noInstall=true
      shift
      ;;
    -h|--help)
      show_usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      die "unknown option: $1"
      ;;
    *)
      if [[ -n "$packagePath" ]]; then
        die "only one package path may be provided"
      fi
      packagePath=$1
      shift
      ;;
  esac
done

if [[ $# -gt 0 ]]; then
  die "unexpected trailing arguments: $*"
fi

if [[ -z "$packagePath" ]]; then
  if [[ "$resetStaging" == true && "$dependenciesOnly" == false ]]; then
    ensure_staging_dir
    reset_staging_dir
    printf 'Removed staged artifacts from %s\n' "$stagingDir"
    exit 0
  fi

  show_usage
  exit 2
fi

trap cleanup EXIT INT TERM HUP

if [[ "$dependenciesOnly" == false ]]; then
  require_cmd fakeroot
  require_cmd slkbuild

  if [[ "$noInstall" == false ]]; then
    require_cmd sudo
    require_cmd upgradepkg
  fi
fi

if [[ "$dependenciesOnly" == false && "$onlyTarget" == false ]]; then
  [[ -d "$installedDbDir" ]] || die "Installed package database not found at ${installedDbDir}; run this on the Slackware/Slint VM"
fi

packagePath=$(normalize_repo_path "$packagePath")
packageDir="${repoRoot}/${packagePath}"
[[ -f "${packageDir}/SLKBUILD" ]] || die "SLKBUILD not found for package: ${packagePath}"

if [[ "$dependenciesOnly" == true ]]; then
  build_repo_index
  build_legacy_index
  packageNameByDir["$packageDir"]=$(parse_pkgname "${packageDir}/SLKBUILD")
  packageDirByRelative["$packageDir"]=$packagePath
  collect_dependency_closure "$packageDir" "${packageNameByDir[${packageDir}]}"
  printf 'Dependencies for %s:\n' "$packagePath"
  for dependencyName in "${dependencyOutput[@]}"; do
    printf '  %s\n' "$dependencyName"
  done
  exit 0
elif [[ "$onlyTarget" == true ]]; then
  packageNameByDir["$packageDir"]=$(parse_pkgname "${packageDir}/SLKBUILD")
  packageDirByRelative["$packageDir"]=$packagePath
  buildQueue=("$packageDir")
else
  build_repo_index
  build_legacy_index

  [[ -n "${packageNameByDir[${packageDir}]:-}" ]] || die "package directory was not indexed as an SLKBUILD package: ${packagePath}"
  if skip_requested "${packageNameByDir[${packageDir}]}"; then
    die "target package ${packageNameByDir[${packageDir}]} cannot be skipped"
  fi
fi

ensure_staging_dir
if [[ "$resetStaging" == true ]]; then
  reset_staging_dir
fi
if [[ "$onlyTarget" == false ]]; then
  visit_package "$packageDir"
  (( ${#buildQueue[@]} > 0 )) || die "no packages were selected to build for ${packagePath}"
fi
filter_staged_packages

if (( ${#buildQueue[@]} == 0 )); then
  printf 'Nothing to build. Staged artifacts already cover the requested packages.\n'
  exit 0
fi

printf 'Build queue:\n'
for packageDir in "${buildQueue[@]}"; do
  printf '  %s\n' "${packageDirByRelative[${packageDir}]}"
done

start_sudo_keepalive

for packageDir in "${buildQueue[@]}"; do
  build_package "$packageDir"
  stage_artifacts "$packageDir"
  install_package "$packageDir"
done

printf 'Built %s package(s). Staged artifacts in %s\n' "${#buildQueue[@]}" "$stagingDir"
