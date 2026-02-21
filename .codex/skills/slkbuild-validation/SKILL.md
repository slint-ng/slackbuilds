---
name: slkbuild-validation
description: Validate SLKBUILD build results from ~/slkbuilds by checking build logs, package artifacts, and expected payload paths. Use when a user asks if a build "looks good", asks to validate logs/artifacts, or requests acceptance checks.
---

# SLKBUILD Validation

## Overview

Use this skill to perform repeatable, build-only validation for packages built
from `SLKBUILD`.

This skill assumes the mount root is always:
- `~/slkbuilds`

It accepts either:
- a relative package path like `k/sof-firmware`
- a relative package path like `k/firmware-installer`
- a relative package path like `k/kernel`
- a relative package path like `a/kernel-firmware`
- or a full path like `/home/alice/slkbuilds/k/sof-firmware`

## Workflow

1. Resolve the package path.
- If relative, resolve under `$HOME/slkbuilds`.

2. Run the validator script.
- `bash .codex/skills/slkbuild-validation/scripts/validate_pkg.sh k/sof-firmware`
- `bash .codex/skills/slkbuild-validation/scripts/validate_pkg.sh k/firmware-installer`
- `bash .codex/skills/slkbuild-validation/scripts/validate_pkg.sh k/kernel`
- `bash .codex/skills/slkbuild-validation/scripts/validate_pkg.sh k/modules-installer`
- `bash .codex/skills/slkbuild-validation/scripts/validate_pkg.sh a/kernel-firmware`

3. Return the script result as a fixed checklist.
- `Artifacts`
- `Log Health`
- `Payload Checks`
- `Verdict`
- `Next Action`

4. On failure, report the first actionable fix.
- Example: missing artifact, missing payload path, hard-failure marker in log.

## Scope

- Build-only validation.
- No install/upgrade actions.
- Non-mutating checks only.

## Known Behavior

- Benign patterns are ignored when success markers and artifacts are present.
- The validator derives package name/version from the built `.txz`, so package
  directory and package artifact names may differ.
- Split kernel packages are validated with package-specific payload checks for:
  `kernel`, `kernel-headers`, `kernel-source`, `modules-installer`,
  and `kernel-firmware`.
- See `references/known-benign-patterns.md`.

## Resources

### scripts/
- `validate_pkg.sh`: Standard validator for logs, artifacts, and payload checks.

### references/
- `known-benign-patterns.md`: Non-fatal log patterns.
