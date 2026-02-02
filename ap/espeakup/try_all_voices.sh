#/bin/sh
(cd /usr/share/espeak-ng-data/lang
for voice in $(find  -type f|sed "s,.*/,,"|sort);do
	echo $voice
	espeak-ng -v$voice "Hello, how are you?"
	sleep 0.5
done
)
