#!/bin/sh
k=$(find -name *txz)
depfinder -p -3 -f "$k"
j=$(find -name *dep)
tr -d '\n' < "$j" > bof
mv bof "$j"
for i in dee \
gnome-dictionary \
isodate \
pastebinit \
python-rdflib \
raptor \
setconf \
telepathy-glib \
zeitgeist; do
	sed "s/,$i//" "$j" > bif
	mv bif "$j"
	printf ",$i" >> "$j"
done
