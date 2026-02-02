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
