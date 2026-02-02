#!/bin/sh
# Do not use: that makes an uselessly bloated tarball for a few commits
# after the release.
gitname=speechd
pkgname=speech-dispatcher
#gitrev=26bc2f2b
#gitrev=cbbd42d
#gitrev=5992f14
#gitrev=4c1db31
#gitrev=7eaca7c
#gitrev=667e0c4
#gitrev=3420c668
#gitrev=f1a8725f
#gitrev=a5b91bd0
#gitrev=246839de
#gitrev=80bf1902
CWD=$(pwd)
( cd /data/GitHub/$gitname
git pull
cat <<EOF > .gitattributes
/data
/m4
./.gitattributes
EOF
#cat .gitattributes
gitrev=git$(git log -n 1 --format=format:%h .)
echo "pkgver=$gitrev"
git archive --worktree-attributes --prefix=${pkgname}-$gitrev/ master | xz > $CWD/${pkgname}-${gitrev}.tar.xz
#rm .gitattributes
)
