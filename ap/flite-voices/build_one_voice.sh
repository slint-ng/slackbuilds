#!/bin/sh

mkdir -p packages

list_MBROLA_voices() {
	most mbrola_voices
}

make_voice_package() {
	export VOICE
	# AUTHOR is the last field
	export AUTHOR=$(grep ^${VOICE}: mbrola_voices|sed "s/.*://")
	# DESC is the second field
	export DESC=$(grep ^${VOICE}: mbrola_voices|sed "s/[^:]*:\([^:]*\).*/\1/")
	# WHEIGHT is the third field
	WHEIGHT=$(grep "^${VOICE}:" mbrola_voices|sed "s/[^:]*:[^:]*:\([^:]*\).*/\1/")
	echo "We will build a package for voice ${VOICE}: $DESC (${WHEIGHT})."
	read -p "Do you confirm this choice[Y/n] " CONFIRM
	if [ "$CONFIRM" = "N" ] || [ "$CONFIRM" = "n" ]; then
		return
	fi
	echo "Building a package for voice $VOICE now..."
	sleep 1
	fakeroot slkbuild -X
	mv mbrola-voice-${VOICE}*txz packages
	rm mbrola-voice-${VOICE}*md5
	rm build-mbrola-voice-${VOICE}*log
	read -p "Press Enter to continue. " DUMMY
}

list_installed_voices() {
	for i in \
	$(ls -1 /var/log/packages/|grep mbrola-voice|sed "s/mbrola-voice-//;s/-.*//"); do
		grep ^$i mbrola_voices
	done| most
}

while [ 0 ]; do
	clear
	echo "This script allows to build packages for MBROLA voices."
	echo "Type:"
	echo "  A to list all MBROLA voices"
	echo "  I to list installed voices"
	echo "  P to build a package for a MBROLA voice"
	echo "  Q to quit"
	read -p "Your choice: " CHOICE
	case $CHOICE in
		a|A)
			list_MBROLA_voices
			;;
		i|I)
			list_installed_voices
			;;
		p|P)
			clear
			read -p "Type the voice name (3 characters, like for instance en1: " VOICE
			if [ -f /var/log/packages/mbrola-voices-${VOICE}* ]; then
				read -p "This voice is already installed. Do you still want to package it[y/N]: " CONFIRM
				if [ ! "$CONFIRM" = "Y" ] &&  [ ! "$CONFIRM" = "Y" ]; then
					continue
				fi
			fi
			if [ "$(grep ^${VOICE}: mbrola_voices)" = "" ]; then
				read -p "The voice $VOICE does not exist. Press Enter to continue. " DUMMY
				continue
			fi
			make_voice_package
		;;
		q|Q)
			clear
			echo "Bye."
			exit
			;;
		*)
			printf "Wrong typing, press Enter to continue "
			read dummy
	esac
done

