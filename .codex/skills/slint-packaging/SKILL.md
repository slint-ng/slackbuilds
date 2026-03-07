---
name: slint-packaging
description: SlackBuild/SLKBUILD maintenance for the Slint slackbuilds repo. Use for converting SlackBuilds to SLKBUILD, updating package versions and checksums, adjusting build steps or deps, cleaning redundant files, enforcing slackdesc line-length rules, and preparing package changes for commit.
---

# Slint Packaging

## Overview

Use this skill to standardize Slint package maintenance tasks, especially SlackBuild -> SLKBUILD conversions and version updates.

## First-use notes

On first use in a session, explicitly mention:
- `convert_slackbuild.py` is a best-effort scaffold and requires manual review.
- `convert_slackbuild.py --apply` now keeps legacy SlackBuild files in place if
  conversion gates fail; cleanup is only safe after review.
- Current `slkbuild` behavior around `dotnew` is subtler than `man 5 slkbuild`
  suggests: if `dotnew=()` is unset, regular files under `/etc` are auto-added;
  if `dotnew=()` is set, you must cover all relevant `/etc` files yourself.
- If latest version is uncertain, confirm with the user before bumping
  (Arch can be a hint, not authoritative by itself).

## Workflow

1. Inspect the package directory
- List files and read `README`, `*.info`, `slack-desc`, `doinst.sh`, patches, and the build script.
- Note upstream URLs, versioning, and any custom steps (meson, cmake, etc.).
- If a similar package already uses SLKBUILD, use it as a pattern.
- Confirm naming and headers are consistent across the directory name, `pkgname`, `slackdesc`, README, and packager header.
- For `perl-*` packages and `libwww-perl`, also read
  `references/perl-packaging.md` before deciding runtime deps, source URLs, or
  test policy.
- Avoid Arch Linux-specific carryover:
  - Do not keep `depends=`, `makedepends=`, `checkdepends=`, or `optdepends=`
    in `SLKBUILD`; `slkbuild` ignores them in this repo workflow.
  - Remove foreign PKGBUILD checksum arrays and other distro-only metadata.
  - Drop imported Arch maintainer/contributor headers unless the user
    explicitly asks to preserve a documented historical attribution.
  - Audit all changed directories and clean up these isms before finishing.
2. Decide the task
- **Conversion**: SlackBuild -> SLKBUILD
- **Update**: version bump, source checksums, deps, build flags

3. Build and dependency generation defaults
- Prefer `fakeroot slkbuild -X` for local build+clean validation.
  Running `slkbuild -X` as a non-root user fails by design.
- Generate package dependency metadata only from the built package artifact,
  never from a source directory.
- For conversions that keep the same in-tree version, require validation
  against the baseline package artifact from the Slint repos after the new
  package builds.

### SlackBuild -> SLKBUILD conversion

- Use `scripts/convert_slackbuild.py` for a best-effort scaffold, then review.
- Run `scripts/check_conversion_gates.py <pkgdir>` before treating the
  conversion as finished. It enforces `bash -n`, `slackdesc` limits, and
  conversion gate checks; add `--shellcheck` when you changed bash logic.
- If the package already exists in-tree, keep the current in-tree version
  when converting (do not bump to a newer upstream/Arch version unless the
  user explicitly asks for an update).
- Preserve the build logic exactly (configure/meson flags, install steps, docs).
- If the source tarball path differs from the package name, prefer a local
  `_srcname="foo"` helper variable instead of changing global assumptions.
- Require strict upstream tarballs in `source=()` from known, verifiable
  provenance. Do not use git/VCS sources unless absolutely necessary and
  explicitly approved with a documented reason.
- Fold simple source-tree documentation installs into `docs=()` when the old
  SlackBuild just copies or finds static doc files into `/usr/doc` or
  `/usr/share/doc`; keep manual build logic for generated docs or subdir
  layouts that `docs=()` would not preserve.
- Fold the stock package-tree ELF stripping stanza into `slkbuild`'s default
  strip pass when the old SlackBuild just does a generic `find ... | file |
  grep ELF | xargs strip --strip-unneeded` over `$PKG`; keep custom/narrow
  strip logic in `build()` and add `options=("nostrip")` manually when a
  package must not be stripped.
- Drop redundant `CFLAGS/CXXFLAGS="$SLKCFLAGS"` wrappers and `export
  CFLAGS/CXXFLAGS="$SLKCFLAGS"` lines during conversion, because `slkbuild`
  already exports those defaults. Keep explicit `--libdir`, `LIB_SUFFIX`, and
  similar build-system arguments when the upstream build needs them; `slkbuild`
  provides `LIBDIRSUFFIX`, but it does not infer install-path flags for you.
- Inline `slack-desc` into `slackdesc=(...)` and keep the handy ruler line.
- Inline `doinst.sh` into `doinst()`.
- Prefer `dotnew=()` for config files and keep `doinst()` only for non-dotnew
  post-install behavior.
- When converting old `doinst.sh` config handling:
  - move common `config etc/foo.new` or `dotnew etc/foo` cases into `dotnew=()`.
  - if you set `dotnew=()`, include every relevant regular file shipped under
    `/etc`, because current `slkbuild` only auto-discovers `/etc` files when
    `dotnew=()` is completely unset.
- Do **not** create placeholder dependency metadata during conversion.
  - Dependency metadata must be generated **after** building the package, from
    the produced package artifact (`*.txz`/`*.t?z`) using `depfinder`.
  - Keep the generated package-style dep filename:
    `<pkgname>-<pkgver>-<arch>-<pkgrel>.dep`.
  - Python packages: use `depfinder -p -f -3 <package>.txz`.
    Due to a `depfinder` option parsing bug, keep `-3` as the final option.
  - Non-Python packages: use `depfinder -f <package>.txz`.
  - Do not run `depfinder -f .` in the package directory; it can emit malformed
    output filenames (for example `..dep`).
  - Treat detected `python2` dependencies as potentially valid in this repo.
    Some packages still legitimately depend on Python 2, so do not auto-rewrite
    `python2` deps to `python3` without package-specific verification.
  - `.dep` content is comma-separated with no spaces.
  - For existing Perl packages, compare the generated `.dep` with
    `slapt-get --show <pkg>` and follow the Perl policy in
    `references/perl-packaging.md` before keeping extra runtime deps.
- For restricted/containerized environments, avoid adding `unshare -n` in
  Python wheel bootstrap steps unless explicitly required and verified.
- Keep necessary helper files (patches, scripts, extra data files) and add to `source=()` when required by the build.
- After the converted package builds, run validation with baseline manifest
  comparison:
  `bash .codex/skills/slkbuild-validation/scripts/validate_pkg.sh --require-baseline <category>/<pkg>`
- The manifest comparison lives in the validation skill, not here. This skill
  only treats passing baseline validation as part of conversion completion.
- Treat the following as blocking conversion gates until manually resolved:
  - leftover PKGBUILD/APKBUILD markers such as `prepare()`, `package()`,
    `pkgdesc=`, `subpackages=`, checksum arrays, `validpgpkeys=`, or
    `git+https://` source syntax, `depends=`/`makedepends=`/`checkdepends=`/
    `optdepends=` variables, and imported Arch maintainer identity headers.
  - raw SlackBuild variables and tempdir scaffolding such as `$PKGNAM`,
    `$VERSION`, `$CWD`, `$TMP`, or `$OUTPUT` left in the generated `build()`.
  - references to `srcdir`, `pkgdir`, `builddir`, or `startdir`.
  - network fetches inside `build()` such as `git clone`, `curl`, or `wget`.
  - remote `source=()` entries that are non-HTTPS, non-tarball, or VCS-style
    (`git://`, `.git`, `#tag=`, `#commit=`, etc.) unless explicitly approved.
  - local helper files referenced by the build but missing from `source=()`.
  - partial `dotnew=()` coverage for packages that install regular files under
    `/etc`; explicit `dotnew=()` disables slkbuild's fallback auto-discovery of
    `/etc` files.
- Remove redundant files after conversion only after the gates pass:
  - `*.SlackBuild`, `slack-desc`, `doinst.sh`, and `.info` when it is no longer used.
- Keep `.url`, `.news`, `.sha256sum`, and similar files unless you are sure they are obsolete.
- If the `dotnew` behavior is unclear, generate `build-<pkgname>.sh` from a
  known-good `SLKBUILD` and inspect the emitted `setup_dotnew()`/`setup_doinst()`
  blocks. When the manpage and generated behavior disagree, prefer the current
  `/usr/bin/slkbuild` implementation.

### Updates

- If unsure of the latest version, confirm with the user before bumping
  (Arch usually tracks latest, but do not assume blindly).
- Update `pkgver`, `source`, and any checksums.
- Use `scripts/bump_version.py` when possible to update `pkgver` and sums.
- Sync `docs=()` with what the build installs.
- For Python packages sourced from PyPI, verify the sdist's top-level directory
  name before assuming it matches the project or repo name. Common mismatches
  include package/repo names like `i3ipc-python` extracting to `i3ipc-<ver>`.
- For Python sdists that already ship generated C sources, prefer patching
  unnecessary `pyproject.toml` build requirements (for example hard Cython
  minimums) over adding heavyweight build deps blindly, if the shipped sdist is
  sufficient for the release build.
- For Python packages that self-compile during wheel creation, check upstream
  build notes for environment toggles that disable native/self compilation when
  that path is not needed for distro packaging.
- If runtime dependencies change, rebuild and regenerate the package `.dep`
  from the produced package artifact with `depfinder` in the same commit.
- Preserve existing build flags unless the update requires changes.
- For linux-firmware based packages in this repo, preserve the paired
  date/commit versioning (`<date>_<commit>`) used by Slint and verify the
  checkout/tag resolves to the expected commit before packaging.

### Kernel and firmware conventions in this repo

- Keep `a/kernel-firmware` in `a/`; do not move it to `k/` unless explicitly requested.
- Keep AMD microcode authoritative in `k/amd-microcode`; avoid duplicate AMD
  microcode package generation in `a/kernel-firmware`.
- Treat kernel outputs as split packages:
  `k/kernel`, `k/kernel-headers`, `k/kernel-source`, and `k/modules-installer`.
- Keep `k/modules-installer` tied to built kernel artifacts (explicit `KERNEL_PKG`
  override or deterministic local detection), not legacy `../../packages` assumptions.
- For `k/dkms` (3.3.x+), keep legacy helper scripts in `/usr/lib/dkms/`
  (`dkms_autoinstaller`, `common.postinst`) for existing Slint/Slackware-style
  local hook compatibility.
- Runtime kernel upgrade flow in this repo is dracut-based: wrappers use
  `dracut --no-early-microcode` then `update-grub`. If installing kernels with
  plain `upgradepkg`, run those steps manually.

## Debugging build failures

- Always preserve generated build scripts before reruns (`build-<pkg>.sh`).
- If a generated build fails with a missing source directory like
  `src/-<version>` or another obviously truncated path, check exported package
  metadata first, especially `srcname`, before debugging the upstream build.
- If a generated build reaches `tar -xf ...` and then fails with a generic
  `build() failed.` and little or no stderr, inspect command substitutions used
  under `set -e` in `build()`. A failing `find` or similar command inside
  `$(...)` can abort the build silently.
- If a package keeps failing with a hardcoded `cd "$SRC/..."` path even after
  `build()` changes, check whether `docs=()` or other `slkbuild` metadata is
  causing generated wrapper code to touch the source tree before `build()`
  runs. In that case, move doc installation into `build()` temporarily to
  isolate the real failure.
- When `set -e` is active, verify failing function return status, not only stderr output.
- Inspect slkbuild-generated helper functions (`gzip_man_and_info_pages`, post-checks, create_package) early when build() seems to pass.
- After converting or renaming an `SLKBUILD`, compare `pkgname`, `srcname`,
  doc/install paths, and the generated `build-<pkg>.sh` unpack path so renamed
  package identity changes do not silently break source-tree resolution.
- Start diagnostics narrowly in the suspected block; widen only if the first pass is inconclusive.
- Keep diagnostics reversible and remove them in a dedicated cleanup commit after success.
- If a generated tail uses test-and-and patterns (for example `[ -a file ] && rm file`) under `set -e`, account for non-zero test returns so successful builds do not abort.

## Quality checks

- `slackdesc` lines should be <= 70 chars (URLs can be longer if needed).
- `slackdesc` should be <= 10 lines.
- `bash -n SLKBUILD` must pass before attempting build validation.
- Converted `SLKBUILD`s should start with either `#!/bin/bash` or a
  `# shellcheck shell=bash ...` directive so shell tooling treats them as bash.
- For converted/updated packages, ensure dependency metadata comes from
  `depfinder` run on the built package artifact and is saved as the generated
  package-style `.dep` filename (`<pkgfull>.dep`).
- For same-version conversions, baseline manifest validation against the
  original Slint package should pass, with only allowlisted additions such as
  `usr/src/<pkg>-<ver>/...`.
- Placeholder dependency files named `<pkgname>.dep` are a sign of an
  incomplete conversion unless that exact filename was generated from the built
  package artifact for repo-specific reasons.
- In `SLKBUILD`, use plain URL sources (for example `https://...`).
  Require HTTPS release tarballs with clear versioned filenames and verifiable
  provenance. Do not use VCS-style sources (`git+https://`, `.git`, tag/commit
  fragments) unless explicitly approved as an exception.
- Prefer simple, explicit `source=()` URLs over bash substring expansion
  expressions such as `${name::1}` inside `source`; some `slkbuild -X`
  generations can mis-handle those and produce bad `cd` paths.
- If you edit a bash script, run `shellcheck` and fix reported issues.

## Landing the plane (session completion)

- When ending a work session, follow the repo `AGENTS.md` completion flow:
  1. File follow-up work in `bd` (not markdown TODOs).
  2. Run quality gates for changed code (`bash -n`, `shellcheck`, build/tests).
  3. For package conversion/update work, create a validation bead:
     `bd create "Validate <pkg>: <change summary>" -t bug -p 1 --deps discovered-from:<work-id> --description="Validation scope and expected outcome" --json`
  4. Record explicit validation evidence before closing validation beads.
  5. Update and close work beads with a clear reason.
  6. Push with the required sync order:
     `git pull --rebase && bd sync && git push && git status`.
- Critical `bd` rules:
  - Use `bd sync` for synchronization in `bd 0.55.4`.
  - Do not use `bd dolt pull` / `bd dolt push`.
  - Conversion/update work requires a linked validation bead (`bug`, `p1`,
    `--deps discovered-from:<work-id>`).
  - Do not close validation beads without evidence that:
    `bash -n`/`shellcheck` are clean, package build completed, and basic smoke
    tests passed.

## Resources

### scripts/
- `check_slackdesc_len.py`: Validate slackdesc line length and line count.
- `check_conversion_gates.py`: Check converted package dirs for leftover
  foreign packaging markers, legacy files, placeholder deps, `slackdesc`
  limits, and `bash -n` failures.
- `convert_slackbuild.py`: Best-effort SlackBuild -> SLKBUILD scaffold.
- `bump_version.py`: Update `pkgver` and refresh checksums if present.
- `sync_dep_files.py`: Legacy helper for `<pkgname>.dep` from `depends=()`;
  do not use for package dependency metadata in this repo workflow
  (`depfinder` on built package artifacts is required).

### references/
- `references/perl-packaging.md`: Perl/CPAN-specific dependency, testing, and
  source URL policy for Slint conversions.

### manpages
- `man 5 slkbuild`: documentation of the slkbuild format.
- `man 8 slkbuild`: documentation for the slkbuild utility itself
- `man 1 depfinder`: documentation of depfinder
