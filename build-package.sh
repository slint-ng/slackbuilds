#!/usr/bin/env bash
set -euo pipefail

show_usage() {
  cat <<'EOF'
Usage: build-package.sh [options] [category/package]

Build a package and any missing repository dependencies described by SLKBUILD
metadata and package depfiles. Built package artifacts get a fresh .dep file from depfinder.
New artifacts are added to the staging directory without removing existing ones.
Use -f/--full without a package path to build every SLKBUILD package in the repo.
Use --reset without -f or a package path to clear staged artifacts and exit.

Options:
      --dependencies       Print the recursive dependency closure and exit.
  -f, --full               Rebuild the full in-repo dependency closure, or all packages when no path is given.
      --only               Build only the requested package and skip dependency resolution.
      --reset              Remove existing staged package artifacts before building.
      --skip PKGNAME       Treat a package as already satisfied. Repeatable.
  -k, --skip-staged        Skip packages whose current pkgver/pkgrel already exists in staging.
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

discover_available_cores() {
  local coreCount=""

  if command -v nproc >/dev/null 2>&1; then
    coreCount=$(nproc 2>/dev/null || true)
  elif command -v getconf >/dev/null 2>&1; then
    coreCount=$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)
  fi

  if [[ ! "$coreCount" =~ ^[0-9]+$ ]] || (( coreCount < 1 )); then
    coreCount=1
  fi

  printf '%s\n' "$coreCount"
}

calculate_parallel_jobs() {
  local coreCount=""
  local jobCount=""

  coreCount=$(discover_available_cores)
  jobCount=$(( (coreCount * 3) / 4 ))

  if (( jobCount < 1 )); then
    jobCount=1
  fi

  printf '%s\n' "$jobCount"
}

trim_whitespace() {
  local value=$1

  value=${value#"${value%%[![:space:]]*}"}
  value=${value%"${value##*[![:space:]]}"}
  printf '%s\n' "$value"
}

normalize_dependency_token() {
  local dependencyToken=$1
  local -a dependencyChoices=()
  local dependencyChoice=""
  local normalizedChoice=""
  local normalizedToken=""

  IFS='|' read -r -a dependencyChoices <<< "$dependencyToken"

  for dependencyChoice in "${dependencyChoices[@]}"; do
    normalizedChoice=$(normalize_dependency_choice "$dependencyChoice")
    [[ -n "$normalizedChoice" ]] || continue

    if [[ -n "$normalizedToken" ]]; then
      normalizedToken+="|"
    fi
    normalizedToken+="$normalizedChoice"
  done

  printf '%s\n' "$normalizedToken"
}

normalize_dependency_choice() {
  local dependencyToken=$1

  dependencyToken=$(trim_whitespace "$dependencyToken")
  dependencyToken=${dependencyToken%%[<>=]*}

  case "$dependencyToken" in
    gcc-libs)
      # Arch's gcc-libs package does not exist in Slint. Use the libgcc
      # provider token as a safe fallback; depfinder will add libstdc++
      # providers when the built artifact actually needs them.
      printf '%s\n' 'aaa_libraries|gcc'
      ;;
    icu)
      # Slint ships the primary ICU runtime as icu4c. Normalize the generic
      # token so dependency closure and installed-package checks stay
      # consistent with generated depfiles.
      printf '%s\n' 'icu4c'
      ;;
    gtk3)
      # Slint ships GTK 3 as the gtk+3 package. Accept the common alias so
      # dependency closure, rebuild order, and merged depfiles stay canonical.
      printf '%s\n' 'gtk+3'
      ;;
    libcrypto.so|libssl.so)
      # Some older tracked depfiles name OpenSSL sonames directly. Resolve them
      # through the package providers so full traversal can reuse installed
      # packages or repo packages consistently.
      printf '%s\n' 'openssl|openssl-solibs'
      ;;
    X-ABI-VIDEODRV_VERSION)
      # This is an xorg-server driver ABI guard, not a package in this repo.
      printf '%s\n' 'xorg-server-devel|xorg-server'
      ;;
    *)
      printf '%s\n' "$dependencyToken"
      ;;
  esac
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

depfile_path_for_artifact() {
  local artifactPath=$1

  printf '%s.dep\n' "${artifactPath%.*}"
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
  local packageDir=""
  local packageName=""

  packageDir=$(dirname "$slkbuildPath")
  packageName=$(
    cd "$packageDir" && \
      bash -c '
        set +eu
        source ./SLKBUILD >/dev/null 2>&1
        printf "%s\n" "${pkgname:-}"
      '
  ) || die "could not parse pkgname from $slkbuildPath"

  [[ -n "$packageName" ]] || die "could not parse pkgname from $slkbuildPath"
  printf '%s\n' "$packageName"
}

parse_slkbuild_scalar() {
  local slkbuildPath=$1
  local variableName=$2
  local packageDir=""
  local scalarValue=""

  packageDir=$(dirname "$slkbuildPath")
  scalarValue=$(
    cd "$packageDir" && \
      bash -c '
        set +eu
        source ./SLKBUILD >/dev/null 2>&1
        variableName=$1
        eval "printf \"%s\n\" \"\${${variableName}:-}\""
      ' _ "$variableName"
  ) || die "could not parse ${variableName} from $slkbuildPath"

  [[ -n "$scalarValue" ]] || die "could not parse ${variableName} from $slkbuildPath"
  printf '%s\n' "$scalarValue"
}

find_depfile() {
  local packageDir=$1
  local packageName=$2
  local -a artifactCandidates=()
  local -a matchingArtifactCandidates=()
  local -a allCandidates=()
  local depFile=""
  local packageVersion=""
  local packageRelease=""
  local artifactBaseName=""

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
    if [[ -f "${packageDir}/SLKBUILD" ]]; then
      packageVersion=$(parse_slkbuild_scalar "${packageDir}/SLKBUILD" pkgver)
      packageRelease=$(parse_slkbuild_scalar "${packageDir}/SLKBUILD" pkgrel)

      for depFile in "${artifactCandidates[@]}"; do
        artifactBaseName=$(basename "$depFile")
        if [[ "$artifactBaseName" == "${packageName}-${packageVersion}-"*"-${packageRelease}.dep" ]]; then
          matchingArtifactCandidates+=("$depFile")
        fi
      done

      if (( ${#matchingArtifactCandidates[@]} == 1 )); then
        printf '%s\n' "${matchingArtifactCandidates[0]}"
        return
      fi

      if (( ${#matchingArtifactCandidates[@]} > 1 )); then
        die "multiple current artifact-style depfiles found for ${packageName}: ${matchingArtifactCandidates[*]}"
      fi
    fi

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

find_curated_depfile() {
  local packageDir=$1
  local packageName=$2
  local depFile="${packageDir}/${packageName}.dep"

  if [[ -f "$depFile" ]]; then
    printf '%s\n' "$depFile"
  fi
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
    trimmedValue=$(normalize_dependency_token "$trimmedValue")
    dependencyRef+=("$trimmedValue")
  done < <(tr ',\n' '\n' < "$depFilePath")
}

write_dependencies() {
  local depFilePath=$1
  shift
  local dependencyValue=""
  local firstEntry=true

  : > "$depFilePath"
  for dependencyValue in "$@"; do
    [[ -n "$dependencyValue" ]] || continue
    if [[ "$firstEntry" == true ]]; then
      printf '%s' "$dependencyValue" >> "$depFilePath"
      firstEntry=false
      continue
    fi
    printf ',%s' "$dependencyValue" >> "$depFilePath"
  done
  printf '\n' >> "$depFilePath"
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
    trimmedValue=$(normalize_dependency_token "$trimmedValue")
    valueRef+=("$trimmedValue")
  done < <(
    cd "$packageDir" && \
      bash -c '
        set +eu
        source ./SLKBUILD >/dev/null 2>&1
        arrayName=$1
        if ! declare -p "$arrayName" >/dev/null 2>&1; then
          exit 0
        fi
        if declare -p "$arrayName" 2>/dev/null | grep -q "^declare \-[^ ]*a"; then
          items=()
          eval "items=(\"\${${arrayName}[@]}\")"
          for item in "${items[@]}"; do
            printf "%s\n" "$item"
          done
        else
          eval "scalarValue=\${${arrayName}}"
          for item in $scalarValue; do
            printf "%s\n" "$item"
          done
        fi
      ' _ "$arrayName"
  )
}

slkbuild_variable_declared() {
  local slkbuildPath=$1
  local variableName=$2
  local packageDir=""

  [[ -f "$slkbuildPath" ]] || return 1

  packageDir=$(dirname "$slkbuildPath")
  cd "$packageDir" && \
    bash -c '
      set +eu
      source ./SLKBUILD >/dev/null 2>&1
      variableName=$1
      declare -p "$variableName" >/dev/null 2>&1
    ' _ "$variableName"
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

dependencyTokenMatchesPackage() {
  local packageDir=$1
  local packageName=$2
  local dependencyToken=$3
  local -a dependencyChoices=()
  local dependencyChoice=""
  local trimmedChoice=""
  local providerPath=""

  [[ -n "$dependencyToken" ]] || return 1
  [[ -n "$packageName" ]] || return 1

  if [[ "$dependencyToken" == "$packageName" ]]; then
    return 0
  fi

  IFS='|' read -r -a dependencyChoices <<< "$dependencyToken"

  for dependencyChoice in "${dependencyChoices[@]}"; do
    trimmedChoice=$(trim_whitespace "$dependencyChoice")
    [[ -n "$trimmedChoice" ]] || continue

    if [[ "$trimmedChoice" == "$packageName" ]]; then
      return 0
    fi

    if [[ -n "${duplicatePackageDirsByName[${trimmedChoice}]:-}" ]]; then
      continue
    fi

    providerPath=$(provider_for_package "$trimmedChoice" || true)
    if [[ -n "$providerPath" && "$providerPath" == "$packageDir" ]]; then
      return 0
    fi
  done

  return 1
}

load_package_dependencies() {
  local packageDir=$1
  local packageName=$2
  local arrayName=$3
  local depFilePath=""
  local slkbuildPath="${packageDir}/SLKBUILD"
  local -a depFileDependencies=()
  local -a slkbuildDepends=()
  local -a slkbuildMakeDepends=()
  local -a filteredDependencies=()
  local dependencyValue=""
  # shellcheck disable=SC2178
  declare -n dependencyRef=$arrayName

  dependencyRef=()

  if [[ -n "${packageNameByDir[${packageDir}]:-}" ]]; then
    read_slkbuild_array "$slkbuildPath" depends slkbuildDepends
    read_slkbuild_array "$slkbuildPath" makedepends slkbuildMakeDepends
    depFilePath=$(find_curated_depfile "$packageDir" "$packageName" || true)
    if [[ -z "$depFilePath" ]]; then
      depFilePath=$(find_depfile "$packageDir" "$packageName" || true)
    fi
  else
    depFilePath=$(find_depfile "$packageDir" "$packageName")
  fi

  if [[ -n "$depFilePath" ]]; then
    read_dependencies "$depFilePath" depFileDependencies
  fi

  append_unique_values dependencyRef "${depFileDependencies[@]}"
  append_unique_values dependencyRef "${slkbuildDepends[@]}"
  append_unique_values dependencyRef "${slkbuildMakeDepends[@]}"

  for dependencyValue in "${dependencyRef[@]}"; do
    if dependencyTokenMatchesPackage "$packageDir" "$packageName" "$dependencyValue"; then
      continue
    fi
    filteredDependencies+=("$dependencyValue")
  done

  dependencyRef=("${filteredDependencies[@]}")
}

remove_value() {
  local targetArrayName=$1
  local removedValue=$2
  local candidateValue=""
  local -a filteredValues=()
  # shellcheck disable=SC2178
  local -n targetRef=$targetArrayName

  for candidateValue in "${targetRef[@]}"; do
    [[ "$candidateValue" == "$removedValue" ]] && continue
    filteredValues+=("$candidateValue")
  done

  targetRef=("${filteredValues[@]}")
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

dependency_has_installed_choice() {
  local dependencyToken=$1
  local -a dependencyChoices=()
  local dependencyChoice=""
  local trimmedChoice=""

  IFS='|' read -r -a dependencyChoices <<< "$dependencyToken"

  for dependencyChoice in "${dependencyChoices[@]}"; do
    trimmedChoice=$(trim_whitespace "$dependencyChoice")
    [[ -n "$trimmedChoice" ]] || continue

    if skip_requested "$trimmedChoice" || is_installed "$trimmedChoice"; then
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
    allPackageDirs+=("$packageDir")
  done < <(
    find "$repoRoot" -mindepth 2 -maxdepth 3 -type f -name 'SLKBUILD' \
      -not -path "$repoRoot/.git/*" \
      -not -path "$repoRoot/templates/*" \
      -not -path "$repoRoot/staging/*" \
      | sort
  )
}

collect_full_build_queue() {
  local packageDir=""
  local packageName=""

  for packageDir in "${allPackageDirs[@]}"; do
    packageName=${packageNameByDir[${packageDir}]}
    if skip_requested "$packageName"; then
      printf 'Skipping %s because --skip %s was requested.\n' \
        "${packageDirByRelative[${packageDir}]}" "$packageName"
      continue
    fi
    visit_package "$packageDir"
  done
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
  local -a patterns=()
  local pattern=""
  local -a commands=()
  local commandName=""
  local -a filePaths=()
  local filePath=""

  if [[ "$packageName" == "slapt-get" ]]; then
    return 0
  fi

  case "$packageName" in
    cargo)
      patterns=(
        "${installedDbDir}/cargo-*"
        "${installedDbDir}/rust-*"
      )
      commands=("cargo")
      ;;
    gcc-libs)
      patterns=(
        "${installedDbDir}/aaa_libraries-*"
        "${installedDbDir}/gcc-*"
      )
      ;;
    openal|OpenAL|openal-soft)
      patterns=(
        "${installedDbDir}/OpenAL-*"
        "${installedDbDir}/openal-*"
        "${installedDbDir}/openal-soft-*"
      )
      ;;
    python)
      patterns=(
        "${installedDbDir}/python-*"
        "${installedDbDir}/python3-*"
      )
      commands=("python" "python3")
      ;;
    freetype|freetype2)
      patterns=(
        "${installedDbDir}/freetype-*"
        "${installedDbDir}/freetype2-*"
      )
      ;;
    docbook-sgml)
      patterns=(
        "${installedDbDir}/docbook-sgml-*"
        "${installedDbDir}/sgml-common-*"
      )
      filePaths=(
        "/usr/share/sgml/docbook"
        "/etc/sgml/catalog"
      )
      ;;
    docbook-utils)
      patterns=("${installedDbDir}/docbook-utils-*")
      commands=("docbook2html" "docbook2man")
      ;;
    *)
      patterns=("${installedDbDir}/${packageName}-*")
      ;;
  esac

  for pattern in "${patterns[@]}"; do
    if compgen -G "$pattern" >/dev/null 2>&1; then
      return 0
    fi
  done

  for commandName in "${commands[@]}"; do
    if command -v "$commandName" >/dev/null 2>&1; then
      return 0
    fi
  done

  for filePath in "${filePaths[@]}"; do
    if [[ -e "$filePath" ]]; then
      return 0
    fi
  done

  return 1
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
      if [[ -n "${duplicatePackageDirsByName[${trimmedChoice}]:-}" ]]; then
        if [[ "$buildAllPackages" == true ]]; then
          printf 'Warning: treating ambiguous repository dependency as preinstalled for full repository build: %s\n' \
            "$trimmedChoice" >&2
          installedChoice=${installedChoice:-$trimmedChoice}
          continue
        fi
        provider_for_package "$trimmedChoice" >/dev/null
      fi
      repoPath=$(provider_for_package "$trimmedChoice" || true)
      if [[ -n "$repoPath" ]]; then
        repoChoice=$trimmedChoice
        continue
      fi
    fi

    if [[ "$buildAllPackages" == true && -n "$installedChoice" ]]; then
      continue
    fi

    if [[ -n "${duplicateLegacyPackageDirsByName[${trimmedChoice}]:-}" ]]; then
      if [[ "$buildAllPackages" == true ]]; then
        printf 'Warning: treating ambiguous legacy dependency as preinstalled for full repository build: %s\n' \
          "$trimmedChoice" >&2
        installedChoice=${installedChoice:-$trimmedChoice}
        continue
      fi
      legacy_provider_for_package "$trimmedChoice" >/dev/null
    fi

    legacyPath=$(legacy_provider_for_package "$trimmedChoice" || true)
    if [[ -n "$legacyPath" ]]; then
      if [[ "$buildAllPackages" == true ]]; then
        printf 'Warning: treating legacy-only dependency as preinstalled for full repository build: %s (%s)\n' \
          "$trimmedChoice" "${legacyPackageDirByRelative[${legacyPath}]}" >&2
        installedChoice=$trimmedChoice
        continue
      fi
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

  if [[ "$buildAllPackages" == true ]]; then
    printf 'Warning: treating unresolved external dependency as preinstalled for full repository build: %s\n' \
      "$dependencyToken" >&2
    printf 'external:%s\n' "$dependencyToken"
    return
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
  local providerDir=""

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
      providerDir=${packageDirByName[${providerName}]}
      if [[ "${packageVisitState[${providerDir}]:-}" == "visiting" ]] \
        && dependency_has_installed_choice "$dependencyName"; then
        printf 'Using installed %s to break dependency cycle: %s\n' \
          "$dependencyName" "$(format_cycle "$providerDir")" >&2
        continue
      fi
      visit_package "$providerDir"
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
  local defaultNumjobs=""
  local effectiveNumjobs=""

  defaultNumjobs=$(calculate_parallel_jobs)
  effectiveNumjobs=${numjobs:-$defaultNumjobs}
  if [[ ! "$effectiveNumjobs" =~ ^[0-9]+$ ]] || (( effectiveNumjobs < 1 )); then
    effectiveNumjobs=$defaultNumjobs
  fi

  prune_local_outputs_if_depfiles_ambiguous "$packageDir"

  printf 'Building %s (numjobs=%s)\n' "${packageDirByRelative[${packageDir}]}" "$effectiveNumjobs"
  pushd "$packageDir" >/dev/null || die "failed to enter package directory: ${packageDirByRelative[${packageDir}]}"
  if ! env numjobs="$effectiveNumjobs" fakeroot slkbuild -X 2>&1 | tee "$logPath"; then
    popd >/dev/null || true
    die "Build failed for ${packageDirByRelative[${packageDir}]}; see ${logPath}"
  fi
  popd >/dev/null || die "failed to return from package directory: ${packageDirByRelative[${packageDir}]}"

  artifactPath=$(latest_file "$packageDir")
  [[ -n "$artifactPath" ]] || die "No package artifact produced for ${packageDirByRelative[${packageDir}]}"

  depFilePath=$(generate_depfile_for_artifact "$packageDir" "$packageName" "$artifactPath")

  builtArtifactByDir["$packageDir"]=$artifactPath
  builtDepfileByDir["$packageDir"]=$depFilePath
}

prune_local_outputs_if_depfiles_ambiguous() {
  local packageDir=$1
  local packageRelativePath=${packageDirByRelative[${packageDir}]:-${packageDir}}
  local -a depFiles=()
  local stalePath=""

  while IFS= read -r stalePath; do
    depFiles+=("$stalePath")
  done < <(
    find "$packageDir" -maxdepth 1 -type f -name '*.dep' -print | sort
  )

  (( ${#depFiles[@]} > 1 )) || return 0

  printf 'Removing stale local package outputs for %s; found multiple depfiles.\n' \
    "$packageRelativePath" >&2

  while IFS= read -r stalePath; do
    rm -f -- "$stalePath"
  done < <(
    find "$packageDir" -maxdepth 1 -type f \
      \( -name '*.dep' -o -name '*.txz' -o -name '*.tgz' -o -name '*.tbz' -o -name '*.tlz' \) \
      -print | sort
  )
}

artifact_looks_like_python_package() {
  local artifactPath=$1

  tar -tf "$artifactPath" 2>/dev/null | grep -Eq \
    '(^|/)usr/lib(64)?/python[0-9.]+/|(^|/)(site-packages|dist-packages)/|\.dist-info/|\.egg-info/'
}

current_python_path_token() {
  command -v python3 >/dev/null 2>&1 || return 1

  python3 - <<'PY'
import sys
print(f"python{sys.version_info[0]}.{sys.version_info[1]}")
PY
}

python_artifact_matches_runtime() {
  local artifactPath=$1
  local currentPythonToken=""
  local recordedToken=""
  local -a recordedTokens=()

  artifact_looks_like_python_package "$artifactPath" || return 0

  currentPythonToken=$(current_python_path_token) || return 0

  while IFS= read -r recordedToken; do
    [[ -n "$recordedToken" ]] || continue
    recordedTokens+=("$recordedToken")
  done < <(
    tar -tf "$artifactPath" 2>/dev/null \
      | grep -Eo 'usr/lib(64)?/python[0-9]+\.[0-9]+/' \
      | sed -E 's|^usr/lib(64)?/(python[0-9]+\.[0-9]+)/$|\2|' \
      | sort -u
  )

  if (( ${#recordedTokens[@]} == 0 )); then
    return 0
  fi

  for recordedToken in "${recordedTokens[@]}"; do
    if [[ "$recordedToken" == "$currentPythonToken" ]]; then
      return 0
    fi
  done

  return 1
}

remove_stale_depfiles() {
  local packageDir=$1
  local packageName=$2
  local keepDepFile=$3
  local depFilePath=""

  # Keep the curated packageName.dep file, if present, and prune only older
  # artifact-style depfiles for the same package.

  while IFS= read -r depFilePath; do
    [[ "$depFilePath" == "$keepDepFile" ]] && continue
    rm -f -- "$depFilePath"
  done < <(
    find "$packageDir" -maxdepth 1 -type f -name "${packageName}-*.dep" -print | sort
  )
}

generate_depfile_for_artifact() {
  local packageDir=$1
  local packageName=$2
  local artifactPath=$3
  local depFilePath=""
  local depfinderFailed=false
  local fallbackDepFile=""
  local depfinderWorkDir=""
  local generatedDepFile=""
  local packageDepFile=""
  local -a generatedDependencies=()
  local -a mergedDependencies=()
  local -a packageDependencies=()
  local -a slkbuildDepends=()
  local slkbuildPath="${packageDir}/SLKBUILD"
  local tempDepFile=""

  depFilePath=$(depfile_path_for_artifact "$artifactPath")
  generatedDepFile="$(basename "$depFilePath")"
  tempDepFile="${depFilePath}.tmp"

  rm -f -- "$tempDepFile"
  depfinderWorkDir=$(mktemp -d "${TMPDIR:-/tmp}/depfinder.XXXXXX") \
    || die "failed to create depfinder workdir"
  if artifact_looks_like_python_package "$artifactPath"; then
    (
      cd "$depfinderWorkDir" || exit 1
      DEPFINDERNOEXIT=1 depfinder -p -f -3 "$artifactPath"
    ) || depfinderFailed=true
  else
    (
      cd "$depfinderWorkDir" || exit 1
      DEPFINDERNOEXIT=1 depfinder -f "$artifactPath"
    ) || depfinderFailed=true
  fi

  if [[ "$depfinderFailed" == true ]]; then
    rm -rf -- "$depfinderWorkDir"
    rm -f -- "$tempDepFile"
    fallbackDepFile=$(find_depfile "$packageDir" "$packageName" || true)
    if [[ -n "$fallbackDepFile" && -f "$fallbackDepFile" ]]; then
      printf 'Warning: depfinder failed for %s; using existing depfile %s\n' \
        "$(basename "$artifactPath")" "$(basename "$fallbackDepFile")" >&2
      printf '%s\n' "$fallbackDepFile"
      return
    fi

    die "depfinder failed for $(basename "$artifactPath")"
  fi

  if [[ ! -f "$depfinderWorkDir/$generatedDepFile" ]]; then
    rm -rf -- "$depfinderWorkDir"
    rm -f -- "$tempDepFile"
    die "depfinder did not create $(basename "$depFilePath")"
  fi

  mv -f -- "$depfinderWorkDir/$generatedDepFile" "$tempDepFile" \
    || die "failed to stage $(basename "$depFilePath")"
  rm -rf -- "$depfinderWorkDir"

  packageDepFile=$(find_curated_depfile "$packageDir" "$packageName" || true)
  if [[ -n "$packageDepFile" && -f "$packageDepFile" ]]; then
    read_dependencies "$packageDepFile" packageDependencies
  fi
  read_dependencies "$tempDepFile" generatedDependencies
  read_slkbuild_array "$slkbuildPath" depends slkbuildDepends
  append_unique_values mergedDependencies "${packageDependencies[@]}"
  append_unique_values mergedDependencies "${slkbuildDepends[@]}"
  append_unique_values mergedDependencies "${generatedDependencies[@]}"
  write_dependencies "$tempDepFile" "${mergedDependencies[@]}"

  remove_stale_depfiles "$packageDir" "$packageName" "$depFilePath"
  mv -f -- "$tempDepFile" "$depFilePath" || die "failed to write $(basename "$depFilePath")"

  printf 'Generated %s\n' "$(basename "$depFilePath")" >&2
  printf '%s\n' "$depFilePath"
}

install_artifact_path() {
  local artifactPath=$1
  [[ "$noInstall" == false ]] || return 0

  printf 'Installing %s\n' "$(basename "$artifactPath")"
  sudo upgradepkg --install-new "$artifactPath" >/dev/null \
    || die "Install failed for ${artifactPath}"
}

install_package() {
  local packageDir=$1
  local artifactPath=${builtArtifactByDir[${packageDir}]}

  install_artifact_path "$artifactPath"
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

staged_artifact_for_package() {
  local packageDir=$1
  local packageName=${packageNameByDir[${packageDir}]}
  local packageVersion=${packageVersionByDir[${packageDir}]:-}
  local packageRelease=${packageReleaseByDir[${packageDir}]:-}
  local stagedArtifactPattern=""

  if [[ -z "$packageVersion" ]]; then
    packageVersion=$(parse_slkbuild_scalar "${packageDir}/SLKBUILD" pkgver)
    packageVersionByDir["$packageDir"]=$packageVersion
  fi

  if [[ -z "$packageRelease" ]]; then
    packageRelease=$(parse_slkbuild_scalar "${packageDir}/SLKBUILD" pkgrel)
    packageReleaseByDir["$packageDir"]=$packageRelease
  fi

  stagedArtifactPattern="${packageName}-${packageVersion}-*-${packageRelease}"
  latest_matching_file "$stagingDir" "$stagedArtifactPattern"
}

filter_staged_packages() {
  local packageDir=""
  local packageName=""
  local stagedArtifactPath=""
  local -a filteredQueue=()

  [[ "$skipStaged" == true || "$fullBuild" == true ]] || return 0

  for packageDir in "${buildQueue[@]}"; do
    packageName=${packageNameByDir[${packageDir}]}
    stagedArtifactPath=$(staged_artifact_for_package "$packageDir")
    if [[ -n "$stagedArtifactPath" ]]; then
      if ! python_artifact_matches_runtime "$stagedArtifactPath"; then
        printf 'Ignoring stale Python staged artifact for %s; it targets a different Python runtime: %s\n' \
          "${packageDirByRelative[${packageDir}]}" "$(basename "$stagedArtifactPath")"
        filteredQueue+=("$packageDir")
        continue
      fi
      printf 'Skipping %s; matching staged artifact already exists: %s\n' \
        "${packageDirByRelative[${packageDir}]}" "$(basename "$stagedArtifactPath")"
      reusedStagedArtifactByDir["$packageDir"]=$stagedArtifactPath
      reusedStagedQueue+=("$packageDir")
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
  [[ "${BUILD_PACKAGE_SUDO_READY:-}" == "1" ]] && return 0

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
buildAllPackages=false
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
declare -a reusedStagedQueue=()
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
declare -A packageVersionByDir=()
declare -A packageReleaseByDir=()
declare -A builtArtifactByDir=()
declare -A builtDepfileByDir=()
declare -A reusedStagedArtifactByDir=()

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
  if [[ "$resetStaging" == true && "$dependenciesOnly" == false && "$fullBuild" == false ]]; then
    ensure_staging_dir
    reset_staging_dir
    printf 'Removed staged artifacts from %s\n' "$stagingDir"
    exit 0
  fi

  if [[ "$fullBuild" == true && "$onlyTarget" == false ]]; then
    buildAllPackages=true
  else
    show_usage
    exit 2
  fi
fi

if [[ "$buildAllPackages" == true && ${#skippedPackages[@]} -gt 0 ]]; then
  printf 'Full repository build requested; skipped packages are treated as already installed.\n'
fi

if [[ "$buildAllPackages" == false && -z "$packagePath" ]]; then
  show_usage
  exit 2
fi

trap cleanup EXIT INT TERM HUP

if [[ "$dependenciesOnly" == false ]]; then
  require_cmd fakeroot
  require_cmd slkbuild
  require_cmd depfinder

  if [[ "$noInstall" == false ]]; then
    require_cmd sudo
    require_cmd upgradepkg
  fi
fi

if [[ "$onlyTarget" == false && ( "$dependenciesOnly" == false || "$buildAllPackages" == true ) ]]; then
  [[ -d "$installedDbDir" ]] || die "Installed package database not found at ${installedDbDir}; run this on the Slackware/Slint VM"
fi

if [[ "$buildAllPackages" == false ]]; then
  packagePath=$(normalize_repo_path "$packagePath")
  packageDir="${repoRoot}/${packagePath}"
  [[ -f "${packageDir}/SLKBUILD" ]] || die "SLKBUILD not found for package: ${packagePath}"
else
  packageDir=""
fi

if [[ "$dependenciesOnly" == true ]]; then
  build_repo_index
  build_legacy_index
  if [[ "$buildAllPackages" == true ]]; then
    collect_full_build_queue
    printf 'Full repository build queue:\n'
    for packageDir in "${buildQueue[@]}"; do
      printf '  %s\n' "${packageDirByRelative[${packageDir}]}"
    done
  else
    packageNameByDir["$packageDir"]=$(parse_pkgname "${packageDir}/SLKBUILD")
    packageDirByRelative["$packageDir"]=$packagePath
    collect_dependency_closure "$packageDir" "${packageNameByDir[${packageDir}]}"
    printf 'Dependencies for %s:\n' "$packagePath"
    for dependencyName in "${dependencyOutput[@]}"; do
      printf '  %s\n' "$dependencyName"
    done
  fi
  exit 0
elif [[ "$onlyTarget" == true ]]; then
  packageNameByDir["$packageDir"]=$(parse_pkgname "${packageDir}/SLKBUILD")
  packageDirByRelative["$packageDir"]=$packagePath
  buildQueue=("$packageDir")
else
  build_repo_index
  build_legacy_index

  if [[ "$buildAllPackages" == false ]]; then
    [[ -n "${packageNameByDir[${packageDir}]:-}" ]] || die "package directory was not indexed as an SLKBUILD package: ${packagePath}"
    if skip_requested "${packageNameByDir[${packageDir}]}"; then
      die "target package ${packageNameByDir[${packageDir}]} cannot be skipped"
    fi
  fi
fi

ensure_staging_dir
if [[ "$resetStaging" == true ]]; then
  reset_staging_dir
fi
if [[ "$onlyTarget" == false ]]; then
  if [[ "$buildAllPackages" == true ]]; then
    collect_full_build_queue
    (( ${#buildQueue[@]} > 0 )) || die "no packages were selected to build"
  else
    visit_package "$packageDir"
    (( ${#buildQueue[@]} > 0 )) || die "no packages were selected to build for ${packagePath}"
  fi
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

for packageDir in "${reusedStagedQueue[@]}"; do
  install_artifact_path "${reusedStagedArtifactByDir[${packageDir}]}"
done

for packageDir in "${buildQueue[@]}"; do
  build_package "$packageDir"
  stage_artifacts "$packageDir"
  install_package "$packageDir"
done

printf 'Built %s package(s). Staged artifacts in %s\n' "${#buildQueue[@]}" "$stagingDir"
