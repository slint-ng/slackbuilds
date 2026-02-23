# Repository Guidelines

## Project Structure & Module Organization
This repository is a collection of SlackBuild package directories. Many are
grouped by Slackware series (for example `a/`, `ap/`, `d/`, `l/`, `n/`, `t/`,
`x/`, `xap/`, `y/`, `kde/`), but some packages also live at the repo root.
Each package directory typically contains `<pkg>.SlackBuild`, `<pkg>.info`,
`slack-desc`, `README`, and optional files like `doinst.sh`, patches
(`*.diff`/`*.patch`), or helper scripts. Templates and reference files live in
`templates/SlackBuilds/`. Repository maintenance helpers are in
`Maintenance-of-the-repository/`.

## Build, Test, and Development Commands
- Build a package by running its SlackBuild script from the package directory:
  `cd ap/abcde && sudo ./abcde.SlackBuild`
- Use the local `README` and `.info` for dependencies, build notes, and source
  URLs/checksums.
- There is no repo-wide build or test runner; some packages ship their own
  helpers (for example `build-*.sh` or `make-git-tarball.sh`).

## Coding Style & Naming Conventions
- `README`: max 72 chars per line, 2-4 spaces indent, no tabs, ASCII/UTF-8, and
  no homepage URL. Long instructions should go in `README.SBo`.
- `slack-desc`: exactly 11 lines, each prefixed with the package name; follow
  the ruler format in `templates/SlackBuilds/slack-desc`.
- `.info`: follow `templates/SlackBuilds/template.info` and keep `PRGNAM`,
  `VERSION`, `DOWNLOAD`, and `MD5SUM` accurate.
- File names: `<pkg>.SlackBuild`, `<pkg>.info`, and descriptive patch names
  (`fix-foo.diff`, `enable-bar.patch`).

## Testing Guidelines
- Primary check is a clean `./<pkg>.SlackBuild` run.
- If upstream tests are available, document how to run them in `README` and run
  them when feasible (for example `make test`).

## Commit & Pull Request Guidelines
- Git history is small and uses short, sentence-case messages (for example
  "Added ...", "removed ..."). Keep commits one line and mention the
  package/category.
- PRs should describe the change, list updated files (SlackBuild, .info,
  patches), and note build/test results and any special install steps.

## Security & Configuration Tips
- When updating sources, refresh `MD5SUM` fields and align `REQUIRES` with the
  README list (use `%README%` when dependencies are documented there).
- Keep secrets out of scripts; use `Maintenance-of-the-repository/` tools for
  repo-wide maintenance tasks.

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until both `git push` and `bd dolt push` succeed.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Create validation bead(s) for package work** - For every package conversion/update, create a validation issue (`bug`, `p1`) linked with `discovered-from:<work-id>`
4. **Run validation and record evidence** - Execute validation checks and keep validation beads open until evidence is captured
5. **Update issue status** - Close finished work, update in-progress items
6. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd dolt pull
   bd dolt push
   git push
   git status  # MUST show "up to date with origin"
   ```
7. **Clean up** - Clear stashes, prune remote branches
8. **Verify** - All changes committed AND pushed
9. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until both `git push` and `bd dolt push` succeed
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
- Do not use `bd sync`; it is deprecated/no-op in `bd 0.56.1+`
- For package conversion/update work, validation beads are mandatory
- Validation beads for package work must be `bug` + `p1` and linked via `discovered-from:<work-id>`
- Do not close validation beads without explicit validation evidence in the update/close reason


<!-- BEGIN BEADS INTEGRATION -->
## Issue Tracking with bd (beads)

**IMPORTANT**: This project uses **bd (beads)** for ALL issue tracking. Do NOT use markdown TODOs, task lists, or other tracking methods.

### Why bd?

- Dependency-aware: Track blockers and relationships between issues
- Git-friendly: Dolt-native sync with JSONL tracked in git
- Agent-optimized: JSON output, ready work detection, discovered-from links
- Prevents duplicate tracking systems and confusion

### Quick Start

**Check for ready work:**

```bash
bd ready --json
```

**Create new issues:**

```bash
bd create "Issue title" --description="Detailed context" -t bug|feature|task -p 0-4 --json
bd create "Issue title" --description="What this issue is about" -p 1 --deps discovered-from:bd-123 --json
```

**Create required package validation issues:**

```bash
bd create "Validate <pkg>: <change summary>" -t bug -p 1 --deps discovered-from:<work-id> --description="Validation scope and expected outcome" --json
```

**Claim and update:**

```bash
bd update bd-42 --status in_progress --json
bd update bd-42 --priority 1 --json
```

**Complete work:**

```bash
bd close bd-42 --reason "Completed" --json
```

### Issue Types

- `bug` - Something broken
- `feature` - New functionality
- `task` - Work item (tests, docs, refactoring)
- `epic` - Large feature with subtasks
- `chore` - Maintenance (dependencies, tooling)

### Priorities

- `0` - Critical (security, data loss, broken builds)
- `1` - High (major features, important bugs)
- `2` - Medium (default, nice-to-have)
- `3` - Low (polish, optimization)
- `4` - Backlog (future ideas)

### Workflow for AI Agents

1. **Check ready work**: `bd ready` shows unblocked issues
2. **Claim your task**: `bd update <id> --status in_progress`
3. **Work on it**: Implement, test, document
4. **If package conversion/update changed anything**: Create a validation issue:
   - `bd create "Validate <pkg>: <change summary>" -t bug -p 1 --deps discovered-from:<work-id> --description="Validation scope and expected outcome" --json`
5. **Run validation and record evidence**:
   - `bd update <validation-id> --notes "Validation evidence: <checks run + outcome>" --json`
   - `bd close <validation-id> --reason "Validated: <checks run + outcome>" --json`
6. **Discover new work?** Create linked issue:
   - `bd create "Found bug" --description="Details about what was found" -p 1 --deps discovered-from:<parent-id>`
7. **Complete**: `bd close <id> --reason "Done"`

### Sync Model

`bd sync` is deprecated/no-op in `bd 0.56.1+`.

Use Dolt-native sync commands:

- `bd dolt pull` to receive beads DB updates
- `bd dolt push` to publish beads DB updates
- Keep `.beads/issues.jsonl` tracked in git for audit/history, but do not rely
  on `bd sync`

### Important Rules

- ✅ Use bd for ALL task tracking
- ✅ Always use `--json` flag for programmatic use
- ✅ Link discovered work with `discovered-from` dependencies
- ✅ For every package conversion/update, open a validation bead (`bug`, `p1`, linked with `discovered-from`)
- ✅ Close validation beads only after recording explicit validation evidence
- ✅ Check `bd ready` before asking "what should I work on?"
- ❌ Do NOT create markdown TODO lists
- ❌ Do NOT use external issue trackers
- ❌ Do NOT duplicate tracking systems

For more details, see README.md and docs/QUICKSTART.md.

<!-- END BEADS INTEGRATION -->
