#!/bin/sh
# install-numen.sh [DESTDIR] [BINDIR]
: "${NUMEN_VERSION=$(git describe --long --abbrev=12 --tags --dirty 2>/dev/null || echo 0.7)}"
: "${NUMEN_DEFAULT_MODEL_PACKAGE=vosk-model-small-en-us}"
: "${NUMEN_DEFAULT_MODEL_PATHS=/usr/local/share/vosk-models/small-en-us /usr/share/vosk-models/small-en-us}"
: "${NUMEN_DEFAULT_PHRASES_DIR=/etc/numen/phrases}"
: "${NUMEN_MANPAGE_DIR=/usr/share/man/man1}"
: "${NUMEN_SCRIPTS_DIR=/etc/numen/scripts}"

if ! [ "$NUMEN_SKIP_CHECKS" ]; then
	ok=1
	! command -v arecord >/dev/null && echo 'you need the alsa-utils package' && unset ok
	! command -v dotool >/dev/null && echo 'you need dotool' && unset ok
	! command -v gcc >/dev/null && echo 'you need gcc' && unset ok
	! command -v go >/dev/null && echo 'you need go (sometimes packaged as golang)' && unset ok
	! command -v scdoc >/dev/null && echo 'you need scdoc' && unset ok
	[ "$ok" ] || exit

	if ! dotool --version >/dev/null 2>&1; then
		echo 'You need a newer version of dotool (version 1.1 or later),'
		echo 'use your package manager or run: sudo ./install-dotool.sh'
		exit 1
	fi
fi

if ! [ "$NUMEN_SKIP_BINARY" ]; then
	go build -ldflags "-X 'main.Version=$NUMEN_VERSION'
		-X 'main.DefaultModelPackage=$NUMEN_DEFAULT_MODEL_PACKAGE'
		-X 'main.DefaultModelPaths=$NUMEN_DEFAULT_MODEL_PATHS'
		-X 'main.DefaultPhrasesDir=$NUMEN_DEFAULT_PHRASES_DIR'" || exit
	echo 'Built successfully.'
fi

if [ "$NUMEN_SKIP_INSTALL" ]; then
	exit
fi

mkdir -p "$1/${2:-usr/local/bin}" || exit
if ! [ "$NUMEN_SKIP_BINARY" ]; then
	cp numen "$1/${2:-usr/local/bin}" || exit
fi
cp numenc "$1/${2:-usr/local/bin}" || exit

# Install the scripts used in the default phrases
rm -rf "$1/$NUMEN_SCRIPTS_DIR" && mkdir -p "$1/$NUMEN_SCRIPTS_DIR" || exit
cp scripts/* "$1/$NUMEN_SCRIPTS_DIR" || exit
sed -i "s:/etc/numen/scripts:$NUMEN_SCRIPTS_DIR:g" "$1/$NUMEN_SCRIPTS_DIR"/* || exit

# Install the default phrases
rm -rf "$1/$NUMEN_DEFAULT_PHRASES_DIR" && mkdir -p "$1/$NUMEN_DEFAULT_PHRASES_DIR" || exit
cp -r phrases/* "$1/$NUMEN_DEFAULT_PHRASES_DIR" || exit
sed -i "s:/etc/numen/scripts:$NUMEN_SCRIPTS_DIR:g" "$1/$NUMEN_DEFAULT_PHRASES_DIR"/* || exit

# Install the manpage
mkdir -p "$1/$NUMEN_MANPAGE_DIR" && scdoc < doc/numen.1.scd > "$1/$NUMEN_MANPAGE_DIR/numen.1" || exit

echo 'Installed successfully.'
