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

3. Build and dependency generation defaults
- Prefer `fakeroot slkbuild -X` for local build+clean validation.
  Running `slkbuild -X` as a non-root user fails by design.
- Generate package dependency metadata only from the built package artifact,
  never from a source directory.

### SlackBuild -> SLKBUILD conversion

- Use `scripts/convert_slackbuild.py` for a best-effort scaffold, then review.
- If the package already exists in-tree, keep the current in-tree version
  when converting (do not bump to a newer upstream/Arch version unless the
  user explicitly asks for an update).
- Preserve the build logic exactly (configure/meson flags, install steps, docs).
- Inline `slack-desc` into `slackdesc=(...)` and keep the handy ruler line.
- Inline `doinst.sh` into `doinst()`.
- Do **not** create placeholder dependency metadata during conversion.
  - Dependency metadata must be generated **after** building the package, from
    the produced package artifact (`*.txz`/`*.t?z`) using `depfinder`.
  - Keep the generated package-style dep filename:
    `<pkgname>-<pkgver>-<arch>-<pkgrel>.dep`.
  - Python packages: use `depfinder -p -f -3 <package>.txz`.
    Due to a `depfinder` option parsing bug, keep `-3` as the final option.
  - Non-Python packages: use `depfinder -f <package>.txz`.
  - Do not run `depfinder -f .` in the package directory; it can emit malformed
    output filenames (for example `..dep`).
  - Treat detected `python2` dependencies as potentially valid in this repo.
    Some packages still legitimately depend on Python 2, so do not auto-rewrite
    `python2` deps to `python3` without package-specific verification.
  - `.dep` content is comma-separated with no spaces.
- For restricted/containerized environments, avoid adding `unshare -n` in
  Python wheel bootstrap steps unless explicitly required and verified.
- Keep necessary helper files (patches, scripts, extra data files) and add to `source=()` when required by the build.
- Remove redundant files after conversion:
  - `*.SlackBuild`, `slack-desc`, `doinst.sh`, and `.info` when it is no longer used.
- Keep `.url`, `.news`, `.sha256sum`, and similar files unless you are sure they are obsolete.

### Updates

- If unsure of the latest version, ask the user to confirm (Arch usually tracks latest).
- Update `pkgver`, `source`, and any checksums.
- Use `scripts/bump_version.py` when possible to update `pkgver` and sums.
- Sync `docs=()` with what the build installs.
- If runtime dependencies change, rebuild and regenerate the package `.dep`
  from the produced package artifact with `depfinder` in the same commit.
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
- `bash -n SLKBUILD` must pass before attempting build validation.
- For converted/updated packages, ensure dependency metadata comes from
  `depfinder` run on the built package artifact and is saved as the generated
  package-style `.dep` filename (`<pkgfull>.dep`).
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
- `sync_dep_files.py`: Legacy helper for `<pkgname>.dep` from `depends=()`;
  do not use for package dependency metadata in this repo workflow.
