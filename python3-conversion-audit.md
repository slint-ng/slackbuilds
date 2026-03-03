# Python 3 Conversion Audit

## Purpose

This file separates packages into three groups:

1. keep explicit `python3.11` for now
2. switch from `python3.11` to `python3` after `/usr/bin/python3` is made to mean Python 3.11
3. packages still building for both `python3.9` and `python3.11`, which should be simplified after the migration

The key rule is:

- do not blindly replace `python3.11` with `python3` until `python3` is reliably Python 3.11

## Group 1: Keep Explicit `python3.11` For Now

These packages are version-specific, bootstrap-sensitive, or core ABI packages where explicit 3.11 targeting is still justified during the migration.

### Interpreter And Bootstrap Packages

- `d/python3.11`
- `d/python-pip3.11`
- `d/python-setuptools3.11`
- `l/python-installer3.11`
- `l/python-wheel3.11`
- `l/python-packaging3.11`
- `l/python-setuptools_scm3.11`
- `l/python-hatch-vcs3.11`
- `l/python-brotli3.11`
- `l/python3-hatchling3.11`

### Core ABI-Sensitive Python Bindings

- `d/gobject-introspection3.11`
- `d/speech-dispatcher3.11`
- `l/dbus-python3.11`
- `l/pycairo3.11`
- `l/pygobject3.11`

### Desktop Packages That Explicitly Target The 3.11 Runtime

- `xap/orca`
- `xap/cthulhu`
- `xap/fontforge`

These should stay explicit until the system-level Python 3 switch is complete, because they either:

- depend on 3.11-specific bindings
- patch scripts to `python3.11`
- or document that they must build against 3.11

## Group 2: Switch To `python3` After The Default Flip

These packages have generic Python 3 package names and do not benefit from staying hardcoded to `python3.11` once `/usr/bin/python3` points to Python 3.11.

### Generic Python 3 Libraries

- `l/python3-setproctitle`
- `l/python3-msgpack`
- `l/python3-pluggy`
- `l/python3-pyautogui`
- `l/python3-pillow`
- `l/python3-trove-classifiers`
- `t/python3-gTTS`

### Generic Python Libraries With Non-`python3-*` Package Names

- `l/python-requests`
- `l/python-certifi`
- `l/python-idna`
- `l/python-websockets`
- `l/python-pep517_3.11`
- `l/python-pycryptodomex`
- `l/python-espeak`
- `l/liblouis` for its Python binding install step
- `ap/mutagen`
- `l/yt-dlp-ejs`

These should be converted from explicit `python3.11` command use to `python3` only after the default interpreter is changed.

### Why These Are Good Candidates

They are good candidates because:

- their package names are already generic
- they do not need parallel 3.9 and 3.11 installs long term
- keeping hardcoded `python3.11` in them would create unnecessary cleanup later

## Group 3: Dual-Build Cleanup Candidates

These packages still explicitly build for both `python3.9` and `python3.11`. They should be simplified once the Python 3.11 migration is complete.

- `l/python3-editables`
- `l/python3-pygetwindow`
- `l/python3-mouseinfo`
- `l/python3-calver`
- `l/python3-pathspec`
- `l/python3-pytweening`
- `l/python-attrs`
- `l/python-chardet`
- `l/python-pyenchant`

Expected cleanup after the migration:

- drop the `python3.9` build path
- build once with `python3`
- verify install path lands under the active Python 3.11 site-packages

## Packages That Should Be Reviewed Carefully

These are not immediate mass-replace candidates:

- anything with `3.11` in the package name
- anything that installs compiled Python extension modules
- anything with notes saying it must be built against 3.11
- anything patching shebangs to `python3.11`

## Recommended Conversion Order

1. First change the system so `python3` means `python3.11`.
2. Then update Group 2 packages from `python3.11` to `python3`.
3. Then simplify Group 3 dual-build packages to one Python 3 build.
4. Only after that should Group 1 packages be reconsidered for renaming or de-versioning.

## Practical Rule Of Thumb

Use this test:

- If the package name itself is versioned for 3.11 or it provides core bindings, keep explicit `python3.11` for now.
- If the package is a normal Python 3 library or app with a generic package name, move it to `python3` after the default interpreter flip.

## Immediate Next Targets

Once `/usr/bin/python3` points to Python 3.11, the first easy wins should be:

- `l/python3-setproctitle`
- `l/python3-msgpack`
- `l/python3-pluggy`
- `l/python3-pyautogui`
- `l/python3-pillow`
- `l/python-requests`
- `l/python-certifi`
- `l/python-idna`

These give a clean early wave of generic Python 3 packages without touching the most delicate core packages first.
