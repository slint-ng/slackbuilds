#!/bin/sh
gitname=pytg
pkgname=pytg
CWD=$(pwd)
( cd /data/GitHub/$gitname
git pull
cat <<EOF > .gitattributes
/data
/m4
./.gitattributes
EOF
cat .gitattributes
gitrev=git$(git log -n 1 --format=format:%h .)
git archive --worktree-attributes --prefix=${pkgname}-$gitrev/ master | xz > $CWD/${pkgname}-${gitrev}.tar.xz
rm .gitattributes
)
