# Package Agent Workflow

This repository now has a package-scoped workflow for parallel conversion and
validation work without paying for full extra checkouts.

## Goal

Use one branch and one sparse worktree per package, then hand the same package
through three roles:

- converter
- validator
- integrator

The unit of work is always one package directory.

## Helper Scripts

- `mkpkgwt`
  Creates a minimal sparse worktree for one package.
- `convertpkg`
  Creates the package worktree and prints the standard conversion flow.
- `pkghandoff`
  Emits the converter -> validator handoff block.
- `validatepkgwt`
  Runs `bash -n`, reports `shellcheck`, and calls the validation helper against
  the package worktree path.
- `integratepkg`
  Fast-forwards a validated package branch onto the target branch and can clean
  up the source worktree and branch.
- `rmpkgwt`
  Removes linked package worktrees and optionally deletes their branches.
- `dispatchpkg`
  Prints the exact converter, validator, and integrator commands for one
  package, including ready-to-paste `codex exec` prompts that explicitly spawn
  the matching Codex agent role.

## Prompt Templates

Templates for agent runs live here:

- `agent-prompts/converter-agent.md`
- `agent-prompts/validator-agent.md`
- `agent-prompts/integrator-agent.md`

Repo-local Codex agent roles are configured here:

- `.codex/config.toml`
- `.codex/agents/package-converter.toml`
- `.codex/agents/package-validator.toml`
- `.codex/agents/package-integrator.toml`

The registered role names are:

- `package-converter`
- `package-validator`
- `package-integrator`

Prefer the repo-local agent roles for reusable Codex multi-agent runs. The
markdown templates remain the plain-text equivalents.

The generated `codex exec` commands tell Codex to spawn the named role and wait
for its result. Simply mentioning a role name is not enough; the role is only
applied when Codex actually spawns an agent with that `agent_type`.

Use helper scripts by absolute path from the main checkout. Sparse package
worktrees do not include `Maintenance-of-the-repository/` by default.

## Recommended Flow

1. Generate the command set for one package:
   ```bash
   /home/sektor/projects/slackbuilds/Maintenance-of-the-repository/dispatchpkg \
     --id 123 \
     --work-bead slackbuilds-123 \
     --validation-bead slackbuilds-124 \
     a/dcron
   ```
2. Run the printed converter command.
3. Convert or update the package in its sparse worktree.
4. Build it with `fakeroot slkbuild -X`.
5. Run the printed validator command.
6. If validation passes, run the printed integrator command from the integration
   checkout.

## Branch and Worktree Layout

Recommended names:

- package branch: `conv/<id>-<category>-<pkg>`
- package worktree: `/tmp/slackbuilds-wt/conv-<id>-<category>-<pkg>`
- integration branch: usually `main`

Each package branch should touch only its own package directory whenever
possible. Shared helper changes should be treated as separate work because they
increase conflict risk.

## Sparse Worktree Notes

`mkpkgwt` defaults to:

- `AGENTS.md`
- `.codex`
- `<category/package>`

Optional flags add more paths only when needed:

- `--beads`
- `--templates`
- `--full-templates`
- `--add <path>`

This keeps package worktrees small enough for low-space VMs.

## Conversion Notes

- Treat `convert_slackbuild.py` as a scaffold only.
- Keep legacy SlackBuild files until conversion gates pass.
- For same-version conversions, require baseline manifest validation.
- Generate `.dep` metadata from the built package artifact, not from the source
  tree.

## Validation Notes

Preferred validator entry point:

```bash
/home/sektor/projects/slackbuilds/Maintenance-of-the-repository/pkghandoff \
  --worktree /tmp/slackbuilds-wt/conv-123-a-dcron \
  --work-bead slackbuilds-123 \
  --validation-bead slackbuilds-124 \
  a/dcron | \
/home/sektor/projects/slackbuilds/Maintenance-of-the-repository/validatepkgwt \
  --handoff - \
  --worktree /tmp/slackbuilds-wt/conv-123-a-dcron \
  --require-baseline
```

`validatepkgwt` adds:

- `bash -n` result
- `shellcheck` result
- validator output from `slkbuild-validation`
- depfile status and any validator-reported post-install library symlink note

## Integration Notes

`integratepkg` is intentionally strict:

- it must run from a clean integration worktree
- it only uses `git merge --ff-only`
- it stops if the source branch is not rebased on the target branch
- it can remove the source worktree and delete the source branch after landing

Example:

```bash
cd /home/sektor/projects/slackbuilds
/home/sektor/projects/slackbuilds/Maintenance-of-the-repository/integratepkg \
  --target main \
  --worktree /tmp/slackbuilds-wt/conv-123-a-dcron \
  --cleanup \
  --force-cleanup
```

If fast-forward is not possible, rebase the package branch, re-run validation if
needed, and then try landing again.

## Landing Batch

After the validated branches you want are landed:

```bash
git pull --rebase
bd sync
./build-package.sh -f --dependencies
./build-package.sh -f
git push
git status
```

Keep this step serialized. The dependency-only command is the cheap graph gate:
it confirms the full repository build queue can be computed before starting the
actual build/install pass.

`build-package.sh -f` with no package path is the full repository build mode. It
builds every indexed `SLKBUILD` package in dependency order, reuses matching
staged artifacts, and still regenerates package-style `.dep` files from built
artifacts. Since curated `pkg.dep` tracking is being phased out, dependency
resolution falls back to current artifact-style depfiles when the curated file
is absent.
