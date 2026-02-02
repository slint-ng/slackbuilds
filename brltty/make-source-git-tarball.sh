#!/bin/sh
gitname=brltty
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
git archive --worktree-attributes --prefix=${gitname}-$gitrev/ master | xz > $CWD/${gitname}-${gitrev}.tar.xz
rm .gitattributes
echo gitrev=$gitrev
)

