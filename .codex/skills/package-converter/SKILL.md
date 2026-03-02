---
name: package-converter
description: Run one package conversion or update in this repository's package-agent workflow. Use when a single package needs SlackBuild to SLKBUILD conversion or another package-local packaging change in a sparse worktree, then must be handed off to validation.
---

# Package Converter

## Overview

Use this skill for the converter role in the package-scoped workflow described in `/home/sektor/projects/slackbuilds/Maintenance-of-the-repository/package-agent-workflow.md`.

Load `/home/sektor/projects/slackbuilds/.codex/skills/slint-packaging/SKILL.md` and follow it for package conversion and update rules.

## Workflow

1. Work on exactly one package, one branch, and one worktree.
- Do not touch unrelated packages or shared helpers unless the task explicitly requires it.

2. Create or enter the sparse package worktree with the repository helper.
```bash
/home/sektor/projects/slackbuilds/Maintenance-of-the-repository/convertpkg \
  --work-bead <work-bead> \
  --validation-bead <validation-bead> \
  --id <short-id> \
  <category/package>
```

3. Inspect the package and perform the conversion or update with `slint-packaging`.
- Treat `convert_slackbuild.py` as a scaffold only.
- Keep legacy SlackBuild files until the conversion gates pass.
- Same-version conversions must be handed off for baseline validation.

4. Run the conversion gates.
```bash
python3 /home/sektor/projects/slackbuilds/.codex/skills/slint-packaging/scripts/check_conversion_gates.py <abs-package-dir>
python3 /home/sektor/projects/slackbuilds/.codex/skills/slint-packaging/scripts/check_conversion_gates.py --shellcheck <abs-package-dir>
```

5. Build the package.
```bash
cd <abs-package-dir>
fakeroot slkbuild -X
```

6. Emit the validator handoff block.
```bash
/home/sektor/projects/slackbuilds/Maintenance-of-the-repository/pkghandoff \
  --worktree <worktree-path> \
  --work-bead <work-bead> \
  --validation-bead <validation-bead> \
  <category/package>
```

7. Stop after the handoff.
- Do not merge, push, or close the validation bead.

## Required Output

- Short change summary
- Exact changed files
- Build result
- The `pkghandoff` block
- First blocker if the package could not be validated yet
