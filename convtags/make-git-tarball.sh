#!/bin/sh
# Do not use: that makes an uselessly bloated tarball for a few commits
# after the release.
gitname=convtags
pkgname=convtags
pkgver=0.1+git9C86091
CWD=$(pwd)
( cd /data/GitHub/$gitname
git pull
cat <<EOF > .gitattributes
/data
/m4
./.gitattributes
EOF
cat .gitattributes
git archive --worktree-attributes --prefix=$pkgname-$pkgver/ master | xz > $CWD/$pkgname-$pkgver.tar.xz
rm .gitattributes
)
