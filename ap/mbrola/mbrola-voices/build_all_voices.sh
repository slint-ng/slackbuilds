#!/bin/sh
echo "This script allows you to package all voices for the MBROLA
synthesizer.
"
mkdir -p packages
rm -f LOG_build_all
VOICES=$(sed "s/:.*//" mbrola_voices)
for VOICE in $VOICES; do
	export VOICE
	# AUTHOR is the last field
	export AUTHOR=$(grep ^${VOICE}: mbrola_voices|sed "s/.*://")
	# desc is the second field
	export DESC=$(grep ^${VOICE}: mbrola_voices|sed "s/[^:]*:\([^:]*\).*/\1/")
	echo "Building a package for voice $VOICE now..."
	sleep 1
	fakeroot slkbuild -X
	mv mbrola-voice-${VOICE}*txz packages
	rm mbrola-voice-${VOICE}*md5
	rm build-mbrola-voice-${VOICE}*log
done
echo "All done. The packages are stored here:"
echo "$(pwd)/packages"
