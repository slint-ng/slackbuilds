#!/bin/sh
# This installs a Vosk speech recognition model.
f=vosk-model-small-en-us-0.15
name=small-en-us
checksum=30f26242c4eb449f948e42cb302dd7a686cb29a3423a8367f99ff41780942498

ok=1
! command -v unzip >/dev/null && echo 'you need unzip' && unset ok
! command -v wget >/dev/null && echo 'you need wget' && unset ok
[ "$ok" ] || exit

# not necessary but lets you run ./numen in this directory
ln -sf "/usr/local/share/vosk-models/$model_name" model

rm -rf tmp && mkdir -p tmp && cd tmp || exit

wget "https://alphacephei.com/kaldi/models/$f.zip" || exit
if [ "$(sha256sum "$f.zip" | cut -d' ' -f1)" != "$checksum" ]; then
	printf %s\\n "$f.zip did not match the checksum"
	exit 1
fi

unzip -q "$f.zip" || exit
mkdir -p /usr/local/share/vosk-models || exit
rm -rf "/usr/local/share/vosk-models/$name" || exit
mv "$f" "/usr/local/share/vosk-models/$name" || exit

echo 'Installed successfully.'
