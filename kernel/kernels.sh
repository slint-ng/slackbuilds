#!/bin/sh
# I assume that new kernels are in $SLINTREPO/source/k and the previous source
# directory is $SLINTREPO/source/kernels that we will replace by
# $SLINTREPO/source/k after having proceeded to the update.
COLORED=$(tput setaf 196)
BLACK=$(tput setaf 0)
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
LIME_YELLOW=$(tput setaf 190)
POWDER_BLUE=$(tput setaf 153)
BLUE=$(tput setaf 4)
MAGENTA=$(tput setaf 5)
CYAN=$(tput setaf 6)
WHITE=$(tput setaf 7)
BRIGHT=$(tput bold)
NORMAL=$(tput sgr0)
BLINK=$(tput blink)
REVERSE=$(tput smso)
UNDERLINE=$(tput smul)
SLINTREPO=/storage/repo/x86_64/slint-14.2.1
clear
echo "== Old kernels files to drop: =="
find $SLINTREPO/previous/packages/kernel-*txz|grep -v firmware
echo "== Packages  to move to SLINTREPO/previous: =="
find $SLINTREPO/slint/kernel-*txz|grep -v firmware
echo "== Packages to include in $SLINTREPO/slint: =="
find $SLINTREPO/source/k/kernel-*txz
printf "Do  it? [N/y]"
read dummy
echo
if [ ! "$dummy" = "y" ] && [ ! "$dummy" = "Y" ]; then
	exit
fi
for i in $(find $SLINTREPO/previous/packages/kernel-*|grep -v firmware); do
	rm $i
done
for i in $(find $SLINTREPO/slint/kernel-*txz|grep -v firmware); do
	mv $i $SLINTREPO/previous/packages/
done
for i in $(find $SLINTREPO/slint/kernel-*md5|grep -v firmware); do
	mv $i $SLINTREPO/previous/packages/
done
for i in $(find $SLINTREPO/slint/kernel-*meta|grep -v firmware); do
	rm $i
done
for i in $(find $SLINTREPO/slint/kernel-*txt|grep -v firmware); do
	rm $i
done
for i in $(find $SLINTREPO/source/k/kernel-*txz); do
	mv $i $SLINTREPO/slint/
done
rm -rf $SLINTREPO/source/kernels
mv $SLINTREPO/source/k $SLINTREPO/source/kernels
echo "All done."