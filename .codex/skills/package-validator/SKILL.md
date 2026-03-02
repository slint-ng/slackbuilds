---
name: package-validator
description: Validate one package handoff in this repository's package-agent workflow. Use after a converter hands off a package worktree and you need to run bash and shellcheck checks, artifact and dep validation, baseline manifest comparison, and bead evidence recording.
---

# Package Validator

## Overview

Use this skill for the validator role in the package-scoped workflow described in `/home/sektor/projects/slackbuilds/Maintenance-of-the-repository/package-agent-workflow.md`.

Load `/home/sektor/projects/slackbuilds/.codex/skills/slkbuild-validation/SKILL.md` and follow it for validation rules and output format.

## Workflow

1. Validate exactly one package handoff.
- Prefer the handoff block from `pkghandoff` over assumptions.
- Do not widen scope beyond the handed-off package.

2. Run the repository validator helper.
```bash
/home/sektor/projects/slackbuilds/Maintenance-of-the-repository/validatepkgwt \
  --handoff - \
  --require-baseline
```
or
```bash
/home/sektor/projects/slackbuilds/Maintenance-of-the-repository/validatepkgwt \
  --worktree <worktree-path> \
  --require-baseline \
  <category/package>
```

3. Confirm the required evidence.
- `bash -n` passes
- `shellcheck` passes, or is explicitly unavailable
- the package artifact exists
- the package-style `.dep` file exists
- the validator output records artifact, log, payload, and manifest results
- compile and basic smoketest evidence is stated

4. Record the evidence in the validation bead.
- Close the validation bead only when the evidence is explicit.
- If validation fails, keep the bead open and report the first actionable fix.

5. Stop after validation.
- Do not merge or push unless explicitly asked.

## Required Output

- Validation verdict
- Exact evidence for `bash -n`, `shellcheck`, artifact presence, `.dep` presence, and manifest result
- First failing reason if validation did not pass
- Whether the package is ready for `integratepkg`
