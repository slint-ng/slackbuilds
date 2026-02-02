#!/bin/sh
# This installs the Vosk speech recognition library.
# See ./install-vosk-musl.sh for musl-based distros like Alpine Linux.
version=0.3.45

ok=1
! command -v unzip >/dev/null && echo 'you need unzip' && unset ok
! command -v wget >/dev/null && echo 'you need wget' && unset ok
[ "$ok" ] || exit

a="$(uname -m)"
case "$a" in
*86) a=x86;;
aarch64|armv7l|riscv64|x86_64) ;;
*) echo "There isn't a binary for your architecture: $a"; exit 1;;
esac

case "$a" in
aarch64) checksum=45e95d37755deb07568e79497d7feba8c03aee5a9e071df29961aa023fd94541;;
armv7l) checksum=10b795ae478ef1d530fcbfbbea9ccbbbf3b7e7c244bd5fd3176f4a6af32f3c8c;;
risc64) checksum=9e7f890e6a464526600fcf94e3a223ff5db960f21e4ee2b51ac49b71c28fa860;;
x86) checksum=b539efc22780948bd98e2ecb9c1b92ca08b3c552a18744f7202ab78405b8e1f9;;
x86_64) checksum=bbdc8ed85c43979f6443142889770ea95cbfbc56cffb5c5dcd73afa875c5fbb2;;
esac

rm -rf tmp && mkdir -p tmp && cd tmp || exit

f="vosk-linux-$a-$version"
wget "https://github.com/alphacep/vosk-api/releases/download/v$version/$f.zip" || exit
if [ "$(sha256sum "$f.zip" | cut -d' ' -f1)" != "$checksum" ]; then
	printf %s\\n "$f.zip did not match the checksum"
	exit 1
fi

unzip -q "$f" || exit
mkdir -p /lib && cp "$f/libvosk.so" /lib || exit
mkdir -p /usr/include && cp "$f/vosk_api.h" /usr/include || exit

echo 'Installed successfully.'
