# Converter Agent Prompt

Use the `package-converter` agent role.

Within that role, use the `slint-packaging` skill.

You own exactly one package conversion/update:

- Package: `<category/package>`
- Work bead: `<work-bead>`
- Validation bead: `<validation-bead or unset>`
- Worktree: `<worktree-path or unset>`
- Branch: `<branch or unset>`

Operating rules:

- Work on this package only. Do not touch unrelated packages or shared helpers unless the task explicitly requires it.
- Use the repository helpers instead of inventing your own layout.
- Call helper scripts by absolute path from the main checkout. Sparse package worktrees do not include `Maintenance-of-the-repository/` by default.
- Treat `convert_slackbuild.py` as a scaffold only; manual review is mandatory.
- Keep legacy SlackBuild files until conversion gates pass.
- For same-version conversions, validation must include baseline manifest comparison.
- Do not merge, push, or close the validation bead yourself.

Execution flow:

1. Create or enter the sparse package worktree.
   Example:
   ```bash
   <repo-root>/Maintenance-of-the-repository/convertpkg \
     --work-bead <work-bead> \
     --validation-bead <validation-bead> \
     --id <short-id> \
     <category/package>
   ```
2. Inspect the package files and perform the conversion/update with `slint-packaging`.
3. Run the conversion gates:
   ```bash
   python3 .codex/skills/slint-packaging/scripts/check_conversion_gates.py <abs-package-dir>
   python3 .codex/skills/slint-packaging/scripts/check_conversion_gates.py --shellcheck <abs-package-dir>
   ```
4. Build with:
   ```bash
   cd <abs-package-dir>
   fakeroot slkbuild -X
   ```
5. If the build succeeds, emit a validator handoff block:
   ```bash
   <repo-root>/Maintenance-of-the-repository/pkghandoff \
     --worktree <worktree-path> \
     --work-bead <work-bead> \
     --validation-bead <validation-bead> \
     <category/package>
   ```
6. Record what changed, note any caveats, and hand off to the validator.

Required output at the end:

- Short change summary
- Exact changed files
- Build result
- The `pkghandoff` block
- First blocker if the package could not be validated yet
