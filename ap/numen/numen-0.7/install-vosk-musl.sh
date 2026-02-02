#!/bin/sh
# This installs the Vosk speech recognition library for musl-based distros
# like Alpine Linux.
version=0.3.45

ok=1
! command -v unzip >/dev/null && echo 'you need unzip' && unset ok
! command -v wget >/dev/null && echo 'you need wget' && unset ok
[ "$ok" ] || exit

a="$(uname -m)"
case "$a" in
aarch64|x86_64) ;;
*) echo "There isn't a binary for your architecture: $a"; exit 1;;
esac

case "$a" in
aarch64) checksum=78a5273c523f74a56d897a202aaa1b8a7dd948c62038bd243960c14f8cc991a5;;
x86_64) checksum=f48b9f8f99d8241c394414472e1893c8bf2df749ac6e322cfc729fd6f71f178a;;
esac

rm -rf tmp && mkdir -p tmp && cd tmp || exit

f="$a"
wget "https://github.com/JohnGebbie/build-vosk/releases/download/$version/$f.zip" || exit
if [ "$(sha256sum "$f.zip" | cut -d' ' -f1)" != "$checksum" ]; then
	printf %s\\n "$f.zip did not match the checksum"
	exit 1
fi

unzip -q "$f" || exit
mkdir -p /lib && cp "$f/libvosk.so" /lib || exit
mkdir -p /usr/include && cp "$f/vosk_api.h" /usr/include || exit

echo 'Installed successfully.'
