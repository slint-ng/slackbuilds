#!/bin/sh
for i in libmatchbox matchbox-common matchbox-config matchbox-desktop matchbox-panel matchbox-panel-manager matchbox-terminal matchbox-themes-extra matchbox-window-manager;
do
	(cd $i 
	fakeroot slkbuild -X 2>&1
	sh ../mtp.sh
	rm -f *log *md5
	)
done
