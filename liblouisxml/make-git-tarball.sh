#!/bin/sh
gitname=liblouisxml
pkgname=liblouisxml
CWD=$(pwd)
( cd /data/GitHub/$gitname
git pull
cat <<EOF > .gitattributes
/data
/m4
./.gitattributes
EOF
gitrev=git$(git log -n 1 --format=format:%h .)
echo "pkgver=$gitrev"
git archive --worktree-attributes --prefix=${pkgname}-$gitrev/ master | xz > $CWD/${pkgname}-${gitrev}.tar.xz
)
