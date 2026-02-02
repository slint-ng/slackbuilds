#!/bin/sh
# Author: Didier Spaier, Paris, France
# Public domain
CWD=$(pwd)
usage() {
  printf %b "Usage: $0\n"
  exit
}
export MAINREPO=packages
BASEDIR=/repo

if [ $UID -eq 0 ]; then
  printf "%b"  "Please execute this script as regular user.\n"
  exit
fi



SLINTREPO=$BASEDIR/x86_64/slint-15.0
	( cd $SLINTREPO || exit 1
		$CWD/metagen.sh all
		$CWD/metagen.sh md5
	)
