---
name: slint-packaging
description: SlackBuild/SLKBUILD maintenance for the Slint slackbuilds repo. Use for converting SlackBuilds to SLKBUILD, updating package versions and checksums, adjusting build steps or deps, cleaning redundant files, enforcing slackdesc line-length rules, and preparing package changes for commit.
---

# Slint Packaging

## Overview

Use this skill to standardize Slint package maintenance tasks, especially SlackBuild → SLKBUILD conversions and version updates.


## First-use notes

On first use in a session, explicitly mention:
- `convert_slackbuild.py` is a best‑effort scaffold and requires manual review.
- `bump_version.py` updates checksums only when sums arrays exist and sources are URL‑based.
- If latest version is uncertain, ask the user to confirm (Arch is usually current).

## Workflow

1. Inspect the package directory
- List files and read `README`, `*.info`, `slack-desc`, `doinst.sh`, patches, and the build script.
- Note upstream URLs, versioning, and any custom steps (git clone, meson, cmake, etc.).
- If a similar package already uses SLKBUILD, use it as a pattern.

2. Decide the task
- **Conversion**: SlackBuild → SLKBUILD
- **Update**: version bump, source checksums, deps, build flags

### SlackBuild → SLKBUILD conversion

- Use `scripts/convert_slackbuild.py` for a best‑effort scaffold, then review.
- Preserve the build logic exactly (configure/meson flags, install steps, docs).
- Inline `slack-desc` into `slackdesc=(...)` and keep the handy ruler line.
- Inline `doinst.sh` into `doinst()`.
- Keep necessary helper files (patches, scripts, extra data files) and add to `source=()` when required by the build.
- Remove redundant files after conversion:
  - `*.SlackBuild`, `slack-desc`, `doinst.sh`, and `.info` when it is no longer used.
- Keep `.url`, `.news`, `.sha256sum`, and similar files unless you are sure they are obsolete.

### Updates

- If unsure of the latest version, ask the user to confirm (Arch usually tracks latest).
- Update `pkgver`, `source`, and any checksums.
- Use `scripts/bump_version.py` when possible to update `pkgver` and sums.
- Sync `docs=()` with what the build installs.
- Preserve existing build flags unless the update requires changes.

## Quality checks

- `slackdesc` lines should be <= 70 chars (URLs can be longer if needed).
- `slackdesc` should be <= 10 lines.
- If you edit a bash script, run `shellcheck` and fix reported issues.

## Resources

### scripts/
- `check_slackdesc_len.py`: Validate slackdesc line length and line count.
- `convert_slackbuild.py`: Best‑effort SlackBuild → SLKBUILD scaffold.
- `bump_version.py`: Update `pkgver` and refresh checksums if present.
