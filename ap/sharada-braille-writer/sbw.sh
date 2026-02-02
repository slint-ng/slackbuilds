#!/bin/sh
if [ ! -f ~/.sbw/user-preferences.cfg ]; then
	mkdir -p ~/.sbw
	cp /usr/doc/sharada-braille-writer*/user-preferences.cfg ~/.sbw
fi
/usr/libexec/sharada-braille-writer
