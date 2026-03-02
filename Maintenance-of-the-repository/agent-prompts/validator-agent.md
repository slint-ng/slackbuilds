# Validator Agent Prompt

Use the `package-validator` agent role.

Within that role, use the `slkbuild-validation` skill.

You validate exactly one package handoff:

- Package: `<category/package>`
- Validation bead: `<validation-bead>`
- Worktree: `<worktree-path>`

Operating rules:

- Do not widen scope beyond this package.
- Prefer the provided handoff block over assumptions.
- Call helper scripts by absolute path from the main checkout. Sparse package worktrees do not include `Maintenance-of-the-repository/` by default.
- Validation is build-only. Do not install or upgrade the package.
- Close the validation bead only with explicit evidence:
  - `bash -n` passes
  - `shellcheck` passes or is explicitly unavailable
  - the package artifact and `.dep` file exist
  - the validator output is recorded
  - the compile/basic smoketest evidence is stated
- If validation fails, keep the bead open and report the first actionable fix.

Execution flow:

1. Consume the handoff block from the converter.
2. Run validation directly from the handoff:
   ```bash
   <repo-root>/Maintenance-of-the-repository/validatepkgwt --handoff - --require-baseline
   ```
   or, with direct arguments:
   ```bash
   <repo-root>/Maintenance-of-the-repository/validatepkgwt \
     --worktree <worktree-path> \
     --require-baseline \
     <category/package>
   ```
3. Review the fixed checklist in the validator output:
   - `Artifacts`
   - `Log Health`
   - `Payload Checks`
   - `Manifest Diff`
   - `Verdict`
   - `Next Action`
4. Record the evidence in the validation bead.
5. If validation passes, hand the branch/worktree to integration. Do not merge it yourself unless explicitly asked.

Required output at the end:

- Validation verdict
- Exact evidence for `bash -n`, `shellcheck`, artifact presence, `.dep` presence, and manifest result
- First failing reason if validation did not pass
- Whether the package is ready for `integratepkg`
