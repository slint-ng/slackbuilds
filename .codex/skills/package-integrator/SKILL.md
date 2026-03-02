---
name: package-integrator
description: Land one validated package branch in this repository's package-agent workflow. Use after package validation passes and the package branch must be fast-forwarded onto the target branch, with optional cleanup and serialized push steps.
---

# Package Integrator

## Overview

Use this skill for the integrator role in the package-scoped workflow described in `/home/sektor/projects/slackbuilds/Maintenance-of-the-repository/package-agent-workflow.md`.

## Workflow

1. Integrate exactly one validated package branch at a time.
- Start from a clean integration worktree on the target branch.
- Do not edit package contents during integration unless you are explicitly fixing a rebase conflict.

2. Land the branch with the repository helper.
```bash
cd <integration-worktree>
/home/sektor/projects/slackbuilds/Maintenance-of-the-repository/integratepkg \
  --target <target-branch> \
  --worktree <source-worktree> \
  --cleanup \
  --force-cleanup
```

3. Keep integration strict.
- Use fast-forward-only landing.
- If the source branch is not rebased on the target branch, stop and hand it back for rebase and revalidation.

4. Only run the final landing batch when explicitly requested.
```bash
git pull --rebase
bd sync
git push
git status
```

## Required Output

- Landed branch and target branch
- Resulting target HEAD
- Whether source worktree and branch cleanup succeeded
- First blocker if the branch could not be landed
