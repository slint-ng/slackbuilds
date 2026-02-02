#!/bin/sh
CWD=$(pwd)
REPO=$(cd .. && cd .. && cd .. && pwd)
UP=$(cd .. && cd .. && pwd)
if [ "$UP" = "$REPO" ]; then
	echo "should not be run from $CWD"
	exit
fi
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
pkgname=$(find . -name "*txz"|sed "s/-[^-]*-[^-]*-[^-]*$//;s/..//")
pkgfullname=$(find . -name "*txz"|sed "s/..//;s/.txz//")
pkgdepname="${pkgfullname}.dep"
#clear
nbpkg=$(find . -name "*txz"|wc -l)
case $nbpkg  in
	0) echo "Aucun paquet prêt."; exit;;
	1) :;;
	*) echo "Plusieurs paquets dans ce répertoire ! Corriger."; exit
esac
if [ ! -f "$pkgdepname" ]; then
	echo "computing deps..."
	depfinder -p -3 "${pkgfullname}".txz > "$pkgdepname"
	if [ -f moredeps ]; then
		tr -d '\n' < "$pkgdepname" > bof
		mv bof "$pkgdepname"
		while read -r addeddep; do
			sed "s/,$addeddep//" "$pkgdepname" >bif
			mv bif "$pkgdepname"
			printf '%s' ",$addeddep" >> "$pkgdepname"
		done < moredeps
	fi
fi
echo "== paquet prêt: ${pkgfullname}.txz =="
pkgver=$(find . -name "*txz"|rev|cut -d"-" -f3|rev)
txz=$(find  "$REPO"/slint -name "${pkgname}-*txz"|grep "${pkgname}-[^-]*-[^-]*-[^-]*$")
md5=$(find  "$REPO"/slint -name "${pkgname}-*md5"|grep "${pkgname}-[^-]*-[^-]*-[^-]*$")
txt=$(find  "$REPO"/slint -name "${pkgname}-*txt"|grep "${pkgname}-[^-]*-[^-]*-[^-]*$")
meta=$(find  "$REPO"/slint -name "${pkgname}-*meta"|grep "${pkgname}-[^-]*-[^-]*-[^-]*$")
dep=$(find  "$REPO"/slint -name "${pkgname}-*dep"|grep "${pkgname}-[^-]*-[^-]*-[^-]*$")
con=$(find  "$REPO"/slint -name "${pkgname}-*con"|grep "${pkgname}-[^-]*-[^-]*-[^-]*$")
# echo txz=$txz
# echo md5=$md5
# echo txt=$txt
# echo meta=$meta
# echo dep=$dep
# echo con=$con
if [ "$txz" = "" ]; then
	echo "pas de paquet précédent"
else
	printf '%s' "archive the previous $txz? [Y/n] "
	read -r dummy
	if [ ! "$dummy" = "n" ] && [ ! "$dummy" = "N" ]; then
		mv "$txz" "$REPO"/previous/packages
	else
		rm "$txz"
	fi
fi
if [ "$md5" = "" ]; then
	echo "pas de md5 trouvé"
else
	printf '%s' "archiver $md5? [Y/n] "
	read -r dummy
	if [ ! "$dummy" = "n" ] && [ ! "$dummy" = "N" ]; then
		mv "$md5" "$REPO"/previous/packages
	else
		rm "$md5"
	fi
fi
for i in $txt $meta $dep $md5; do
	if [ ! "$i" = "" ]; then
		list="yes"
		echo "$i"
	fi
done
if [ "$list" = "yes" ]; then
	echo
	printf "supprimer les fichiers ci-dessus [Y/n] "
	read -r dummy
	if [ ! "$dummy" = "n" ] && [ ! "$dummy" = "N" ]; then
		rm -f "$txt" "$meta" "$dep" "$md5"
	else
		echo "Not removed."
	fi
fi

if [ ! "$pkgname" = "" ]; then
	rm -f "build-${pkgfullname}.log"
	rm -f "build-${pkgname}.sh"
	packagefullname="$(find . -name "*txz")"
	printf '%s' "Include $packagefullname in Slint/Extra/Testing/ISO/None [s/e/t/i/n] "
	read -r dummy
	if [ "$dummy" = "e" ] || [ "$dummy" = "E" ]; then
		mv "$packagefullname" "$REPO/slint/extra" || exit 1
	elif [ "$dummy" = "s" ] || [ "$dummy" = "S" ]; then
		mv "$packagefullname" "$REPO/slint" || exit 1
	elif [ "$dummy" = "t" ] || [ "$dummy" = "T" ]; then
		mv "$packagefullname" "$REPO/slint/testing" || exit 1
	elif [ "$dummy" = "i" ] || [ "$dummy" = "I" ]; then
		mv "$packagefullname" "$REPO/slint/ISO" || exit 1
	else
		echo "non inclus."
	fi
	packagedep="$(find . -name "${pkgname}*dep")"
	printf '%s' "Include $packagedep in Slint/Extra/Testing/None [s/e/t/i/n] "
	read -r dummy
	if [ "$dummy" = "e" ] || [ "$dummy" = "E" ]; then
		mv "$packagedep" "$REPO/slint/extra" || exit 1
	elif [ "$dummy" = "s" ] || [ "$dummy" = "S" ]; then
		mv "$packagedep" "$REPO/slint" || exit 1
	elif [ "$dummy" = "t" ] || [ "$dummy" = "T" ]; then
		mv "$packagedep" "$REPO/slint/testing" || exit 1
	elif [ "$dummy" = "i" ] || [ "$dummy" = "I" ]; then
		mv "$packagedep" "$REPO/slint/ISO" || exit 1
	else
		echo "not included."
	fi
fi
echo "== Contain of the directory =="
ls --color -1
echo
if [ -f "LOG" ]; then
	echo "Presser Entrée pour lire le journal"
	read -r dummy
	most LOG
	printf "supprimer le fichier LOG [Y/n]"
	read -r dummy
	if [ ! "$dummy" = "n" ] && [ ! "$dummy" = "Y" ]; then
		rm LOG
	fi
fi
if [ "$pkgver" = "" ]; then
	pkgver="nopackageheresonoversioneither"
fi
if [ "$pkgname" = "" ]; then
	pkgname="nopackagehere"
fi
echo "==="
find .  -maxdepth 1 | grep -v \
-e "^.$" \
-e SLKBUILD \
-e ${pkgname}.SlackBuild \
-e ${pkgname}.info \
-e slack-desc \
-e README \
-e ${pkgver}*z \
-e ${pkgver}*z2 \
-e doinst.sh
echo "==="
for i in $(find . -maxdepth 1 | grep -v \
-e "^.$" \
-e SLKBUILD \
-e ${pkgname}.SlackBuild \
-e ${pkgname}.info \
-e slack-desc \
-e README \
-e ${pkgver}*z \
-e v${pkgver}*z \
-e ${pkgname}-${pkgver}*z \
-e ${pkgver}*z2 \
-e doinst.sh); do
	if [ -f "$i" ] && echo "$i"|grep  -q -v -e /; then
		printf '%s' "supprimer le fichier $i [y/N]"
		read -r dummy
		if [ "$dummy" = "y" ] || [ "$dummy" = "Y" ]; then
			rm "$i"
		fi
	fi
	if [ -d "$i" ]; then
		printf '%s' "remove the directory ${COLORED}$i${NORMAL} [Y/n]"
		read -r dummy
		if [ ! "$dummy" = "n" ] && [ ! "$dummy" = "Y" ]; then
			rm -r "$i"
		fi
	fi
done
echo
echo "== Content of the directory after cleaning =="
ls --color -1
