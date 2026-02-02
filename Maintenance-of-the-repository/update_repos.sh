#!/bin/sh
# This script is context-dependent.
#MIRROR=rsync://slackware.uk
#MIRROR=rsync://ftp.slackware.com
#TARGET=/storage/salix
VERSION=14.2
NEWVERSION=15.0
CURRENT=current

#SOURCE=https://slackware.uk/people/alien/sbrepos/15.0/x86_64/:DEFAULT
#rsync -rlpt --delete -P -H $MIRROR/salix/sbo/$VERSION $TARGET/sbo
#for Arch in i486 x86_64; do
TARGET=/data/repos
MIRROR=rsync://slackware.uk
rsync -4 -rlpt --delete -P -H $MIRROR/slackware/slackware64-$CURRENT $TARGET
rsync -rlpt --delete -P -H $MIRROR/people/alien/sbrepos/15.0/x86_64 $TARGET/alien
#rsync -rlpt --delete -P -H $MIRROR/people/alien/slackbuilds/libreoffice/build/ $TARGET/alien_libreoffice
rsync -rlpt --delete -P -H $MIRROR/people/alien/slackbuilds/openjdk17/build/ $TARGET/alien_openjdk17
rsync -rlpt --delete -P -H $MIRROR/salix/x86_64/15.0/ $TARGET/salix-15.0
rsync -rlpt --delete -P -H $MIRROR/salix/x86_64/xfce4.18-15.0/ $TARGET/xfce4.18-15.0
rsync -rlpt --delete -P -H $MIRROR/gfs/15.0/41.10/x86_64/ $TARGET/gfs64-15.0
rsync -rlpt --delete -P -H --exclude source $MIRROR/salix/x86_64/extra-15.0/ $TARGET/extra-15.0
rsync -rlpt --delete -P -H $MIRROR/salix/x86_64/slackware-15.0 $TARGET
#MIRROR=rsync://ftp.slackware.com
echo "Now, SBo."
(
cd /data/repos/slackbuilds || exit 1
git pull
)
exit
(
echo "Now, Ponce's  SlackBuilds"
cd /data/repos/Ponce/slackbuilds || exit 1
git pull
)
