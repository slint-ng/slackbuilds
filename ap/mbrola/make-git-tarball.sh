#!/bin/sh
gitname=MBROLA
pkgname=mbrola
pkgver=git6b15b8f
CWD=$(pwd)
( cd /data/GitHub/$gitname
git pull
git archive --prefix=$pkgname-$pkgver/ master | xz > $CWD/$pkgname-$pkgver.tar.xz
)
