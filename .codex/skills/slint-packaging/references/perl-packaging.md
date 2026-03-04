## Perl Packaging

Use this reference for `perl-*` packages and `libwww-perl` in `l/`.

## Runtime deps

- Treat `slapt-get --show <pkg>` as the runtime dependency baseline for
  existing Slint Perl packages.
- Generate the package-style `.dep` from the built artifact with `depfinder`,
  then compare it with `slapt-get --show <pkg>`.
- If `depfinder` is empty and `slapt-get --show` is empty, keep the generated
  `.dep` empty.
- If `depfinder` finds extra pure-Perl edges but `slapt-get --show` does not,
  do not keep those extra runtime deps unless a smoke test proves they are
  required at runtime.
- Old `.info` `REQUIRES` values are hints about stack order or likely missing
  helpers, not automatic runtime dependency metadata.

## Test helpers

- Missing CPAN-style test modules should usually be treated as local build
  blockers, not runtime deps to encode in `.dep`.
- Install helper packages locally when needed to clear `make test`, then keep
  runtime `.dep` aligned with the distro view.
- Package naming usually follows `Module::Name -> perl-Module-Name`.
- Typical examples from this stack:
  - `Test::Fatal -> perl-Test-Fatal`
  - `Module::Build::Tiny -> perl-Module-Build-Tiny`
  - `Test::Needs -> perl-Test-Needs`

## Network tests

- Upstream live internet tests are not reliable build gates for repo packaging.
- If a test depends on third-party hosts, changing redirects, or external TLS
  behavior, patch or skip it for packaging.
- Prefer a narrow backport of the upstream test fix over a version bump when
  the package should stay on the current in-tree version.
- `perl-net-http` is the model case:
  - backport the upstream live-test fixes
  - keep the package at the current in-tree version
  - do not add fake runtime deps just because the test suite needed internet

## Known package quirks

- `perl-Term-ReadLine-Gnu` tests can fail under non-tty builders when
  `TERM=dumb`, because `Term::ReadLine::Gnu` intentionally falls back to
  `Term::ReadLine::Stub` in that environment. Keep test runs with:
  `TERM=xterm INPUTRC=/dev/null make test`.
- `perl-Test-Warnings` (`0.026-x86_64-1slint`) baseline payload is historically
  doc-only. A corrected conversion that actually installs module/manpage
  content will show large manifest additions versus baseline.

## Source URLs

- Prefer explicit CPAN URLs in `source=()` over bash substring tricks.
- If an old CPAN author path returns 404, resolve the correct author path from
  MetaCPAN or another authoritative CPAN index and then pin the full URL.
- Keep the in-tree version unless the user explicitly asked for an update.

## Manifest expectations

- Same-version Perl conversions should normally differ from baseline only by
  the allowlisted `usr/src/<pkg>-<ver>/SLKBUILD` addition.
- Do not assume every converted Perl package should also ship a legacy-named
  SlackBuild copy under `/usr/doc`.
- If baseline diff shows an extra doc file such as
  `usr/doc/<pkg>-<ver>/<pkg>.SlackBuild`, treat that as a real regression and
  remove the extra install step unless baseline packaging proves otherwise.
