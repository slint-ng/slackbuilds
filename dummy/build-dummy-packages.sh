#!/bin/sh
while read i; do
	export SBONAME=$(echo "$i"|sed "s/.*;//")
	export SLINTNAME=$(echo "$i"|sed "s/;.*//")
	fakeroot slkbuild -X 1>/dev/null
	TXZ=$(ls ${SBONAME}*txz)
	DEP=${TXZ%txz}dep
	echo $SLINTNAME > $DEP
done <plus
#done <convert-naming-table
