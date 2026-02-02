# Numen

Numen is voice control for handsfree computing, letting you type efficiently
by saying syllables and literal words. It works system-wide on Linux, and
the speech recognition runs locally.

There's a short demonstration on: [numenvoice.org](https://numenvoice.org)

## Install From Source

`go` (a.k.a `golang`) is required.

The [speech recognition library](https://alphacephei.com/vosk) and an English
model (about 40MB) can be installed with:

    sudo ./install-vosk.sh && sudo ./install-model.sh

The [dotool](https://sr.ht/~geb/dotool) command which simulates the input,
can be installed with:

    sudo ./install-dotool.sh

Finally, `numen` itself can be installed with:

    sudo ./install-numen.sh

## Permission and Keyboard Layouts

`dotool` requires permission to `/dev/uinput` to create the virtual input
devices, and a udev rule grants this to users in group input.

You could try:

    echo type hello | dotool

and if need be, you can run:

    sudo groupadd -f input
    sudo usermod -a -G input $USER

and re-login and trigger the udev rule or just reboot.

If it types something other than *hello*, see about keyboard layouts in the
[manpage](doc/numen.1.scd).

## Getting Started

Once you've got a microphone, you can run it with:

    numen

There shouldn't be any output, but you can try typing *hey* by saying "hoof
each yank", and try transcribing a sentence after saying "scribe". Terminate
it by pressing Ctrl+c (a.k.a "troy cap").

If nothing happened, check it's using the right audio device with:

    timeout 5 numen --verbose --audiolog=me.wav
    aplay me.wav

and specify a `--mic` from `--list-mics` if not.

Now you're ready to have a go in your text editor! The default phrases are
in the `/etc/numen/phrases` directory.

## Going Further

I just use Numen and the default phrases for all my computing,
with keyboard-based programs like [Neovim](https://neovim.io) and
[qutebrowser](https://qutebrowser.org). I also use a minimal desktop
environment I made, called [Tiles](https://git.sr.ht/~geb/tiles), that
doesn't require a pointer device for window management, file picking, etc.

The [manpage](doc/numen.1.scd) covers configuring Numen.

## Mailing List and Matrix Chat

You can send questions or patches by composing an email to
[~geb/public-inbox@lists.sr.ht](https://lists.sr.ht/~geb/public-inbox).

You're also welcome to join the Matrix chat at
[#numen:matrix.org](https://matrix.to/#/#numen:matrix.org).

## See Also

* [Tiles](https://git.sr.ht/~geb/tiles) - a minimal desktop environment
  suited to voice control.
* [Noggin](https://git.sr.ht/~geb/noggin) - face tracking I use for
  playing/developing games.

## Support My Work 👀

[Thank you!](https://liberapay.com/geb)

## License

AGPLv3 only, see [LICENSE](./LICENSE).

Copyright (c) 2022-2023 John Gebbie
