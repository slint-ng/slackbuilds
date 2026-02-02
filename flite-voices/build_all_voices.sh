#!/bin/sh
echo "This script allows you to package all voices for the flite
synthesizer.
"
mkdir -p packages
rm -f LOG_build_all
(cd voices
pwd
ls
for i in $(ls *vox); do
	export i
	echo $i
	VOICE=$(echo $i|sed "s/cmu_us_//;s/cmu_indic_//;s/.flitevox//")
	export VOICE
	export VOICELANG=$(grep "${VOICE}:" ../flite_voices_list|sed "s/.*://;s/:.*//") 
	export GENDER=$(grep "${VOICE}:" ../flite_voices_list|sed "s/[^:]*:\([^:]*\).*/\1/")
	echo "Building a package for voice $VOICE now..."
	fakeroot slkbuild -X
	mv flite-voice-${VOICE}*txz ../packages
	rm flite-voice-${VOICE}*md5
	rm build-flite-voice-${VOICE}*log
done
)
echo "All done. The packages are stored here:"
echo "$(pwd)/packages"
