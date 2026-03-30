# gcc-libs Dependency Cleanup and Rebuild Plan

## Problem

On 2026-03-30, `slapt-get -s --upgrade` excluded `gnote` with:

`gnote: Depends: gcc-libs`

`gcc-libs` is an Arch package name. It is not a real Slint package, so any
published `.dep` file that still names it can block upgrades.

## What was changed

The repository now normalizes `gcc-libs` to real Slint provider tokens in two
places:

- tracked `SLKBUILD` `depends=()` metadata
- tracked curated `*.dep` files

`build-package.sh` also normalizes stray `gcc-libs` tokens while merging
curated deps, `SLKBUILD` deps, and raw `depfinder` output. This prevents the
wrong token from being reintroduced into generated artifact depfiles.

## Provider mapping used here

The replacements below were chosen from package build logic and, where
available, installed ELF `NEEDED` entries.

### `aaa_libraries|gcc`

Use this when the package needs `libgcc_s.so.1` but not `libstdc++.so.6`.

- `ap/hts_engine_API`
- `ap/open-jtalk`
- `l/libblkio`

### `aaa_libraries|gcc` and `aaa_libraries|gcc-g++`

Use these when the package needs both `libgcc_s.so.1` and `libstdc++.so.6`.

- `ap/glslang`
- `ap/gnote`
- `ap/grub-customizer`
- `d/rust`
- `l/libxml++5.0`
- `xap/webkit2gtk`
- `y/libgme`

### `llvm`

Use this when the package is explicitly built against LLVM libc++ instead of
libstdc++.

- `ap/tdlib`

### no runtime compiler package dep

Use no compiler-runtime dep when the package only ships data.

- `ap/open-jtalk-mecab-naist-jdic`

## Affected packages

- `ap/glslang`
- `ap/gnote`
- `ap/grub-customizer`
- `ap/hts_engine_API`
- `ap/open-jtalk`
- `ap/open-jtalk-mecab-naist-jdic`
- `ap/tdlib`
- `d/rust`
- `l/libblkio`
- `l/libxml++5.0`
- `xap/webkit2gtk`
- `y/libgme`

## Rebuild and publish order

If package outputs are rebuilt and published incrementally, use this order:

1. `ap/gnote`
2. `ap/hts_engine_API`
3. `ap/open-jtalk`
4. `ap/open-jtalk-mecab-naist-jdic`
5. `y/libgme`
6. `ap/glslang`
7. `ap/grub-customizer`
8. `l/libxml++5.0`
9. `l/libblkio`
10. `ap/tdlib`
11. `d/rust`
12. `xap/webkit2gtk`

## Why this order

1. `gnote` first because it is the package currently proven to block
   `slapt-get --upgrade`.
2. `hts_engine_API`, `open-jtalk`, and `open-jtalk-mecab-naist-jdic` are a
   small related cluster and should be corrected together.
3. `libgme`, `glslang`, `grub-customizer`, `libxml++5.0`, `libblkio`, and
   `tdlib` are independent fixes with smaller blast radius than `rust` or
   `webkit2gtk`.
4. `rust` later because it is heavier to rebuild and its package ships both
   Rust and C++-linked components.
5. `webkit2gtk` last because it is the longest and riskiest rebuild in this
   set.

If the repo metadata is regenerated from the git tree in one batch after all
builds complete, the order matters much less. The sequence above is for staged
or piecemeal publication.

## Publishing notes

- Rebuild each package and regenerate the package-style depfile from the built
  artifact.
- Do not rely on the tracked curated `pkg.dep` file alone if a newer
  `<pkg>-<ver>-<arch>-<rel>.dep` will be published with the artifact.
- For `gnote` and `rust`, local untracked artifact depfiles may still exist in
  working directories; regenerate and publish fresh ones from the final rebuilt
  package artifacts.

## Minimum verification before closing follow-up validation

- `bash -n` and `shellcheck` return no errors for the changed `SLKBUILD`s and
  `build-package.sh`.
- Each rebuilt package compiles in the target Slint environment.
- Basic smoketests pass:
  - `gnote`: binary starts far enough to show help or version output
  - `open-jtalk`: executable runs
  - `open-jtalk-mecab-naist-jdic`: expected dictionary payload exists
  - `tdlib`: installed library links cleanly against libc++
  - `rust`: `rustc -V` and `cargo -V`
  - `webkit2gtk`: `jsc --help` or MiniBrowser startup smoke test
