#!/bin/sh
rm -f files_in_sys
CWD=$(pwd)
( cd /sys/accessibility/speakup
for file in $(find -type f|sort); do
	echo "$file:" >> $CWD/files_in_sys
	cat $file >> $CWD/files_in_sys
	echo >> $CWD/files_in_sys
done
)
geany files_in_sys &