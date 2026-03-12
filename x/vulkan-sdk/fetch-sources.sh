#!/bin/bash

# Copyright 2017, 2018  Patrick J. Volkerding, Sebeka, Minnesota, USA
# Copyright 2021  Heinz Wiesinger, Amsterdam, The Netherlands
# All rights reserved.
#
# Redistribution and use of this script, with or without modification, is
# permitted provided that the following conditions are met:
#
# 1. Redistributions of this script must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#
#  THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR IMPLIED
#  WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
#  MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO
#  EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
#  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
#  PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
#  OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
#  WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
#  OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
#  ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# Call this script with the version of the Vulkan-LoaderAndValidationLayers-sdk
# that you would like to fetch the sources for. This will fetch the SDK from
# github, and then look at the revisions listed in the external_revisions
# directory to fetch the proper glslang, SPIRV-Headers, and SPIRV-Tools.
#
# Example:  VERSION=1.1.92.1 ./fetch-sources.sh

set -euo pipefail

version=${VERSION:-latest}

map_archive_name() {
  case "$1" in
    glslang) printf '%s\n' "glslang-sdk" ;;
    SPIRV-Tools) printf '%s\n' "SPIRV-Tools-sdk" ;;
    Vulkan-Headers) printf '%s\n' "Vulkan-Headers-sdk" ;;
    Vulkan-Loader) printf '%s\n' "Vulkan-Loader-sdk" ;;
    volk) printf '%s\n' "volk" ;;
    Vulkan-ValidationLayers) printf '%s\n' "Vulkan-ValidationLayers-sdk" ;;
    Vulkan-Utility-Libraries) printf '%s\n' "Vulkan-Utility-Libraries-sdk" ;;
    Vulkan-ExtensionLayer) printf '%s\n' "Vulkan-ExtensionLayer-sdk" ;;
    Vulkan-Tools) printf '%s\n' "Vulkan-Tools-sdk" ;;
    VulkanTools) printf '%s\n' "VulkanTools-sdk" ;;
    SPIRV-Cross) printf '%s\n' "SPIRV-Cross-sdk" ;;
    gfxreconstruct) printf '%s\n' "gfxreconstruct-sdk" ;;
    SPIRV-Reflect) printf '%s\n' "SPIRV-Reflect-sdk" ;;
    Vulkan-Profiles) printf '%s\n' "Vulkan-Profiles-sdk" ;;
    shaderc|DirectXShaderCompiler|valijson) printf '%s\n' "$1" ;;
    *) return 1 ;;
  esac
}

resolve_repo_path() {
  case "$1" in
    glslang|SPIRV-Headers|SPIRV-Tools|Vulkan-Headers|Vulkan-Loader|Vulkan-ValidationLayers|Vulkan-Utility-Libraries|Vulkan-ExtensionLayer|Vulkan-Tools|SPIRV-Cross|SPIRV-Reflect|Vulkan-Profiles)
      printf '%s\n' "KhronosGroup/$1"
      ;;
    VulkanTools|gfxreconstruct)
      printf '%s\n' "LunarG/$1"
      ;;
    volk)
      printf '%s\n' "zeux/volk"
      ;;
    shaderc)
      printf '%s\n' "google/shaderc"
      ;;
    DirectXShaderCompiler)
      printf '%s\n' "microsoft/DirectXShaderCompiler"
      ;;
    valijson)
      printf '%s\n' "tristanpenman/valijson"
      ;;
    *)
      printf '%s\n' "$1"
      ;;
  esac
}

extract_release_components() {
  local releaseNotesPath=$1

  python3 - "$releaseNotesPath" << 'EOF'
import html
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="ignore")
text = re.sub(r"(?is)<(script|style).*?>.*?</\1>", "", text)
text = html.unescape(re.sub(r"(?s)<[^>]+>", " ", text))
text = re.sub(r"\s+", " ", text)

pattern = re.compile(
    r"(?:GitHub|Github) Repo:\s*"
    r"([A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)?)"
    r"(?:\s+github\.com)?"
    r"\s*,?\s*"
    r"(Version Tag|Commit|tag|commit):\s*"
    r"([^,\s]+)",
    re.IGNORECASE,
)

for match in pattern.finditer(text):
    print(f"{match.group(1).strip()}\t{match.group(2).strip()}\t{match.group(3).strip()}")
EOF
}

get_known_good() {
  local jsonPath=$1
  local depName=$2
  local jsonKey=$3

  python3 - << EOF
import json
with open('$jsonPath', encoding='utf-8') as f:
	known_good = json.load(f)
name = '$depName'
headers = next(commit for commit in known_good['$jsonKey'] if commit['name'] == name)
print(headers['commit'])
EOF
}

clone_and_pack() {
  local repoPath=$1
  local archiveName=$2
  local refName=$3
  local cloneDir=""
  local oldPwd=$PWD
  local resolvedRefName=$refName
  local refCandidates=("$refName")
  local refCandidate=""
  local refResolved=0

  if [ "$archiveName" = "VulkanTools-sdk" ]; then
    refCandidates+=("vulkan-sdk-${version}")
    refCandidates+=("v${version%.0}")
  fi

  for refCandidate in "${refCandidates[@]}"; do
    if [ -e "${archiveName}-${refCandidate}.tar.lz" ]; then
      resolvedRefName=$refCandidate
      refResolved=1
      break
    fi
  done

  cloneDir="${archiveName}-${resolvedRefName}"

  if [ "$refResolved" -eq 1 ] && [ -e "${archiveName}-${resolvedRefName}.tar.lz" ]; then
    if ! [ -d "$cloneDir" ]; then
      tar xf "${cloneDir}.tar.lz"
    fi
    return 0
  fi

  git clone "https://github.com/${repoPath}.git" "$cloneDir"
  cd "$cloneDir" || return 1
  for refCandidate in "${refCandidates[@]}"; do
    if git reset --hard "$refCandidate" || git reset --hard "origin/$refCandidate"; then
      resolvedRefName=$refCandidate
      refResolved=1
      break
    fi
  done
  [ "$refResolved" -eq 1 ] || return 1
  git submodule update --init --recursive
  git describe --tags --always > .git-version
  cd "$oldPwd" || return 1
  if [ "$resolvedRefName" != "$refName" ]; then
    mv "$cloneDir" "${archiveName}-${resolvedRefName}"
    cloneDir="${archiveName}-${resolvedRefName}"
  fi
  tar --exclude-vcs -cf "${cloneDir}.tar" "$cloneDir"
  plzip -9 "${cloneDir}.tar"
}

rm -f ./*.tar.lz
rm -f release_notes.html release_components.tsv

if [ "$version" = "latest" ]; then
  version=$(wget -qO- "https://vulkan.lunarg.com/sdk/latest/linux.txt")
fi

releaseNotesUrl="https://vulkan.lunarg.com/doc/view/${version}/linux/release_notes.html"
wget -O release_notes.html "$releaseNotesUrl"
extract_release_components release_notes.html > release_components.tsv

while IFS=$'\t' read -r repoPath refType refName; do
  [ -n "$repoPath" ] || continue

  repoPath=${repoPath#https://github.com/}
  repoPath=${repoPath%.git}
  if [[ "$repoPath" != */* ]]; then
    repoPath=$(resolve_repo_path "$repoPath")
  fi
  repoName=$(basename "$repoPath")

  if ! archiveName=$(map_archive_name "$repoName"); then
    continue
  fi

  if [ -e "${archiveName}.fetched" ]; then
    continue
  fi

  printf '\n%s (%s %s)\n\n' "$archiveName" "$refType" "$refName"
  clone_and_pack "$repoPath" "$archiveName" "$refName"
  touch "${archiveName}.fetched"

  if [ "$repoName" = "glslang" ] && ! [ -e "SPIRV-Headers.fetched" ]; then
    spirvHeadersTag="vulkan-sdk-${version}"
    clone_and_pack "KhronosGroup/SPIRV-Headers" "SPIRV-Headers" "$spirvHeadersTag"
    touch "SPIRV-Headers.fetched"
  elif [ "$repoName" = "Vulkan-ValidationLayers" ] && ! [ -e "robin-hood-hashing.fetched" ]; then
    robinHoodCommit=$(get_known_good "${archiveName}-${refName}/scripts/known_good.json" "robin-hood-hashing" "repos")
    clone_and_pack "martinus/robin-hood-hashing" "robin-hood-hashing" "$robinHoodCommit"
    touch "robin-hood-hashing.fetched"
  fi
done < release_components.tsv

valijsonVersion="v1.1.0"
if ! [ -e "valijson-${valijsonVersion}.tar.lz" ]; then
  printf '\n%s (%s %s)\n\n' "valijson" "Version Tag" "$valijsonVersion"
  clone_and_pack "tristanpenman/valijson" "valijson" "$valijsonVersion"
fi

printf '%s\n' "$version" > VERSION

rm -f release_notes.html
rm -f release_components.tsv
rm -f -- ./*.fetched
