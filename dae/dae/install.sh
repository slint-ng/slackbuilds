#!/bin/bash
#Released under GNU General Public License version 3, see the file COPYING for details.
#installation script for Dae

#parse arguments for installation directories
showhelp() {
 echo $0 "can be called with the following options:"
 echo "$0 --help show options"
 echo $0" --prefix=<dir> installs into <dir>"
 echo $0" --destdir=<dir> destination "root" directory to copy files to"
 echo "e.g. when installing to a fakeroot environment"
 echo $0" --datadir=<dir> where data components will go"
 echo $0" --bindir=<dir> where executables will go"
 echo $0" --mandir=<dir> where man pages will go" 
 exit 1
}

for arg
do
  case $arg in
    --prefix=*)
        prefix=${arg#*=}
        ;;
    --help)
        showhelp
        ;;
    --bindir=*)
        bindir=${arg#*=}
        ;;
    --mandir=*)
        mandir=${arg#*=}
        ;;
    --datadir=*)
        datadir=${arg#*=}
        ;;
    --destdir=*)
        #destination "root" directory to copy files to
        #e.g. when installing to a fakeroot environment
        destdir=${arg#*=}
        ;;
  esac
done
if [ -z $prefix ]
then
  prefix=/usr/local
fi
if [ -z $bindir ]
then
  bindir=$prefix/bin
fi
if [ -z $datadir ] 
then
  datadir=$prefix/share
fi
if [ -z $mandir ]
then
  mandir=$datadir/man
fi

#check for the basics
ok=1
check_for() {
if (which "$1" 2> /dev/null > /dev/null)
then ok=0
else echo "I need the $1 utility and cannot find it, please install it first"
  exit 1
  fi
}  
check_for sed
check_for dd
check_for stty
check_for wc
check_for tty
check_for hexdump
check_for fgrep
check_for sort
check_for file
check_for test
check_for python
check_for ecasound

#change hardcoded file locations in other files
find . -type f -not -name "install.sh" -exec sed -i "s:/usr/local/bin:$bindir:g;" {} ";"
find . -type f -not -name "install.sh" -exec sed -i "s:/usr/local/man:$mandir:g;" {} ";"
find . -type f -not -name "install.sh" -exec sed -i "s:/usr/local/share:$datadir:g;" {} ";"

echo "installing the digital audio editor"

ok=1
if (test ! -d $destdir$bindir)
  then mkdir -p $destdir$bindir&&ok=0||echo creation of $destdir$bindir failed
  export PATH=$PATH:$destdir$bindir
  test $ok -eq 1&&exit 1
fi
cp dae $destdir$bindir||echo "failed to copy dae"
cp catchkey $destdir$bindir||echo "failed to copy catchkey"
cp kies_wifi_microphone $destdir$bindir||echo "failed to copy kies_wifi_microphone"
cp pickafile $destdir$bindir||echo "failed to copy pickafile"
cp getterm $destdir$bindir||echo "failed to copy getterm"
if (test ! -d $destdir/bin)
  then mkdir -p $destdir/bin&&ok=0||echo creation of $destdirbindir failed
  test $ok -eq 1&&exit 1
fi
echo "installing man pages"
ok=1
if (test ! -d $destdir$mandir/man1)
  then mkdir -p $destdir$mandir/man1&&ok=0||echo creation of $destdir$mandir/man1 failed
  test $ok -eq 1&&exit 1
fi
cp *.1 $destdir$mandir/man1||echo "man page installation failed"

echo "installing example audio file and audio tutorial"

if (test ! -d $destdir$datadir/dae/tutorial)
then mkdir -p $destdir$datadir/dae/tutorial||echo failed
fi

cp -r tutorial/* $destdir$datadir/dae/tutorial/.
cp README $destdir$datadir/dae/.
cp COPYING $destdir$datadir/dae/.
cp Changelog $destdir$datadir/dae/.

echo 'to proceed, type "man dae" without quotes and press enter.'

