#!/bin/sh
VERSION=$1 BUILD=$2 TMP=$(pwd) TAG=slint OUTPUT=$(pwd) PKGTYPE=txz fakeroot sh *ld 2>&1 |tee LOG

