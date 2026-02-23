---
name: slint-packaging
description: SlackBuild/SLKBUILD maintenance for the Slint slackbuilds repo. Use for converting SlackBuilds to SLKBUILD, updating package versions and checksums, adjusting build steps or deps, cleaning redundant files, enforcing slackdesc line-length rules, and preparing package changes for commit.
---

# Slint Packaging

## Overview

Use this skill to standardize Slint package maintenance tasks, especially SlackBuild -> SLKBUILD conversions and version updates.

## First-use notes

On first use in a session, explicitly mention:
- `convert_slackbuild.py` is a best-effort scaffold and requires manual review.
- `bump_version.py` updates checksums only when sums arrays exist and sources are URL-based.
- If latest version is uncertain, ask the user to confirm (Arch is usually current).

## Workflow

1. Inspect the package directory
- List files and read `README`, `*.info`, `slack-desc`, `doinst.sh`, patches, and the build script.
- Note upstream URLs, versioning, and any custom steps (git clone, meson, cmake, etc.).
- If a similar package already uses SLKBUILD, use it as a pattern.
- Confirm naming and headers are consistent across the directory name, `pkgname`, `slackdesc`, README, and packager header.

2. Decide the task
- **Conversion**: SlackBuild -> SLKBUILD
- **Update**: version bump, source checksums, deps, build flags

### SlackBuild -> SLKBUILD conversion

- Use `scripts/convert_slackbuild.py` for a best-effort scaffold, then review.
- If the package already exists in-tree, keep the current in-tree version
  when converting (do not bump to a newer upstream/Arch version unless the
  user explicitly asks for an update).
- Preserve the build logic exactly (configure/meson flags, install steps, docs).
- Inline `slack-desc` into `slackdesc=(...)` and keep the handy ruler line.
- Inline `doinst.sh` into `doinst()`.
- Ensure dependency metadata exists as `<pkgname>.dep` in the package directory.
  - `sourcegen.sh` reads `<pkgname>.dep` for `SLACKBUILD REQUIRES`; it does not read `depends=()` from `SLKBUILD`.
  - Keep `.dep` comma-separated with no spaces (example: `python,gtk3,python-gobject`).
- Keep necessary helper files (patches, scripts, extra data files) and add to `source=()` when required by the build.
- Remove redundant files after conversion:
  - `*.SlackBuild`, `slack-desc`, `doinst.sh`, and `.info` when it is no longer used.
- Keep `.url`, `.news`, `.sha256sum`, and similar files unless you are sure they are obsolete.

### Updates

- If unsure of the latest version, ask the user to confirm (Arch usually tracks latest).
- Update `pkgver`, `source`, and any checksums.
- Use `scripts/bump_version.py` when possible to update `pkgver` and sums.
- Sync `docs=()` with what the build installs.
- If `depends=()` changes, update `<pkgname>.dep` in the same commit.
- Preserve existing build flags unless the update requires changes.
- For linux-firmware based packages in this repo, preserve the paired
  date/commit versioning (`<date>_<commit>`) used by Slint and verify the
  checkout/tag resolves to the expected commit before packaging.

### Kernel and firmware conventions in this repo

- Keep `a/kernel-firmware` in `a/`; do not move it to `k/` unless explicitly requested.
- Keep AMD microcode authoritative in `k/amd-microcode`; avoid duplicate AMD
  microcode package generation in `a/kernel-firmware`.
- Treat kernel outputs as split packages:
  `k/kernel`, `k/kernel-headers`, `k/kernel-source`, and `k/modules-installer`.
- Keep `k/modules-installer` tied to built kernel artifacts (explicit `KERNEL_PKG`
  override or deterministic local detection), not legacy `../../packages` assumptions.
- For `k/dkms` (3.3.x+), keep legacy helper scripts in `/usr/lib/dkms/`
  (`dkms_autoinstaller`, `common.postinst`) for existing Slint/Slackware-style
  local hook compatibility.
- Runtime kernel upgrade flow in this repo is dracut-based: wrappers use
  `dracut --no-early-microcode` then `update-grub`. If installing kernels with
  plain `upgradepkg`, run those steps manually.

## Debugging build failures

- Always preserve generated build scripts before reruns (`build-<pkg>.sh`).
- When `set -e` is active, verify failing function return status, not only stderr output.
- Inspect slkbuild-generated helper functions (`gzip_man_and_info_pages`, post-checks, create_package) early when build() seems to pass.
- Start diagnostics narrowly in the suspected block; widen only if the first pass is inconclusive.
- Keep diagnostics reversible and remove them in a dedicated cleanup commit after success.
- If a generated tail uses test-and-and patterns (for example `[ -a file ] && rm file`) under `set -e`, account for non-zero test returns so successful builds do not abort.

## Quality checks

- `slackdesc` lines should be <= 70 chars (URLs can be longer if needed).
- `slackdesc` should be <= 10 lines.
- Ensure every tracked package `SLKBUILD` has a matching `<pkgname>.dep` file.
  - Use `scripts/sync_dep_files.py --check` to audit.
  - Use `scripts/sync_dep_files.py --write` to create/update dep files in bulk.
- In `SLKBUILD`, use plain URL sources (for example `https://...`).
  Do not use Arch-style `git+https://...` source syntax.
  Tag-based git sources are fine as plain URLs, for example
  `https://example.org/repo.git#tag=v1.2.3`.
- Prefer simple, explicit `source=()` URLs over bash substring expansion
  expressions such as `${name::1}` inside `source`; some `slkbuild -X`
  generations can mis-handle those and produce bad `cd` paths.
- If you edit a bash script, run `shellcheck` and fix reported issues.

## Resources

### scripts/
- `check_slackdesc_len.py`: Validate slackdesc line length and line count.
- `convert_slackbuild.py`: Best-effort SlackBuild -> SLKBUILD scaffold.
- `bump_version.py`: Update `pkgver` and refresh checksums if present.
- `sync_dep_files.py`: Generate/update `<pkgname>.dep` files from `depends=()` across tracked `SLKBUILD`s.
