#!/bin/sh
 A='Les amoureux fervents et les savants austères, aiment également, dans leur mûre saison, les chats, puissants et doux, 
orgueil de la maison.'
espeak-ng -vfr "$A"
while read person; do
	echo $person
	espeak-ng -vfr+"$person" "$A"
done < selected_variants

