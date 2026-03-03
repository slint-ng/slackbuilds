# Python 3.11 Migration Roadmap For Slint

## Goal

Move Slint to a single supported Python 3 runtime:

- `python3` must mean `python3.11`
- Python 3 packages must build against `python3.11`
- Python 3 applications must run against `python3.11`
- `python3.9` must stop being the default `python3`
- If `python3.9` remains installed during transition, it must only be used when explicitly called as `python3.9`

This document is written as a practical roadmap, not a theory note.

## Why This Needs To Happen

Right now the system is split across:

- `python2`
- `python3.9`
- `python3`
- package names that sometimes mean "generic Python 3"
- package names that sometimes mean "built for a specific Python 3 minor"

That causes four recurring problems:

1. A package appears to be installed, but it was built for the wrong Python version.
2. A package builds with whichever `python3` happens to be first on the system.
3. Applications import extension modules compiled for a different Python ABI and fail at runtime.
4. Package names become misleading, so dependency metadata stops being trustworthy.

For Cthulhu, this is already visible:

- Python 3.9 builds run, but braille support breaks.
- Python 3.11 builds handle braille correctly, but parts of the dependency stack are incomplete.

That means the right answer is not "support both forever." The right answer is "pick one Python 3 and rebuild cleanly."

## The Core Policy Decision

Slint should adopt this rule:

1. The distro supports one primary Python 3 minor at a time.
2. Today, that target should be Python 3.11.
3. `/usr/bin/python3` must launch Python 3.11.
4. All generic Python 3 package builds must use `/usr/bin/python3`.
5. Python 3.9 may temporarily remain installed, but only as an explicit compatibility tool invoked as `python3.9`.
6. New package work must not add more dual-version Python 3 complexity.

If this policy is not enforced first, the rest of the migration will drift.

## End State

The migration is complete when all of the following are true:

- `python3 --version` reports Python 3.11
- packages with Python shebangs using `python3` run under Python 3.11
- all Python extension modules used by packaged applications are rebuilt for Python 3.11
- dependency metadata no longer mixes `python-setproctitle`, `setproctitle3.11`, and similar names without a reason
- Cthulhu, Orca, Fenrir, and other key desktop tools work under the same Python 3 stack
- Python 3.9 is either removed or clearly marked as a legacy compatibility interpreter

## Important Warning

Do not start by deleting Python 3.9.

That is the wrong first move.

First:

- decide the target policy
- make `python3` point to 3.11
- rebuild the Python 3 dependency graph
- validate the critical applications

Only after that should Python 3.9 be removed or downgraded to an explicit compatibility role.

## Glossary

- **Interpreter**: the Python executable, such as `python3.11`
- **ABI**: the compiled binary interface used by C extensions
- **Extension module**: a Python package with compiled `.so` files, such as `pycairo`, `setproctitle`, or `speechd`
- **Pure Python package**: a Python package made only of `.py` files, such as `requests` or `webcolors`
- **Single source of truth**: one authoritative Python 3 interpreter for builds and runtime

## Big Picture Strategy

This migration should happen in phases.

### Phase 1: Freeze The Rules

Before rebuilding anything, define these rules and stick to them:

1. `python3` means `python3.11`
2. package build scripts must not guess between `python3.9` and `python3.11`
3. generic Python 3 packages should not use minor-version suffixes unless parallel installs are intentionally required
4. if a package must temporarily remain version-specific, that must be documented as transitional only

### Phase 2: Inventory The Python 3 Package Graph

Create three package lists:

1. Python 3 interpreters
2. Python 3 libraries and bindings
3. Python 3 applications

Then classify each package as one of these:

- pure Python
- compiled extension
- introspection binding
- application
- build helper

This classification matters because rebuild order depends on it.

### Phase 3: Make Python 3.11 The Default `python3`

This is the key pivot point.

After this phase:

- `python3` must be 3.11
- `python3-config` must be the 3.11 one
- `pip3` must map to the 3.11 environment if it exists
- `/usr/bin/env python3` must resolve to Python 3.11

Python 3.9 can still exist, but only as `python3.9`.

### Phase 4: Rebuild The Python 3 Core Stack

Rebuild core packages first, because almost everything else depends on them.

Suggested early rebuild set:

- `python3` itself, with `python3` symlink policy settled
- setuptools/build/install tooling
- wheel/build helpers
- packaging support libraries
- core bindings such as `pygobject`, `pycairo`, `python-atspi`, `dasbus`

### Phase 5: Rebuild The Python 3 Extension Layer

After the core stack, rebuild packages that ship binary Python modules or tightly couple to the interpreter:

- `setproctitle`
- `speechd` Python bindings
- `pycairo`
- `pygobject`
- `python-atspi`
- any package installing `.so` files under `site-packages`

These are the packages most likely to fail if built for the wrong Python minor.

### Phase 6: Rebuild Pure Python Libraries

Once the extension layer is stable, rebuild or rename pure Python libraries as needed:

- `pluggy`
- `tomlkit`
- `requests`
- `webcolors`
- `pdf2image`
- `msgpack`
- `tornado`
- `pytesseract`
- similar packages

Pure Python packages are easier, but they still need consistent package naming and dependency metadata.

### Phase 7: Rebuild User-Facing Applications

Do this after the libraries:

- Cthulhu
- Orca
- Fenrir
- LightDM settings
- Mint menu or other desktop tools using Python

Applications are where users will see the damage if the lower layers are inconsistent.

### Phase 8: Clean Up Naming And Metadata

Once things run under Python 3.11, normalize naming and dependency declarations.

### Phase 9: Remove Or Isolate Python 3.9

Only after validation:

- remove `python3.9` packages from normal dependency paths, or
- keep them only as legacy tools explicitly invoked as `python3.9`

Do not leave a half-migrated state where `python3` and package metadata still disagree.

## Recommended Naming Policy

Slint should pick one naming convention and apply it consistently.

Recommended long-term rule:

- default interpreter package should be `python3`
- default packaging tools should be `python3-pip` and `python3-setuptools`
- generic Python 3 libraries should use stable names without a minor suffix
- dependency metadata for Python 3 libraries should refer to those stable names

Examples:

- `python3-pluggy`, not `pluggy3.11`
- `python3-dasbus`, not `dasbus3.11`
- `python3-tomlkit`, not `tomlkit3.11`

For historically messy packages like `setproctitle`, pick one package name and make everything depend on that one package name.

The code imports the module `setproctitle`. It does not care whether the package is called:

- `setproctitle`
- `setproctitle3.11`
- `python-setproctitle`

But package metadata does care. That is where the breakage comes from.

## Transitional Naming Policy

If a full rename cannot happen at once, use this temporary rule:

1. keep the existing package if needed for bootstrapping
2. choose the future canonical package name
3. update dependent package metadata in batches
4. remove old aliases only after reverse dependencies are updated

The key point is to avoid open-ended dual naming.

## Build Environment Rules

Every Python 3 package build should follow these rules:

1. use `/usr/bin/python3`
2. never hardcode `/usr/bin/python3.9` unless that package is explicitly a Python 3.9 compatibility package
3. do not hardcode `site-packages` paths with `python3.9`
4. prefer tools invoked through the active interpreter

Examples:

```bash
python3 -m build --wheel --no-isolation
python3 -m installer --destdir="$PKG" dist/*.whl
```

Avoid this in generic Python 3 packages:

```bash
python3.9 -m build
```

unless the package is intentionally version-locked.

## Rebuild Order

This is the order a newcomer should follow.

### Step 1: Confirm The Current Reality

Record:

- output of `python3 --version`
- output of `python3.9 --version`
- output of `python3.11 --version`
- where `/usr/bin/python3` points
- current Python 3 `site-packages` directories

If `python3` is not already Python 3.11, note that as the first system-level change to make.

### Step 2: Build A Package Inventory

Search the repo for:

- `python3.9`
- `python3.11`
- `#!/usr/bin/python3`
- `#!/usr/bin/env python3`
- `site-packages`
- `python-setproctitle`
- `setproctitle3.11`

This tells you which packages are still tied to old assumptions.

### Step 3: Identify Extension Packages

Mark every package that installs compiled Python modules.

Typical signs:

- `.so` files in `site-packages`
- use of Cython, Meson, setuptools extension builds, or compiled bindings

These must be rebuilt early.

### Step 4: Switch The Meaning Of `python3`

Make the distro decision that:

- `python3` is Python 3.11

This is likely a system packaging change outside this repo, but it must happen before the rebuild wave is considered complete.

### Step 5: Rebuild Python Build Tools

Rebuild the packaging toolchain first:

- setuptools
- wheel
- build
- installer
- packaging support libraries

If the build tools are inconsistent, the rest of the migration becomes unreliable.

### Step 6: Rebuild Core Bindings

Rebuild the packages that are foundational for desktop accessibility and Python 3 apps:

- `pygobject`
- `pycairo`
- `python-atspi`
- `python3-dasbus`
- speech dispatcher Python bindings
- `setproctitle`

### Step 7: Rebuild Pure Python Support Libraries

These include:

- `pluggy`
- `tomlkit`
- `requests`
- `msgpack`
- `tornado`
- `webcolors`
- `pdf2image`
- `pytesseract`

### Step 8: Rebuild High-Value Applications

Suggested order:

1. Orca
2. Cthulhu
3. Fenrir
4. other Python desktop tools

This order is sensible because accessibility tools are directly affected by interpreter mismatches.

### Step 9: Validate Critical Features

For each application, test the features users actually care about.

For Cthulhu:

- startup
- speech output
- braille output
- preferences
- D-Bus control if used
- OCR plugin if packaged
- AI assistant only if intended to ship

For Orca:

- startup
- speech
- braille
- desktop navigation

For Fenrir:

- startup
- console speech
- configuration tools

### Step 10: Clean Dependency Metadata

Once packages work, normalize the dependency files and build scripts.

Do not leave old names behind unless they are explicit compatibility shims with a removal date.

## How To Decide What Is Required Versus Optional

A package should be considered **required** if the application cannot perform its core job without it.

A package should be considered **optional** if it only enables an add-on feature.

For Cthulhu, a practical split is:

Required:

- `pygobject`
- `python-atspi`
- `pycairo`
- `pluggy`
- `tomlkit`
- speech dispatcher bindings if speech is considered a core feature

Optional:

- `piper-tts`
- `pdf2image`
- `webcolors`
- `pytesseract`
- `msgpack`
- `tornado`
- `pyautogui`

Braille support is a special case:

- if Slint wants braille support as a first-class accessibility feature, then `brlapi` and `liblouis` are not really optional in practice

## Cthulhu-Specific Notes

The immediate Cthulhu lesson is simple:

- stop trying to support it as both a 3.9 app and a 3.11 app
- choose 3.11
- complete the 3.11 dependency chain

The dependency checker at `dep.py` in the repo root can be used during validation:

```bash
python3 dep.py
python3.11 dep.py
```

The second command is especially important during migration.

## What Can Go Wrong

### Problem: A Package Builds But Fails At Runtime

Cause:

- it found headers or metadata for one Python version but was imported by another

Fix:

- rebuild it with the correct interpreter and verify the installed path

### Problem: A Pure Python Package Exists But Is Not Found

Cause:

- wrong `site-packages` path
- wrong package name in dependency metadata
- built into a version-specific location not used by `python3`

Fix:

- normalize the install path and metadata

### Problem: A GI Module Imports The Wrong Version

Cause:

- mixed GTK3 and GTK4 assumptions
- introspection modules not rebuilt consistently

Fix:

- verify `gi.require_version()` usage and package stack consistency

### Problem: The Build Script Hardcodes Python 3.9

Cause:

- old packaging assumptions

Fix:

- update it to use `python3`, after `python3` is made to mean 3.11

## Validation Checklist

A package is not considered migrated until all of these are true:

1. it builds with `python3` resolving to 3.11
2. it installs into the expected Python 3.11 `site-packages`
3. it imports successfully under `python3`
4. it passes basic smoke tests
5. dependency metadata matches reality

For compiled modules, also verify:

6. the package does not leave behind stale `.so` files for the old interpreter path

## Suggested Work Plan For A New Contributor

If you are new to this repo, do the work in this order:

1. read this file fully
2. confirm what `python3` currently means on the system
3. list all packages mentioning `python3.9`
4. list all packages mentioning `python3.11`
5. identify the Python 3 core packages
6. switch the system policy so `python3` means 3.11
7. rebuild the Python build toolchain
8. rebuild core extension modules
9. rebuild pure Python libraries
10. rebuild critical applications
11. test accessibility-critical apps first
12. clean dependency names
13. remove or isolate Python 3.9

## What Not To Do

Do not:

- delete Python 3.9 before rebuilding the stack
- keep changing package naming conventions package by package without a policy
- let generic Python 3 packages keep hardcoding 3.9
- assume a package is good just because it built once
- mix runtime validation and naming cleanup into the same blind batch

## Short Version

The migration plan is:

1. decide that Python 3.11 is the only supported Python 3 target
2. make `python3` point to Python 3.11
3. rebuild Python 3 build tools
4. rebuild Python 3 bindings and extension modules
5. rebuild pure Python libraries
6. rebuild applications
7. validate Cthulhu, Orca, Fenrir, and other critical tools
8. normalize package naming
9. remove or isolate Python 3.9

That is the clean path out of the current split-brain state.
