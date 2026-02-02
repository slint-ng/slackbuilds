# Changelog

Notable changes to Numen will be documented in this file.
See ./phrases/CHANGELOG.md for changes to the default phrases.

## [0.7](https://git.sr.ht/~geb/numen/refs/0.7)

### Added

- A test.
- The actions: run, load, hwheel, keydown, keyup, keydelay, keyhold,
  typedelay and typehold.
- The special phrase \<complete>.
- Noise recognition of blow, hiss and shush.
- A --verbose option.
- An --audiolog=FILE option.

### Changed

- Overhauled to be one binary instead of a weird libexec pipeline.
- The license changed from GPL to AGPL.
- The --mic and --list-mics options now match arecord.
- It's now one action per line and the colon is mandatory.
- Bad and redefined phrase definitions now (just) print a warning.
- State env vars have been replaced by $NUMEN_STATE_DIR files.
- The eval action now blocks, fixing race conditions.
- The repeat action now covers more actions.
- The localeval and localpen actions have been merged into eval and pen.
- The scrollup and scrolldown actions have been replaced by wheel.
- The @rapidon and @rapidoff tags have been merged into stick.
- The --kernel option has been renamed --uinput.
- The capson/capsoff actions have become caps on/caps off.
- The stick/unstick actions have become stick on/stick off.

### Fixed

- Some recognizer tweaks should make the recognition more robust.

### Removed

- The --speechless option.

## [0.6](https://git.sr.ht/~geb/numen/refs/0.6)

### Added

- Support for multi-word phrases.
- --gadget mode for simulating input over USB.
- A numenc command for running actions programmatically.
- A --phraselog=FILE option.
- An --audio=FILE option.
- A --speechless option.
- $NUMEN_KEY_HOLD and $NUMEN_TYPE_HOLD.

### Changed

- Now requires dotool>=1.1.
- dmenu, xdotool and xset are now optional.
- Now exits immediately if another instance is already reading the action pipe.
- The displaying command is now installed to libexec.

### Fixed

- The tweaked key-down-up time should stop missed keys with some applications.
- Fixed the kernel handler ignoring $NUMEN_KEY_DELAY and $NUMEN_TYPE_DELAY.
- Made $NUMEN_TYPE_DELAY with the X11 handler consistent with the others.
- Fixed the @kernel and @x11 tags.

## [0.5](https://git.sr.ht/~geb/numen/refs/0.5)

### Changed

- Reimplemented @transcribe and @cancel to slice the audio once the
  results have been finalized, rather than hotplugging the audio between
  commanding/transcribing and relying on unfinalized results.
- Now doesn't exit if the microphone is unplugged and continues when it is
  plugged back in.

### Fixed

- Fixed paths in ./install-numen.sh that ignored the DESTDIR argument.

### Removed

- Removed the @instant tag now it's no longer needed with @transcribe and
  @cancel.

## [0.4](https://git.sr.ht/~geb/numen/refs/0.4)

### Added

- A --version flag.

### Changed

- Now exits less confusingly if no model is installed.

## [0.3](https://git.sr.ht/~geb/numen/refs/0.3)

### Added

- This changelog har har har.

### Changed

- The @transcribe tag now sets an environment variable to your sentence
  instead of typing it. This lets you apply a filter to the result.
- Simplified the runit service.

### Fixed

- You no longer need to leave a slight pause before transcribing a sentence.
- Sticky mode now releases keys properly when using --kernel.
- Replaced a redundant udev in ./install-dotool.sh with ./install-user-udev-rule.sh.
