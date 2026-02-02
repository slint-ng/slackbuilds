#!/bin/sh
[ $(id -u) -ne 0 ] && echo "Run me as root!" && exit
CWD=$(pwd)
PRGNAM=swapinzram
VERSION=2
TMP=$CWD
ARCH=noarch
PKG=$CWD/pkg
BUILD=1slint
rm -rf $PKG
mkdir -p $PKG/usr/doc/${PRGNAM}-${VERSION}
mkdir -p $PKG/install
mkdir -p $PKG/etc/rc.d
cp $CWD/rc.swapinzram $PKG/etc/rc.d
chmod 755  $PKG/etc/rc.d/rc.swapinzram
cp $CWD/swapinzram.conf $PKG/etc/swapinzram.conf.new
chmod 644 $PKG/etc/swapinzram.conf.new
chown root:root $PKG/etc/swapinzram.conf.new
chown root:root $PKG/etc/rc.d/rc.swapinzram
cp $CWD/README $PKG/usr/doc/${PRGNAM}-${VERSION}
chmod 644 $PKG/usr/doc/${PRGNAM}-${VERSION}/*
echo \
"${PRGNAM}: swapinzram (configure a swap block device in RAM using zram)
${PRGNAM}:
${PRGNAM}: Author: Didier Spaier." >$PKG/install/slack-desc
cp slack-desc $PKG/install/
cp doinst.sh $PKG/install
cd $PKG
/sbin/makepkg -l y -c n $TMP/$PRGNAM-$VERSION-$ARCH-$BUILD.txz

