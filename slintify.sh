#/bin/sh
source="/repo/x86_64/slint-15.0/source"
pkgname=$1
pkgdir=$(find /data/repos/slackbuilds -type d -name "$pkgname")
echo $pkgdir
CWD=$(pwd)
if [ ! "$CWD" = "$source" ]; then
	echo "You are not in $source"
	exit
fi
if [ "$pkgdir" = "" ]; then
	echo "$pkgname not found among the slackbuilds."
	exit
else
	echo "Press Enter to see the ${pkgname}.info among the slackbuilds."
	read
	most $pkgdir/*.info
fi
if [ -d "$pkgname" ]; then
	echo "$pkgname found in source"
	if [ ! -f $pkgname/*.info ]; then
		echo "press Enter to see the .info"
		read
		most $pkgname/*.info
	else
		echo "no .info found"
	fi
else
	echo "$pkgname not found in source"
fi
echo "To use $pkgdir press Enter, else press Ctrl+C"
read
rm -rf $source$pkgname
cp -a $pkgdir $source/
cd $source/$pkgname || exit 1
cat *info
echo "Press Enter to start"
read
sed -i '
/Included in Slint/d
/PRGNAM=/s,.*,# Included in Slint by Didier Spaier didieratslintdotfr\n\n&,
s,TAG=.*,TAG=slint,
s,TMP=.*,TMP=$CWD,
s,OUTPUT=.*,OUTPUT=$CWD,
s,:-tgz,:-txz,' *.SlackBuild
. ./*.info
NBDL=$(echo $DOWNLOAD|sed "s/[[:space:]]\{1,\}/\n/g"|wc -l)
NBNB5=$(echo $MD5SUM|sed "s/[[:space:]]\{1,\}/\n/g"|wc -l)
if [ ! $NBDL -eq $NBNB5 ]; then
echo "not the same number of source files and mdSum files."
	exit
fi
PKGNUM=0
echo $DOWNLOAD|sed "s/[[:space:]]\{1,\}/\n/g"
echo $DOWNLOAD|sed "s/[[:space:]]\{1,\}/\n/g"|while read URL; do
	PKGNUM=$((PKGNUM + 1))
	FILENAME="$(basename $URL)"
	echo "$FILENAME" > filename$PKGNUM
	if [ ! -f $FILENAME ]; then
		wget "$URL"
	fi
done
PKGNUM=0
OK="y"
echo $MD5SUM|sed "s/[[:space:]]\{1,\}/\n/g"|while read MD5; do
	PKGNUM=$((PKGNUM + 1))
	MD5SUM2=$(md5sum $(cat filename$PKGNUM)|sed "s/[[:space:]].*//")
	if [ "$MD5" = "$MD5SUM2" ]; then
		echo "md5sum OK for $(cat filename$PKGNUM)"
	unset OK
	else
		echo "Wrong md5sum for $FILENAME$PKGNUM."
	fi
done
rm filename*
if [ $OK ]; then
	echo "Press Enter to continue"
	read
	fakeroot sh *ld 2>&1|tee LOG
fi
echo "Press Enter to install, Ctrl+C to abort"
read
su -c "upgradepkg --reinstall --install-new *txz"
echo "Press Enter to run mtp.sh, Ctrl+C to abort"
read
../mtp.sh
