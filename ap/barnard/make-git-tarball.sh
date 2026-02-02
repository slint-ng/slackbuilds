#!/bin/sh
# Do not use: that makes an uselessly bloated tarball for a few commits
# after the release.
gitname=barnard
pkgname=barnard
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
