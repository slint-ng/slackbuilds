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
- Repository mirror updates are not synced from this VM. Prepare packages and
  matching `.dep` files in `/home/storm/staging`; the user copies that staging
  directory to their main machine before running mirror update/upload workflows.

## Landing the Plane (Session Completion)

**When ending a work session**, complete all steps below:

1. File follow-up work in `bd` (no markdown TODO tracking).
2. Run quality gates when code changed (tests/lint/build as applicable).
3. For package conversion/update work, create a validation bead:
   `bd create "Validate <pkg>: <change summary>" -t bug -p 1 --deps discovered-from:<work-id> --description="Validation scope and expected outcome" --json`
4. Record explicit validation evidence before closing validation beads.
5. Update and close work beads with clear reasons.
6. Push code changes:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # should show up to date with origin
   ```

**Critical rules:**
- Use `bd sync` for bead synchronization in `bd 0.55.4`.
- Do not use `bd dolt pull`/`bd dolt push` for the `0.55.4` workflow.
- For package conversion/update work, validation beads are mandatory (`bug`,
  `p1`, linked with `discovered-from:<work-id>`).
- Do not close validation beads without explicit evidence in notes/reason, to include the following:
  - shellcheck/bash -n return no errors.
  - the package compiles
  - relatively basic smoketests pass


<!-- BEGIN BEADS INTEGRATION -->
## Issue Tracking

This project uses **bd (beads)** for issue tracking.
Run `bd prime` for workflow context, or install hooks (`bd hooks install`) for
auto-injection.

**Quick reference:**
- `bd ready --json` - Find unblocked work
- `bd create "Title" --type task --priority 2 --json` - Create issue
- `bd update <id> --status in_progress --json` - Claim work
- `bd close <id> --reason "Completed" --json` - Complete work
- `bd sync` - Sync beads state for commit/push workflows in `bd 0.55.4`

<!-- END BEADS INTEGRATION -->
