#!/bin/sh
version=7b38f27d30581b2ba2a75c079502fdc118e4bf57
distfile="https://git.sr.ht/~geb/dotool/archive/$version.tar.gz"
checksum=6a9156bdf8bb6405615733e14cf22f6f5e91c4006799b5e9770d09e08633bda0

ok=1
! command -v go > /dev/null && echo 'you need go (sometimes packaged as golang)' && unset ok
! command -v tar > /dev/null && echo 'you need tar' && unset ok
! command -v wget > /dev/null && echo 'you need wget' && unset ok
! test -d /usr/include/xkbcommon && echo 'you need libxkbcommon-dev' && unset ok
[ "$ok" ] || exit

rm -rf tmp && mkdir -p tmp && cd tmp || exit

wget --no-verbose -O dotool.tar.gz "$distfile" || exit
if [ "$(sha256sum dotool.tar.gz | cut -d' ' -f1)" != "$checksum" ]; then
	echo 'dotool.tar.gz did not match checksum'
	exit 1
fi

tar xf dotool.tar.gz || exit
cd "dotool-$version" || exit
DOTOOL_VERSION="$version" ./install.sh || exit

echo 'Installed successfully.'
