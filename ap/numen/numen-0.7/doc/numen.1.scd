numen(1)

# NAME

*numen* - voice control for handsfree computing

# SYNOPSIS

*numen* [*--gadget*|*--uinput*|*--x11*] [*--mic=*_NAME_] [_FILE_...]++
*numen* *--help*

# DESCRIPTION

*numen* reads phrases and actions from one or more files, and performs the
actions when you say their phrases.

With no arguments, *numen* uses the default phrases in the
*/etc/numen/phrases/* directory, unless you've put files ending with *.phrases*
in the *$XDG_CONFIG_HOME/numen/phrases/* directory. (*$XDG_CONFIG_HOME*
is *~/.config* unless set otherwise.)

There is also the *numenc* command to trigger actions programmatically.

# DOTOOL AND KEYBOARD LAYOUTS

The default handler uses the *dotool* command to simulate input anywhere
(X11, Wayland, TTYs) but it usually requires your user to be in group *input*
(see *dotool --help*).

If you use a non-us-qwerty keyboard layout, you can set the environment
variables *DOTOOL_XKB_LAYOUT* and *DOTOOL_XKB_VARIANT* to have *dotool*
simulate the right keys. For example, if you use the French *fr* layout:

	*DOTOOL_XKB_LAYOUT=fr numen*

# OPTIONS

*--audio=*_FILE_
	Specify an audio file to use instead of the microphone. This isn't
	for normal use, and the correct audio format depends on the speech
	recognition model.

*--audiolog=*_FILE_
	Write the audio to _FILE_ while it's recorded.

*-h*, *--help*
	Print help and exit.

*--gadget*
	Simulate the input over USB using the *gadget* command
	(https://git.sr.ht/~geb/gadget).

*--uinput*
	Simulate the input system-wide using the *dotool* command (see the
	section above). This is the default.

*--list-mics*
	List audio devices and exit. The same as *arecord -L*.

*--mic=*_AUDIO_DEVICE_
	Specify the audio device. Like *arecord -D*.

*--phraselog=*_FILE_
	Write phrases to _FILE_ while they're performed.

*--verbose*
	Show what is being used.

*--version*
	Print the version and exit.

*--x11*
	Simulate the input for X11 using the *xdotool* and *xset* commands.

# CONFIGURATION

Phrase files consist of lines mapping phrases to actions. The format is:

\[*@*_TAG_...] _PHRASE_:_ACTION_

That is, there can be zero or more "tags" starting with *@*, then the phrase,
then a *:* and the action. If a line ends with a backslash, the next line is
taken as another action. Empty lines and lines starting with *#* are ignored.

Phrases with words unknown to the speech recognition model are ignored with
a warning.

## ACTIONS

*press* [_CHORD_...]
	Simulate each _CHORD_. For example, to cycle round splits in Vim:

	*switch: press ctrl+w w*

	The key names are the XKB key names which you can find with *dotool
	\--list-x-keys*.  The modifiers are *super*, *ctrl*, *alt* and *shift*.

*type* _TEXT_
	Simulate typing _TEXT_.

*mod* *super*/*ctrl*/*alt*/*shift*
	Enable a modifier for the next press.

*mod* *clear*
	Clear all modifiers.

*caps* *on*/*off*
	Enable/disable Caps Lock.

*mouseto* _X_ _Y_
	Teleport the cursor to _X_ _Y_, where _X_ and _Y_ are percentages
	between 0.0 and 1.0.

*mousemove* _X_ _Y_
	Move the cursor relative to its current position.

*click* *left*/*middle*/*right*
	Simulate a mouse click.

*wheel* _AMOUNT_
	Simulate a (vertical) mouse wheel. A positive _AMOUNT_ is up,
	negative is down.

*hwheel* _AMOUNT_
	Simulate a horizontal mouse wheel. A positive _AMOUNT_ is right,
	negative is left.

*stick* *on*
	Make presses not keyup, like holding down a key at a time.  If already
	sticking, keyup but keep sticking.

*stick* *off*
	Keyup and stop sticking.

*repeat* _TIMES_
	Repeat the previous *click*, *mousemove*, *mouseto*, *pen*, *press*,
	*run*, *type*, *wheel* or *hwheel* however many _TIMES_.

*run* _COMMAND_
	Run a shell command. For example:

	*hi: run notify-send "Greetings, I'm a notification!"*

*pen* _COMMAND_
	Type the output of a shell command. For example, to type the date:

	*date: pen date +%D*

*eval* _COMMAND_
	Perform the output of a shell command as actions. For example,
	to backspace a transcription:

	*ditch: eval "$NUMEN_STATE_DIR/transcripts" | sed 's/./ BackSpace/g; s/^/press/; q'*

*set* _ENV_VAR_ _COMMAND_
	Set an environment variable to the output of a shell command.

*load* [_FILE_...]
	Switch to different phrase files, or pause *numen* by loading no
	files. For example, you can pause and resume *numen* programmatically
	using the *numenc* command:

	*$ echo load | numenc*++
*...*++
*$ echo load /etc/numen/phrases/\*.phrases | numenc*

*handler* *gadget*/*uinput*/*x11*
	Change between the *--gadget*, *--uinput* and *--x11* modes.

*keydelay* _MILLISECONDS_/*reset*
	Set the time between *press* keys.

*keyhold* _MILLISECONDS_/*reset*
	Set the time *press* keys are held.

*typedelay* _MILLISECONDS_/*reset*
	Set the time between *type*/*pen* keys.

*typehold* _MILLISECONDS_/*reset*
	Set the time *type*/*pen* keys are held.

## TAGS

Tags have phrases act specially.

*@cancel*
	Cancel the preceding phrases.

*@transcribe*
	Do literal speech recognition until the next silence, record the
	results in *$NUMEN_STATE_DIR/transcripts*, and only then perform
	the action. For example, to type the top result:

	*@transcribe scribe: pen head -n 1 $NUMEN_STATE_DIR/transcripts*

*@gadget* *@uinput* *@x11*
	If a phrase is tagged with any of these, ignore it unless *numen*
	was started in one of their modes.

# SPECIAL PHRASES

The special phrase *<complete>* is performed after each sentence is performed.
For example, to turn off Caps Lock at the end of each sentence:

	*<complete>: caps off*

In addition to speech, *numen* can recognize a few particular noises nearly
instantaneously. They are too trigger-happy for most uses, but good for
playing games with a handful of carefully chosen words. Each noise has a
special phrase for the beginning and end of its detection. They are:

- *<blow-begin>* and *<blow-end>* - Blowing into the microphone.
- *<hiss-begin>* and *<hiss-end>* - SSSS!
- *<shush-begin>* and *<shush-end>* - SHHH!

The environment variable *NUMEN_NOISE_THRESHOLD* adjusts the required energy
for the noises (especially blowing).

# ENVIRONMENT VARIABLES

*numen* can be tweaked by some environment variables:

- *NUMEN_NOISE_THRESHOLD* as noted above.
- *NUMEN_KEY_DELAY*, *NUMEN_KEY_HOLD*, *NUMEN_TYPE_DELAY* and *NUMEN_TYPE_HOLD*
  are like their corresponding actions but at startup.
- *NUMEN_SHELL* sets the shell used for shell commands, instead of */bin/sh*.

# STATE FILES

*numen* exposes some of its state in files in the *$NUMEN_STATE_DIR* directory.
*numen* will set *$NUMEN_STATE_DIR* to the default (*$XDG_STATE_HOME/numen*)
if not set otherwise, for convenience in actions.  (*$XDG_STATE_HOME* is
*~/.local/state* unless set otherwise.)

- *$NUMEN_STATE_DIR/handler* contains *gadget*, *uinput* or *x11* depending
  on the mode.
- *$NUMEN_STATE_DIR/mods* contains the state of the modifier keys.
- *$NUMEN_STATE_DIR/phrase* contains the previous phrase.
- *$NUMEN_STATE_DIR/transcripts* contains the results of the *@transcribe* tag.

# DIFFERENT MODELS AND LANGUAGES

Properly supporting/testing different speech recognition models and spoken
languages is on the todo list, but *numen* should work with any of the *small*
models from *https://alphacephei.com/vosk/models*. Use the environment
variable *NUMEN_MODEL* to specify the path to the model directory.

# EXAMPLES

Run *numen* with the default phrases:

	*$ numen /etc/numen/phrases/\*.phrases*

There shouldn't be any output but you should be able to type *hey* by saying
"hoof each yank". You can also try transcribing a sentence after saying
"scribe", and terminate it by pressing Ctrl+c (a.k.a "troy cap").

Check the microphone:

	*$ timeout 5 numen --verbose --audiolog=me.wav++
$ aplay me.wav*

Run *numen* printing the phrases while they're performed:

	*$ numen --phraselog=/dev/stdout*

# AUTHOR

John Gebbie
