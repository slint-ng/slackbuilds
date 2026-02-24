---
name: slkbuild-validation
description: Validate SLKBUILD build results from /home/sektor/projects/slackbuilds by checking build logs, package artifacts, and expected payload paths. Use when a user asks if a build "looks good", asks to validate logs/artifacts, or requests acceptance checks.
---

# SLKBUILD Validation

## Overview

Use this skill to perform repeatable, build-only validation for packages built
from `SLKBUILD`.

This skill assumes the validation root is always:
- `/home/sektor/projects/slackbuilds`

It accepts either:
- a relative package path like `k/sof-firmware`
- a relative package path like `k/firmware-installer`
- a relative package path like `k/kernel`
- a relative package path like `a/kernel-firmware`
- or a full path like `/home/sektor/projects/slackbuilds/k/sof-firmware`

## Workflow

1. Wait for explicit VM build progress from the user.
- Expected handoff format:
  - `bead: <id>`
  - `package: <category>/<pkg>`
  - optional `build note: <status>`

2. Resolve the package path.
- If relative, resolve under `/home/sektor/projects/slackbuilds`.

3. Run the validator script.
- `bash .codex/skills/slkbuild-validation/scripts/validate_pkg.sh k/sof-firmware`
- `bash .codex/skills/slkbuild-validation/scripts/validate_pkg.sh k/firmware-installer`
- `bash .codex/skills/slkbuild-validation/scripts/validate_pkg.sh k/kernel`
- `bash .codex/skills/slkbuild-validation/scripts/validate_pkg.sh k/modules-installer`
- `bash .codex/skills/slkbuild-validation/scripts/validate_pkg.sh a/kernel-firmware`
- Optional regression check:
  `bash .codex/skills/slkbuild-validation/scripts/test_validate_pkg.sh`
- Also run `bash -n <pkg>/SLKBUILD` and include the result in validation notes.
- If `shellcheck` is unavailable, record that explicitly instead of assuming pass.

4. Return the script result as a fixed checklist.
- `Artifacts`
- `Log Health`
- `Payload Checks`
- `Verdict`
- `Next Action`
- Include `.dep` artifact presence and filename as part of artifact evidence
  (package-style `<pkgfull>.dep`, generated from built package).

5. On failure, report the first actionable fix.
- Example: missing artifact, missing payload path, hard-failure marker in log.
- If `.txz`/log/md5 is missing, keep the validation bead open with an explicit
  "build evidence missing" reason.

## Scope

- Build-only validation.
- No install/upgrade actions.
- Non-mutating checks only.

## Known Behavior

- Benign patterns are ignored when success markers and artifacts are present.
- If multiple logs exist, the validator prefers a log matching the built `.txz`
  name before falling back to the latest `build-*.log`.
- Generic `error:` log lines are shown as non-fatal when success markers and
  artifacts exist, unless they match critical failure markers.
- `depfinder` warnings about missing optional/test Python modules can be
  non-fatal when build success markers, required artifacts, and payload checks
  all pass.
- `python2` entries in generated `.dep` files are not automatic failures in
  this repository; some packages legitimately depend on Python 2.
- The validator derives package name/version from the built `.txz`, so package
  directory and package artifact names may differ.
- Split kernel packages are validated with package-specific payload checks for:
  `kernel`, `kernel-headers`, `kernel-source`, `modules-installer`,
  and `kernel-firmware`.
- Validation is build-only. For live kernel rollouts, initramfs/boot menu checks
  still require post-install verification (`dracut`, `update-grub`,
  `list_boot_entries`, and post-reboot `uname -r`).
- See `references/known-benign-patterns.md`.

## Resources

### scripts/
- `validate_pkg.sh`: Standard validator for logs, artifacts, and payload checks.
- `test_validate_pkg.sh`: Regression fixture for `firmware-installer` payload checks.

### references/
- `known-benign-patterns.md`: Non-fatal log patterns.
