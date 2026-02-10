#!/usr/bin/env bash
# Slint repository management

# Your username for rsync access
userName=""

# Your password for rsync access
password=""

# your preferred editor if not set $EDITOR will be used or nano if not set
editor=""

# Regenerate metadata for all repo roots regardless of detected package changes
forceRegenMetadata="yes"

# Change this if you want a different directory for repository management
repoDir="slint-repo"

# Remote mirror details
remoteHost="slackware.uk"
mirror="slint"

# GPG configuration
gpgBin="gpg"
gpgKeyId=""

# If yes, fail when an existing signature (.asc) has no matching target file
failOnMissingSignedTarget="no"

# If yes, fail when a signature cannot be verified due to missing public key
failOnMissingSignatureKey="no"

# If yes, attempt to import missing public keys automatically
autoImportMissingKeys="no"

# Keyserver to use when importing missing public keys
keyServer="keys.openpgp.org"

# If yes, confirm before importing keys
confirmKeyImport="yes"

# If yes, treat expired signature keys as warnings instead of failures
allowExpiredSignatures="no"

# If yes, prompt to replace expired signatures with the current key
promptExpiredSignatures="yes"

# If yes, include /source/ signatures when prompting to replace expired signatures
includeUpstreamExpiredSignatures="no"

# If yes, prompt to replace bad signatures with the current key
promptBadSignatures="yes"

# If yes, include /source/ signatures when prompting to replace bad signatures
includeUpstreamBadSignatures="yes"

# ---------- NO EDITS REQUIRED BELOW THIS LINE ----------

# Function section

select_gpg_key() {
    local -a keyLabels=()
    local -a keyOptions=()
    local selectedKey=""
    local selectedKeyId=""
    local originalColumns=""

    mapfile -t keyLabels < <(
        "${gpgBin}" --list-secret-keys --with-colons --keyid-format long 2>/dev/null | awk -F: '
            $1 == "sec" {
                if (key != "") {
                    print key " - (no uid)"
                }
                key = $5
                uid = ""
                next
            }
            $1 == "uid" && uid == "" {
                uid = $10
                if (key != "") {
                    if (uid == "") {
                        uid = "(no uid)"
                    }
                    print key " - " uid
                    key = ""
                    uid = ""
                }
            }
            END {
                if (key != "") {
                    print key " - (no uid)"
                }
            }
        '
    )

    if [[ ${#keyLabels[@]} -eq 0 ]]; then
        echo "No GPG secret keys were found."
        echo "Create one with:"
        echo "  gpg --full-generate-key"
        echo "Then rerun ${0##*/}."
        exit 1
    fi

    if [[ -n "${gpgKeyId}" ]]; then
        if ! "${gpgBin}" --list-secret-keys --with-colons --keyid-format long 2>/dev/null | awk -F: '$1 == "sec" { print $5 }' | grep -Fxq "${gpgKeyId}"; then
            echo "Requested GPG key ${gpgKeyId} was not found."
            exit 1
        fi
        return 0
    fi

    if [[ ${#keyLabels[@]} -eq 1 ]]; then
        gpgKeyId=${keyLabels[0]%% *}
        echo "Using GPG key ${gpgKeyId}."
        return 0
    fi

    keyOptions=("${keyLabels[@]}" "Exit")
    originalColumns=${COLUMNS-}
    COLUMNS=1 # Much nicer for screen reader users
    PS3="Select GPG key or choose Exit: "
    select selectedKey in "${keyOptions[@]}"; do
        if [[ -z "${selectedKey}" || "${selectedKey}" == "Exit" ]]; then
            exit 0
        fi
        selectedKeyId=${selectedKey%% *}
        gpgKeyId=${selectedKeyId}
        break
    done
    if [[ -n "${originalColumns}" ]]; then
        COLUMNS="${originalColumns}"
    else
        unset COLUMNS
    fi
}

sign_file() {
    local targetFile=$1
    local gpgArgs=(
        --yes
        --armor
        --detach-sign
        --output "${targetFile}.asc"
    )
    if [[ -n "${gpgKeyId}" ]]; then
        gpgArgs+=(--default-key "${gpgKeyId}")
    fi
    "${gpgBin}" "${gpgArgs[@]}" "${targetFile}"
}

sign_existing_signatures() {
    local ascFile
    local baseFile
    local signedCount=0
    local updatedCount=0
    local missingCount=0

    while IFS= read -r -d '' ascFile; do
        baseFile=${ascFile%.asc}
        if [[ ! -f "${baseFile}" ]]; then
            echo "Missing target file for signature ${ascFile}"
            missingCount=$((missingCount + 1))
            continue
        fi
        if [[ "${baseFile}" -nt "${ascFile}" ]]; then
            echo "Signing ${baseFile}..."
            if ! sign_file "${baseFile}"; then
                echo "Failed to sign ${baseFile}"
                return 1
            fi
            updatedCount=$((updatedCount + 1))
        fi
        signedCount=$((signedCount + 1))
    done < <(find . -type f -name '*.asc' -print0)

    if [[ "${signedCount}" -eq 0 ]]; then
        echo "No existing .asc files found to refresh."
    else
        echo "Checked ${signedCount} existing signatures; updated ${updatedCount}."
    fi

    if [[ "${missingCount}" -gt 0 ]]; then
        if [[ "${failOnMissingSignedTarget}" == "yes" ]]; then
            echo "Missing ${missingCount} signed file(s). Fix and rerun."
            return 1
        fi
        echo "Missing ${missingCount} signed file(s); skipped."
    fi
}

verify_existing_signatures() {
    local ascFile
    local baseFile
    local verifiedCount=0
    local failedCount=0
    local missingCount=0
    local missingKeyCount=0
    local expiredCount=0
    local missingKeyId=""
    local statusOutput=""
    local -A missingKeyIds=()
    local -a failedSignatureFiles=()
    local -a failedSignatureReasons=()
    local -a badSignatureFiles=()
    declare -ga badSignatureFilesGlobal=()
    badSignatureFilesGlobal=()

    declare -ga missingSignatureKeys=()
    missingSignatureKeys=()
    declare -ga expiredSignatureFiles=()
    expiredSignatureFiles=()

    while IFS= read -r -d '' ascFile; do
        baseFile=${ascFile%.asc}
        if [[ ! -f "${baseFile}" ]]; then
            echo "Missing target file for signature ${ascFile}"
            missingCount=$((missingCount + 1))
            continue
        fi
        statusOutput=$("${gpgBin}" --status-fd 1 --verify "${ascFile}" "${baseFile}" 2>/dev/null || true)
        if grep -q '^\[GNUPG:\] GOODSIG ' <<< "${statusOutput}"; then
            if grep -q '^\[GNUPG:\] EXPKEYSIG ' <<< "${statusOutput}" || grep -q '^\[GNUPG:\] EXPSIG ' <<< "${statusOutput}" || grep -q '^\[GNUPG:\] SIGEXPIRED ' <<< "${statusOutput}"; then
                expiredCount=$((expiredCount + 1))
                expiredSignatureFiles+=("${ascFile}")
                if [[ "${allowExpiredSignatures}" == "yes" || "${promptExpiredSignatures}" == "yes" ]]; then
                    echo "Signature valid but expired key: ${ascFile}"
                    verifiedCount=$((verifiedCount + 1))
                else
                    echo "Signature expired: ${ascFile}"
                    failedCount=$((failedCount + 1))
                fi
            else
                verifiedCount=$((verifiedCount + 1))
            fi
            continue
        fi
        if grep -q '^\[GNUPG:\] NO_PUBKEY ' <<< "${statusOutput}"; then
            missingKeyId=$(awk '/^\[GNUPG:\] NO_PUBKEY /{print $3; exit}' <<< "${statusOutput}")
            if [[ -n "${missingKeyId}" ]]; then
                missingKeyIds["${missingKeyId}"]=1
            fi
            echo "Signature missing public key: ${ascFile}"
            missingKeyCount=$((missingKeyCount + 1))
            continue
        fi
        if grep -q '^\[GNUPG:\] EXPKEYSIG ' <<< "${statusOutput}" || grep -q '^\[GNUPG:\] EXPSIG ' <<< "${statusOutput}" || grep -q '^\[GNUPG:\] SIGEXPIRED ' <<< "${statusOutput}"; then
            expiredCount=$((expiredCount + 1))
            expiredSignatureFiles+=("${ascFile}")
            if [[ "${allowExpiredSignatures}" == "yes" || "${promptExpiredSignatures}" == "yes" ]]; then
                echo "Signature valid but expired key: ${ascFile}"
                verifiedCount=$((verifiedCount + 1))
            else
                echo "Signature expired: ${ascFile}"
                failedCount=$((failedCount + 1))
            fi
            continue
        fi
        if grep -q '^\[GNUPG:\] BADSIG ' <<< "${statusOutput}"; then
            echo "Signature verification failed (bad signature): ${ascFile}"
            failedCount=$((failedCount + 1))
            failedSignatureFiles+=("${ascFile}")
            failedSignatureReasons+=("bad signature")
            badSignatureFiles+=("${ascFile}")
            continue
        fi
        if grep -q '^\[GNUPG:\] REVKEYSIG ' <<< "${statusOutput}" || grep -q '^\[GNUPG:\] KEYREVOKED ' <<< "${statusOutput}"; then
            echo "Signature verification failed (revoked key): ${ascFile}"
            failedCount=$((failedCount + 1))
            failedSignatureFiles+=("${ascFile}")
            failedSignatureReasons+=("revoked key")
            continue
        fi
        echo "Signature verification failed: ${ascFile}"
        failedCount=$((failedCount + 1))
        failedSignatureFiles+=("${ascFile}")
        failedSignatureReasons+=("unknown error")
    done < <(find . -type f -name '*.asc' -print0)

    if [[ "${verifiedCount}" -eq 0 ]]; then
        echo "No existing .asc files found to verify."
    else
        echo "Verified ${verifiedCount} signatures."
    fi

    if ((${#missingKeyIds[@]} > 0)); then
        mapfile -t missingSignatureKeys < <(printf '%s\n' "${!missingKeyIds[@]}" | sort)
        echo "Missing public key(s) for signatures:"
        printf '%s\n' "${missingSignatureKeys[@]}"
    fi
    if [[ "${expiredCount}" -gt 0 ]]; then
        if [[ "${allowExpiredSignatures}" == "yes" || "${promptExpiredSignatures}" == "yes" ]]; then
            echo "Accepted ${expiredCount} expired signature(s)."
        else
            echo "Found ${expiredCount} expired signature(s)."
        fi
    fi

    if [[ "${failedCount}" -gt 0 ]]; then
        echo "Signature verification failures:"
        for idx in "${!failedSignatureFiles[@]}"; do
            echo "${failedSignatureFiles[$idx]} - ${failedSignatureReasons[$idx]}"
        done
        echo "Signature verification had ${failedCount} failure(s)."
        if ((${#badSignatureFiles[@]} > 0)); then
            declare -ga badSignatureFilesGlobal=()
            badSignatureFilesGlobal=("${badSignatureFiles[@]}")
        fi
        return 1
    fi
    if [[ "${missingKeyCount}" -gt 0 ]]; then
        if [[ "${failOnMissingSignatureKey}" == "yes" ]]; then
            echo "Signature verification missing ${missingKeyCount} public key(s)."
            return 1
        fi
        echo "Signature verification skipped ${missingKeyCount} signature(s) due to missing public key(s)."
    fi
    if [[ "${missingCount}" -gt 0 ]]; then
        if [[ "${failOnMissingSignedTarget}" == "yes" ]]; then
            echo "Signature verification had ${missingCount} missing file(s)."
            return 1
        fi
        echo "Signature verification skipped ${missingCount} missing file(s)."
    fi
}

prompt_orphan_signature_review() {
    local ascFile=""
    local baseFile=""
    local -a orphanAscFiles=()

    while IFS= read -r -d '' ascFile; do
        baseFile=${ascFile%.asc}
        if [[ ! -f "${baseFile}" ]]; then
            orphanAscFiles+=("${ascFile}")
        fi
    done < <(find . -type f -name '*.asc' -print0)

    if ((${#orphanAscFiles[@]} == 0)); then
        return 0
    fi

    echo "Found ${#orphanAscFiles[@]} orphaned signature file(s):"
    printf '%s\n' "${orphanAscFiles[@]}"
    read -r -p "Review orphaned signatures above. Remove if desired, then press enter to continue."
}

is_upstream_signature() {
    local ascFile=$1
    [[ "${ascFile}" == *"/source/"* ]]
}

prompt_expired_signature_resign() {
    local ascFile=""
    local baseFile=""
    local reply=""
    local -a eligibleExpired=()

    if ((${#expiredSignatureFiles[@]} == 0)); then
        return 0
    fi

    for ascFile in "${expiredSignatureFiles[@]}"; do
        if [[ "${includeUpstreamExpiredSignatures}" != "yes" ]] && is_upstream_signature "${ascFile}"; then
            continue
        fi
        eligibleExpired+=("${ascFile}")
    done

    if ((${#eligibleExpired[@]} == 0)); then
        return 0
    fi

    echo "Expired signatures can be replaced with your current key."
    echo "Note: Replacing upstream signatures changes provenance."
    echo "Expired signature file(s) eligible for replacement:"
    printf '%s\n' "${eligibleExpired[@]}"

    if [[ "${promptExpiredSignatures}" != "yes" ]]; then
        return 0
    fi

    while true; do
        read -r -p "Replace expired signatures with your key? (yes/no): " reply
        case "${reply,,}" in
            y|yes)
                for ascFile in "${eligibleExpired[@]}"; do
                    baseFile=${ascFile%.asc}
                    if [[ ! -f "${baseFile}" ]]; then
                        echo "Skipping missing target for ${ascFile}"
                        continue
                    fi
                    echo "Replacing signature for ${baseFile}"
                    if ! sign_file "${baseFile}"; then
                        echo "Failed to sign ${baseFile}"
                        return 1
                    fi
                done
                return 0
                ;;
            n|no)
                return 2
                ;;
            *)
                echo "Please answer yes or no."
                ;;
        esac
    done
}

prompt_bad_signature_resign() {
    local ascFile=""
    local baseFile=""
    local reply=""
    local -a eligibleBad=()

    if ((${#badSignatureFilesGlobal[@]} == 0)); then
        return 0
    fi

    for ascFile in "${badSignatureFilesGlobal[@]}"; do
        if [[ "${includeUpstreamBadSignatures}" != "yes" ]] && is_upstream_signature "${ascFile}"; then
            continue
        fi
        eligibleBad+=("${ascFile}")
    done

    if ((${#eligibleBad[@]} == 0)); then
        echo "Bad signatures were found but are excluded by current settings."
        echo "Set includeUpstreamBadSignatures=\"yes\" to allow replacement."
        return 2
    fi

    echo "Bad signatures can be replaced with your current key."
    echo "Note: Replacing upstream signatures changes provenance."
    echo "Bad signature file(s) eligible for replacement:"
    printf '%s\n' "${eligibleBad[@]}"

    if [[ "${promptBadSignatures}" != "yes" ]]; then
        return 2
    fi

    while true; do
        read -r -p "Replace bad signatures with your key? (yes/no): " reply
        case "${reply,,}" in
            y|yes)
                for ascFile in "${eligibleBad[@]}"; do
                    baseFile=${ascFile%.asc}
                    if [[ ! -f "${baseFile}" ]]; then
                        echo "Skipping missing target for ${ascFile}"
                        continue
                    fi
                    echo "Replacing signature for ${baseFile}"
                    if ! sign_file "${baseFile}"; then
                        echo "Failed to sign ${baseFile}"
                        return 1
                    fi
                done
                return 0
                ;;
            n|no)
                return 2
                ;;
            *)
                echo "Please answer yes or no."
                ;;
        esac
    done
}

handle_bad_signature_failures() {
    if [[ "${promptBadSignatures}" != "yes" ]]; then
        return 1
    fi
    if ((${#badSignatureFilesGlobal[@]} == 0)); then
        return 1
    fi
    if prompt_bad_signature_resign; then
        return 0
    fi
    echo "Bad signatures remain. Resolve or re-run."
    return 1
}

import_missing_signature_keys() {
    local -a missingKeys=("$@")
    local reply=""

    if ((${#missingKeys[@]} == 0)); then
        return 0
    fi

    echo "Missing public key(s) for signature verification:"
    printf '%s\n' "${missingKeys[@]}"

    if [[ "${confirmKeyImport}" == "yes" ]]; then
        while true; do
            read -r -p "Import missing keys from ${keyServer}? (yes/no): " reply
            case "${reply,,}" in
                y|yes)
                    break
                    ;;
                n|no)
                    echo "Skipping key import."
                    return 0
                    ;;
                *)
                    echo "Please answer yes or no."
                    ;;
            esac
        done
    fi

    if ! "${gpgBin}" --keyserver "${keyServer}" --recv-keys "${missingKeys[@]}"; then
        echo "Key import failed. You may need to import keys manually."
        return 1
    fi
}

discover_repo_roots() {
    # Repo roots are directories that have a PACKAGES.TXT at shallow depth.
    declare -ga repoRoots=()
    while IFS= read -r -d '' pkgFile; do
        local root=${pkgFile%/PACKAGES.TXT}
        root=${root#./}
        repoRoots+=("${root}")
    done < <(find . -maxdepth 3 -type f -name 'PACKAGES.TXT' -print0 | sort -z)

    if ((${#repoRoots[@]} == 0)); then
        echo "No PACKAGES.TXT files were found."
        exit 1
    fi
}

load_package_base_dirs() {
    # Map repo root -> base dirs that actually contain packages.
    declare -gA packageBaseDirsByRoot=()

    local root=""
    local pkgFile=""
    local line=""
    local location=""
    local baseDir=""
    local -A seenBase=()
    local -a baseDirs=()
    # Unique list of base dirs derived from PACKAGES.TXT.
    local -a uniqueBaseDirs=()

    for root in "${repoRoots[@]}"; do
        pkgFile="${root}/PACKAGES.TXT"
        baseDirs=()
        uniqueBaseDirs=()
        seenBase=()

        if [[ -f "${pkgFile}" ]]; then
            while IFS= read -r line; do
                [[ "${line}" == "PACKAGE LOCATION:"* ]] || continue
                location=${line#PACKAGE LOCATION:  }
                location=${location#./}
                baseDir=${location%%/*}
                if [[ -n "${baseDir}" ]]; then
                    baseDirs+=("${baseDir}")
                fi
            done < "${pkgFile}"
        fi

        for baseDir in "${baseDirs[@]}"; do
            if [[ -z "${seenBase[${baseDir}]-}" ]]; then
                seenBase["${baseDir}"]=1
                uniqueBaseDirs+=("${baseDir}")
            fi
        done

        if ((${#uniqueBaseDirs[@]} == 0)); then
            [[ -d "${root}/packages" ]] && uniqueBaseDirs+=("packages")
            [[ -d "${root}/slint" ]] && uniqueBaseDirs+=("slint")
        fi

        packageBaseDirsByRoot["${root}"]="${uniqueBaseDirs[*]}"
    done
}

list_package_files_for_root() {
    local root=$1
    local baseDirsString=${packageBaseDirsByRoot[${root}]-}
    local -a baseDirs=()
    local baseDir=""

    IFS=' ' read -r -a baseDirs <<< "${baseDirsString}"
    for baseDir in "${baseDirs[@]}"; do
        [[ -d "${root}/${baseDir}" ]] || continue
        find "${root}/${baseDir}" \
            -type d \( -path '*/.git' -o -path '*/.rsync-tmp' -o -path '*/previous' -o -path '*/iso' -o -path '*/source' \) -prune -o \
            -type f -name '*.t?z' -print0
    done
}

gather_package_files_for_root() {
    local root=$1
    local -a files=()

    while IFS= read -r -d '' filePath; do
        files+=("${filePath}")
    done < <(list_package_files_for_root "${root}")

    if ((${#files[@]} == 0)); then
        return 0
    fi

    printf '%s\0' "${files[@]}" | sort -z
}

parse_package_fields() {
    local pkgPath=$1
    local pkgFile=${pkgPath##*/}
    local pkgBase=${pkgFile%.*}
    local -a pkgParts=()
    local partCount=0
    local build=""
    local arch=""
    local version=""
    local name=""

    IFS='-' read -r -a pkgParts <<< "${pkgBase}"
    partCount=${#pkgParts[@]}
    if (( partCount < 4 )); then
        return 1
    fi

    build=${pkgParts[$((partCount - 1))]}
    arch=${pkgParts[$((partCount - 2))]}
    version=${pkgParts[$((partCount - 3))]}
    name=$(IFS='-'; echo "${pkgParts[*]:0:$((partCount - 3))}")

    printf '%s|%s|%s|%s\n' "${name}" "${version}" "${arch}" "${build}"
}

version_is_newer() {
    local candidateVersion=$1
    local currentVersion=$2
    local newestVersion=""

    if [[ -z "${currentVersion}" ]]; then
        return 0
    fi
    if [[ "${candidateVersion}" == "${currentVersion}" ]]; then
        return 1
    fi
    newestVersion=$(printf '%s\n%s\n' "${candidateVersion}" "${currentVersion}" | sort -V | tail -n1)
    [[ "${newestVersion}" == "${candidateVersion}" ]]
}

log_path_for_file() {
    # Produce ChangeLog-style paths (strip repo root and base dir).
    local root=$1
    local filePath=$2
    local relPath=${filePath#"${root}"/}
    local baseDirsString=${packageBaseDirsByRoot[${root}]-}
    local -a baseDirs=()
    local baseDir=""

    IFS=' ' read -r -a baseDirs <<< "${baseDirsString}"
    for baseDir in "${baseDirs[@]}"; do
        if [[ "${relPath}" == "${baseDir}/"* ]]; then
            relPath=${relPath#"${baseDir}"/}
            break
        fi
    done

    printf '%s\n' "${relPath}"
}

remove_package_and_sidecars() {
    # Remove package and its related sidecar files in the same directory.
    local pkgFile=$1
    local basePath=${pkgFile%.*}
    local -a sidecarExtensions=(
        asc
        con
        dep
        desc
        lst
        md5
        meta
        sug
        txt
    )
    local ext=""

    echo "Removing old package ${pkgFile}..."
    rm -f -- "${pkgFile}"
    for ext in "${sidecarExtensions[@]}"; do
        rm -f -- "${basePath}.${ext}"
    done
}

build_package_map() {
    local mapPrefix=$1
    local -n versions="${mapPrefix}Versions"
    # shellcheck disable=SC2178
    local -n files="${mapPrefix}Files"
    # shellcheck disable=SC2178
    local -n roots="${mapPrefix}Roots"
    local pkg=""
    local parsed=""
    local name=""
    local version=""
    local arch=""
    local build=""
    local key=""
    local versionBuild=""
    local root=""

    # Reset target maps for this build.
    versions=()
    files=()
    roots=()

    for root in "${repoRoots[@]}"; do
        while IFS= read -r -d '' pkg; do
            parsed=$(parse_package_fields "${pkg}") || continue
            IFS='|' read -r name version arch build <<< "${parsed}"
            key="${root}|${name}|${arch}"
            versionBuild="${version}-${build}"
            if version_is_newer "${versionBuild}" "${versions[${key}]}" ; then
                versions["${key}"]="${versionBuild}"
                # shellcheck disable=SC2034
                files["${key}"]="${pkg}"
                # shellcheck disable=SC2034
                roots["${key}"]="${root}"
            fi
        done < <(gather_package_files_for_root "${root}")
    done
}

remove_old_packages() {
    # Remove older versions only when a newer version appears.
    local key=""
    local currentFile=""
    local currentVersion=""
    local baselineVersion=""
    local parsed=""
    local name=""
    local version=""
    local arch=""
    local build=""
    local currentVersionBuild=""
    local dirName=""
    local pkg=""
    local pkgName=""
    local pkgVersion=""
    local pkgArch=""
    local pkgBuild=""
    local pkgVersionBuild=""
    local removedCount=0
    local -A removedFiles=()

    for key in "${!currentVersions[@]}"; do
        baselineVersion=${baselineVersions[${key}]-}
        currentVersion=${currentVersions[${key}]}
        if [[ -z "${baselineVersion}" || "${baselineVersion}" == "${currentVersion}" ]]; then
            continue
        fi

        currentFile=${currentFiles[${key}]}
        parsed=$(parse_package_fields "${currentFile}") || continue
        IFS='|' read -r name version arch build <<< "${parsed}"
        currentVersionBuild="${version}-${build}"
        dirName=$(dirname "${currentFile}")

        while IFS= read -r -d '' pkg; do
            parsed=$(parse_package_fields "${pkg}") || continue
            IFS='|' read -r pkgName pkgVersion pkgArch pkgBuild <<< "${parsed}"
            if [[ "${pkgName}" != "${name}" || "${pkgArch}" != "${arch}" ]]; then
                continue
            fi
            pkgVersionBuild="${pkgVersion}-${pkgBuild}"
            if [[ "${pkgVersionBuild}" == "${currentVersionBuild}" ]]; then
                continue
            fi
            if [[ -z "${removedFiles[${pkg}]-}" ]]; then
                remove_package_and_sidecars "${pkg}"
                removedFiles["${pkg}"]=1
                removedCount=$((removedCount + 1))
            fi
        done < <(find "${dirName}" -maxdepth 1 -type f -name '*.t?z' -print0)
    done

    echo "Removed ${removedCount} old package(s)."
}

collect_changes() {
    # Build ChangeLog entries and track which repo roots changed.
    declare -gA addedByRoot=()
    declare -gA upgradedByRoot=()
    declare -gA removedByRoot=()
    declare -gA changedRoots=()
    declare -ga changedRootsList=()

    local key=""
    local root=""
    local filePath=""
    local logPath=""

    for key in "${!currentVersions[@]}"; do
        if [[ -z "${baselineVersions[${key}]-}" ]]; then
            root="${currentRoots[${key}]}"
            filePath="${currentFiles[${key}]}"
            logPath=$(log_path_for_file "${root}" "${filePath}")
            addedByRoot["${root}"]+=$(printf '%s\n' "${logPath}")
            changedRoots["${root}"]=1
        elif [[ "${baselineVersions[${key}]}" != "${currentVersions[${key}]}" ]]; then
            root="${currentRoots[${key}]}"
            filePath="${currentFiles[${key}]}"
            logPath=$(log_path_for_file "${root}" "${filePath}")
            upgradedByRoot["${root}"]+=$(printf '%s\n' "${logPath}")
            changedRoots["${root}"]=1
        fi
    done

    for key in "${!baselineVersions[@]}"; do
        if [[ -z "${currentVersions[${key}]-}" ]]; then
            root="${baselineRoots[${key}]}"
            filePath="${baselineFiles[${key}]}"
            logPath=$(log_path_for_file "${root}" "${filePath}")
            removedByRoot["${root}"]+=$(printf '%s\n' "${logPath}")
            changedRoots["${root}"]=1
        fi
    done

    for root in "${!changedRoots[@]}"; do
        changedRootsList+=("${root}")
    done
    if ((${#changedRootsList[@]} > 0)); then
        mapfile -t changedRootsList < <(printf '%s\n' "${changedRootsList[@]}" | sort)
    fi
}

build_changelog_lines() {
    local statusPadding=$1
    local statusText=$2
    local line=""

    while IFS= read -r line; do
        [[ -n "${line}" ]] || continue
        printf '%s:%s%s\n' "${line}" "${statusPadding}" "${statusText}"
    done
}

prepend_to_file() {
    local targetFile=$1
    local content=$2
    local tempFile=""

    tempFile=$(mktemp)
    printf '%s' "${content}" > "${tempFile}"
    cat "${targetFile}" >> "${tempFile}"
    mv "${tempFile}" "${targetFile}"
}

update_changelogs() {
    # Use existing ChangeLog spacing and separator style when possible.
    local entryDate=""
    local -a changelogFiles=()
    local root=""
    local changelogFile=""
    local entryLines=""
    local entryText=""
    local statusPadding=""
    local separatorLine=""
    local addedLines=""
    local upgradedLines=""
    local removedLines=""

    entryDate=$(LC_ALL=C date '+%A %e %B %Y')

    for root in "${changedRootsList[@]}"; do
        changelogFile="${root}/ChangeLog.txt"
        if [[ ! -f "${changelogFile}" ]]; then
            echo "ChangeLog.txt not found in ${root}; skipping."
            continue
        fi

        statusPadding=$(awk 'match($0, /:([ ]*)(Added|Upgraded|Removed)\./, m) { print m[1]; exit }' "${changelogFile}")
        if [[ -z "${statusPadding}" ]]; then
            statusPadding=" "
        fi
        separatorLine=$(awk 'match($0, /^\\+[-]+\\+$/, m) { print $0; exit }' "${changelogFile}")
        if [[ -z "${separatorLine}" ]]; then
            separatorLine="+-------------------------+"
        fi

        addedLines=$(printf '%s' "${addedByRoot[${root}]-}" | sed '/^$/d' | sort)
        upgradedLines=$(printf '%s' "${upgradedByRoot[${root}]-}" | sed '/^$/d' | sort)
        removedLines=$(printf '%s' "${removedByRoot[${root}]-}" | sed '/^$/d' | sort)

        entryLines=$(
            build_changelog_lines "${statusPadding}" "Added." <<< "${addedLines}"
            build_changelog_lines "${statusPadding}" "Upgraded." <<< "${upgradedLines}"
            build_changelog_lines "${statusPadding}" "Removed." <<< "${removedLines}"
        )

        if [[ -z "${entryLines}" ]]; then
            continue
        fi

        entryText=$(printf '%s\n%s\n%s\n' "${entryDate}" "${entryLines}" "${separatorLine}")
        prepend_to_file "${changelogFile}" "${entryText}"
        changelogFiles+=("${changelogFile}")
    done

    if ((${#changelogFiles[@]} == 0)); then
        echo "No ChangeLog updates were needed."
        return 0
    fi

    for changelogFile in "${changelogFiles[@]}"; do
        "${editor}" "${changelogFile}"
    done
}

package_relative_path() {
    local root=$1
    local filePath=$2

    printf '%s\n' "${filePath#"${root}"/}"
}

package_location_for_file() {
    local root=$1
    local filePath=$2
    local relDir=""

    relDir=${filePath#"${root}"/}
    relDir=${relDir%/*}
    printf './%s\n' "${relDir}"
}

decompress_package_stream() {
    # Stream package contents to stdout based on archive extension.
    local pkgFile=$1
    local ext=${pkgFile##*.}

    case "${ext}" in
        tgz)
            gzip -dc "${pkgFile}"
            ;;
        txz)
            xz -dc "${pkgFile}"
            ;;
        tbz)
            bzip2 -dc "${pkgFile}"
            ;;
        tlz)
            if command -v lzma >/dev/null 2>&1; then
                lzma -dc "${pkgFile}"
            elif command -v lzip >/dev/null 2>&1; then
                lzip -dc "${pkgFile}"
            else
                return 1
            fi
            ;;
        *)
            return 1
            ;;
    esac
}

extract_slack_desc() {
    local pkgFile=$1
    local descContent=""

    if ! descContent=$(decompress_package_stream "${pkgFile}" | tar -xO install/slack-desc 2>/dev/null); then
        return 1
    fi

    printf '%s\n' "${descContent}" | sed -n '/^#/d;/:/p'
}

package_compressed_k() {
    local pkgFile=$1

    du -s "${pkgFile}" | awk '{print $1}'
}

package_uncompressed_k() {
    local pkgFile=$1
    local ext=${pkgFile##*.}
    local uncompressedBytes=""

    if [[ "${ext}" == "tgz" ]]; then
        uncompressedBytes=$(gzip -l "${pkgFile}" | tail -1 | awk '{print $2}')
    else
        uncompressedBytes=$(decompress_package_stream "${pkgFile}" | wc -c)
    fi

    printf '%s\n' "$((uncompressedBytes / 1024))"
}

generate_txt_file() {
    # Create .txt description from install/slack-desc when needed.
    local pkgFile=$1
    local txtFile=$2
    local pkgName=${pkgFile##*/}

    if [[ ! -f "${txtFile}" || "${pkgFile}" -nt "${txtFile}" ]]; then
        echo "--> Generating .txt file for ${pkgName}"
        if ! extract_slack_desc "${pkgFile}" > "${txtFile}"; then
            echo "Failed to extract slack-desc for ${pkgName}"
            return 1
        fi
    fi
}

generate_meta_file() {
    # Create .meta entries used by PACKAGES.TXT.
    local pkgFile=$1
    local root=$2
    local pkgName=${pkgFile##*/}
    local basePath=${pkgFile%.*}
    local txtFile="${basePath}.txt"
    local metaFile="${basePath}.meta"
    local depFile="${basePath}.dep"
    local conFile="${basePath}.con"
    local sugFile="${basePath}.sug"
    local requires=""
    local conflicts=""
    local suggests=""
    local compressedK=""
    local uncompressedK=""
    local location=""

    if [[ -f "${depFile}" ]]; then
        requires=$(tr -d '\n' < "${depFile}")
    fi
    if [[ -f "${conFile}" ]]; then
        conflicts=$(tr -d '\n' < "${conFile}")
    fi
    if [[ -f "${sugFile}" ]]; then
        suggests=$(tr -d '\n' < "${sugFile}")
    fi

    if [[ ! -f "${metaFile}" || "${pkgFile}" -nt "${metaFile}" || "${txtFile}" -nt "${metaFile}" ]]; then
        if [[ ! -f "${txtFile}" ]]; then
            echo "Missing ${txtFile} for ${pkgName}"
            return 1
        fi

        echo "--> Generating .meta file for ${pkgName}"
        compressedK=$(package_compressed_k "${pkgFile}")
        uncompressedK=$(package_uncompressed_k "${pkgFile}")
        location=$(package_location_for_file "${root}" "${pkgFile}")

        {
            echo "PACKAGE NAME:  ${pkgName}"
            echo "PACKAGE LOCATION:  ${location}"
            echo "PACKAGE SIZE (compressed):  ${compressedK} K"
            echo "PACKAGE SIZE (uncompressed):  ${uncompressedK} K"
            echo "PACKAGE REQUIRED:  ${requires}"
            echo "PACKAGE CONFLICTS:  ${conflicts}"
            echo "PACKAGE SUGGESTS:  ${suggests}"
            echo "PACKAGE DESCRIPTION:"
            cat "${txtFile}"
            echo ""
        } > "${metaFile}"
    fi
}

generate_md5_file() {
    # Create per-package md5 file for later aggregation.
    local pkgFile=$1
    local pkgName=${pkgFile##*/}
    local md5File="${pkgFile%.*}.md5"
    local hash=""

    if [[ ! -f "${md5File}" || "${pkgFile}" -nt "${md5File}" ]]; then
        echo "--> Generating .md5 file for ${pkgName}"
        hash=$(md5sum "${pkgFile}" | awk '{print $1}')
        if [[ -z "${hash}" ]]; then
            echo "Failed to generate md5 for ${pkgName}"
            return 1
        fi
        printf '%s  %s\n' "${hash}" "${pkgName}" > "${md5File}"
    fi
}

generate_packages_txt_for_root() {
    # Rebuild PACKAGES.TXT from all .meta files in this repo root.
    local root=$1
    local -n packageList=$2
    local packagesFile="${root}/PACKAGES.TXT"
    local pkg=""
    local metaFile=""
    local location=""

    printf '\n' > "${packagesFile}"
    for pkg in "${packageList[@]}"; do
        metaFile="${pkg%.*}.meta"
        location=$(package_location_for_file "${root}" "${pkg}")
        sed -e "/^PACKAGE LOCATION: /s,^.*$,PACKAGE LOCATION:  ${location}," "${metaFile}" >> "${packagesFile}"
    done
    gzip -9 -c "${packagesFile}" > "${packagesFile}.gz"
}

generate_checksums_md5_for_root() {
    # Rebuild CHECKSUMS.md5 from per-package .md5 files.
    local root=$1
    local -n packageList=$2
    local checksumsFile="${root}/CHECKSUMS.md5"
    local pkg=""
    local pkgName=""
    local relPath=""
    local md5File=""

    : > "${checksumsFile}"
    for pkg in "${packageList[@]}"; do
        pkgName=${pkg##*/}
        relPath="./$(package_relative_path "${root}" "${pkg}")"
        md5File="${pkg%.*}.md5"
        if [[ ! -f "${md5File}" || "${pkg}" -nt "${md5File}" ]]; then
            generate_md5_file "${pkg}"
        fi
        sed "s|${pkgName}|${relPath}|" "${md5File}" >> "${checksumsFile}"
    done
    gzip -9 -c "${checksumsFile}" > "${checksumsFile}.gz"
}

regenerate_metadata_for_root() {
    local root=$1
    local -a packageFiles=()
    local pkg=""

    while IFS= read -r -d '' pkg; do
        packageFiles+=("${pkg}")
    done < <(gather_package_files_for_root "${root}")

    if ((${#packageFiles[@]} == 0)); then
        echo "No packages found for ${root}; skipping metadata."
        return 0
    fi

    for pkg in "${packageFiles[@]}"; do
        if ! generate_txt_file "${pkg}" "${pkg%.*}.txt"; then
            return 1
        fi
        if ! generate_meta_file "${pkg}" "${root}"; then
            return 1
        fi
        if ! generate_md5_file "${pkg}"; then
            return 1
        fi
    done

    generate_packages_txt_for_root "${root}" packageFiles
    generate_checksums_md5_for_root "${root}" packageFiles
}

regenerate_metadata() {
    # Regenerate metadata only for changed roots (or all roots if forced).
    local root=""

    for root in "${changedRootsList[@]}"; do
        echo "Regenerating metadata in ${root}..."
        if ! regenerate_metadata_for_root "${root}"; then
            return 1
        fi
    done
}

run_dry_run() {
    echo "Running upload dry-run..."
    RSYNC_PASSWORD="${password}" rsync "${uploadOptions[@]}" --dry-run "${excludeArgs[@]}" . "${userName}@${remoteHost}::slint-upload" |& w3m -T text/plain -
}

perform_upload() {
    RSYNC_PASSWORD="${password}" rsync "${uploadOptions[@]}" "${excludeArgs[@]}" . "${userName}@${remoteHost}::slint-upload"
}

prompt_upload() {
    local reply=""

    while true; do
        read -r -p "Perform actual upload? (yes/no): " reply
        case "${reply,,}" in
            y|yes)
                perform_upload
                return 0
                ;;
            n|no)
                echo "Upload skipped."
                return 0
                ;;
            *)
                echo "Please answer yes or no."
                ;;
        esac
    done
}

# Preflight checks

# Make sure we're in the correct repository directory
dirName=$(pwd)
dirName="${dirName##*/}"

# If not in proper directory, exit with error
if [[ "${repoDir}" != "${dirName}" ]]; then
    echo "Current directory <$(pwd)> does not match expected repository directory ${repoDir}."
    exit 1
fi

# Check for required dependencies
dependencies=(
    rsync
    w3m
    awk
    bzip2
    du
    find
    "${gpgBin}"
    gzip
    md5sum
    sed
    sort
    tar
    wc
    xz
)

declare -a missingDependencies
for i in "${dependencies[@]}" ; do
    if ! command -v "$i" &> /dev/null ; then
        missingDependencies+=("$i")
    fi
done
if [[ ${#missingDependencies[@]} -gt 0 ]]; then
    echo "Missing dependencies:"
    echo "Please install the following packages to continue..."
    for i in "${missingDependencies[@]}" ; do
        echo "$i"
    done
    exit 1
fi

# Make sure username and password is set
if [[ ${#userName} -lt 2 ]]; then
    echo "Username is not set. Please edit $0 and set the requested variables near the top of the file."
    exit 1
fi
if [[ ${#password} -lt 2 ]]; then
    echo "Password is not set. Please edit $0 and set the requested variables near the top of the file."
    exit 1
fi

select_gpg_key

# Main code starts here

# Ensure gpg uses the current TTY for passphrase prompts.
if tty -s; then
    export GPG_TTY
    GPG_TTY=$(tty)
fi

# Files/paths to exclude from any sync commands
scriptName=${0##*/}
excludePatterns=(
    "${scriptName}"
    ".git/"
    ".rsync-tmp/"
    "slint_repo.sh"
    "*.swp"
    "*.bak"
    "*~"
    ".DS_Store"
)

# Set editor
if [[ ${#editor} -lt 2 ]]; then
    if [[ -n "${EDITOR}" ]]; then
        editor="${EDITOR}"
    else
        editor="nano"
    fi
fi

# Make sure the upstream repository matches the local version.

echo "Syncing mirror..."
rsyncBaseOptions=(
    --no-motd
    --contimeout=30
    --timeout=60
    -aH
    "--chmod=go-w,+rX"
    --partial
    --partial-dir=.rsync-tmp
    --delay-updates
    --progress
    --verbose
    --human-readable
)

mirrorOptions=("${rsyncBaseOptions[@]}")
uploadOptions=("${rsyncBaseOptions[@]}" --delete-delay)

excludeArgs=()
for pattern in "${excludePatterns[@]}"; do
    excludeArgs+=(--exclude="${pattern}")
done

rsync "${mirrorOptions[@]}" "${excludeArgs[@]}" "${remoteHost}::${mirror}/" .

declare -a repoRoots
discover_repo_roots
load_package_base_dirs

declare -A baselineVersions
declare -A baselineFiles
declare -A baselineRoots
declare -A currentVersions
declare -A currentFiles
declare -A currentRoots

build_package_map baseline

echo "The mirror has been synced to this device."
read -r -p "Add any updated packages and press enter to continue."
echo -e "\nUpdating repository..."

build_package_map current
remove_old_packages
build_package_map current
collect_changes
if [[ "${forceRegenMetadata}" == "yes" ]]; then
    mapfile -t changedRootsList < <(printf '%s\n' "${repoRoots[@]}" | sort -u)
fi
if ! regenerate_metadata; then
    exit 1
fi
update_changelogs

# Check gpg signatures
if ! sign_existing_signatures; then
    exit 1
fi
if ! verify_existing_signatures; then
    if ! handle_bad_signature_failures; then
        exit 1
    fi
    if ! verify_existing_signatures; then
        exit 1
    fi
fi

if [[ "${autoImportMissingKeys}" == "yes" ]] && ((${#missingSignatureKeys[@]} > 0)); then
    if import_missing_signature_keys "${missingSignatureKeys[@]}"; then
        if ! verify_existing_signatures; then
            if ! handle_bad_signature_failures; then
                exit 1
            fi
            if ! verify_existing_signatures; then
                exit 1
            fi
        fi
    fi
fi

if ((${#expiredSignatureFiles[@]} > 0)); then
    prompt_expired_signature_resign
    case $? in
        0)
            if ! verify_existing_signatures; then
                if ! handle_bad_signature_failures; then
                    exit 1
                fi
                if ! verify_existing_signatures; then
                    exit 1
                fi
            fi
            ;;
        2)
            if [[ "${allowExpiredSignatures}" != "yes" ]]; then
                echo "Expired signatures remain. Set allowExpiredSignatures=\"yes\" or replace them."
                exit 1
            fi
            ;;
        *)
            exit 1
            ;;
    esac
fi

prompt_orphan_signature_review

run_dry_run
prompt_upload

exit 0

# vim: set ts=4 sw=4 et:
