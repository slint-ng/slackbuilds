#!/bin/bash
#Automatically Created by slkbuild 1.2
#url: http://www.kbd-project.org

###Variables
startdir=$(pwd)
SRC=$startdir/src
PKG=$startdir/pkg

pkgname=kbd
pkgver=2.6.3
pkgrel=1slint
arch=x86_64
numjobs=1
package=$pkgname-$pkgver-$arch-1slint
source=("https://mirrors.edge.kernel.org/pub/linux/utils/kbd/kbd-2.6.3.tar.xz" "fix-euro2.patch" "vlock.pam")
docs=(COPYING CREDITS LICENSE README)
export CFLAGS="-O2 -fPIC"
export CXXFLAGS="-O2 -fPIC"
export SLKCFLAGS="-O2 -fPIC"
export LIBDIRSUFFIX="64"
export ARCH="x86_64"

######Begin Redundant Code######################################
check_for_root() {
    if [ "$UID" != "0" ]; then
        echo -e "\nERROR: You need to be root. Using fakeroot is usually preferable."
        echo "Example command: fakeroot slkbuild -X"
        exit 1
    fi
}

clean_dirs () {
        for COMPLETED in src pkg; do
                if [ -e $COMPLETED ]; then
                        rm -rf $COMPLETED
                fi
        done
}

clean_old_builds () {
    rm -rf $package.{t[xlgb]z,tbr,md5}
    clean_dirs
}

set_pre_permissions() {
    cd $startdir/src
    find -L . \( \
        -perm 777 \
        -o -perm 775 \
        -o -perm 750 \
        -o -perm 711 \
        -o -perm 555 \
        -o -perm 511 \) \
        -print0 | \
        xargs -0r chmod 755
    find -L . \( \
        -perm 666 \
        -o -perm 664 \
        -o -perm 640 \
        -o -perm 600 \
        -o -perm 444 \
        -o -perm 440 \
        -o -perm 400 \) \
        -print0 | \
        xargs -0r chmod 644
}


remove_libtool_archives() {
    [ -d $startdir/pkg/lib${LIBDIRSUFFIX} ] && \
        find $startdir/pkg/lib${LIBDIRSUFFIX} -name "*.la" -delete
    [ -d $startdir/pkg/usr/lib${LIBDIRSUFFIX} ] && \
        find $startdir/pkg/usr/lib${LIBDIRSUFFIX} -name "*.la" -delete
}

gzip_man_and_info_pages() {
    for DOCS in man info; do
        if [ -d "$startdir/pkg/usr/share/$DOCS" ]; then
            mv $startdir/pkg/usr/share/$DOCS $startdir/pkg/usr/$DOCS
            if [[ ! "$(ls $startdir/pkg/usr/share)" ]]; then
                rm -rf $startdir/pkg/usr/share
            fi
        fi
        if [ -d "$startdir/pkg/usr/$DOCS" ]; then
            # I've never seen symlinks in info pages....
            if [ "$DOCS" == "man" ]; then
                (cd $startdir/pkg/usr/$DOCS
                for manpagedir in $(find . -type d -name "man*" 2> /dev/null) ; do
                    ( cd $manpagedir
                    for eachpage in $( find . -type l -maxdepth 1 2> /dev/null) ; do
                        ln -s $( readlink $eachpage ).gz $eachpage.gz
                        rm $eachpage
                    done )
                done)
            fi
            find $startdir/pkg/usr/$DOCS -type f -exec gzip -9 '{}' \;
        fi
    done
    [ -a $startdir/pkg/usr/info/dir.gz ] && rm -f $startdir/pkg/usr/info/dir.gz
}

set_post_permissions() {
    for DIRS in usr/share/icons usr/doc; do
        if [ -d "$startdir/pkg/$DIRS" ]; then
            if [ "$DIRS" == "usr/doc" ]; then
                find -L $startdir/pkg/$DIRS -type f -print0 | \
                    xargs -0r chmod 644
                find -L $startdir/pkg/$DIRS -type d -print0 | \
                    xargs -0r chmod 755
            fi
        fi
        [ -d $startdir/pkg/$DIRS ] && chown root:root -R $startdir/pkg/$DIRS
    done
    [ -d $startdir/pkg/usr/bin ] && find $startdir/pkg/usr/bin -user root -group bin -exec chown root:root {} \;
}

copy_build_script() {
    mkdir -p $startdir/pkg/usr/src/$pkgname-$pkgver/
    [ -f $startdir/SLKBUILD ] && cp $startdir/SLKBUILD    $startdir/pkg/usr/src/$pkgname-$pkgver/SLKBUILD
}

create_package() {
    ls -lR $startdir/pkg
    cd $startdir/pkg
    /sbin/makepkg -p -l y -c n $startdir/$package.txz
    cd $startdir
    md5sum $package.txz > $startdir/$package.md5
}

strip_binaries() {
    cd $startdir/pkg
    find . -print0 | \
        xargs -0r file | \
        grep -e "executable" -e "shared object" | \
        grep ELF | \
        cut -f 1 -d : | \
        xargs strip --strip-unneeded 2> /dev/null || true
}
#########End Redundant Code#####################################
#########Begin Non Redundant Code##############################

prepare_directory() {
    NOSRCPACK=""
    mkdir $startdir/src
    mkdir -p $startdir/pkg/usr/src/$pkgname-$pkgver
    for SOURCES in ${source[@]}; do
        protocol=$(echo $SOURCES | sed 's|:.*||')
            file=$(basename $SOURCES | awk -F= '{print $NF}')
        if [ ! -f "$file" ]; then
            if [ "$protocol" = "http" -o "$protocol" = "https" -o "$protocol" = "ftp" ]; then
                echo -e "\nDownloading $(basename $SOURCES)\n"
                            wget -c --no-check-certificate $SOURCES -O $file
                if [ ! "$?" == "0" ]; then
                    echo "Download failed"
                    exit 2
                fi 
            else
                echo "$SOURCES does not appear to be a url nor is it in the directory"
                exit 2
            fi
        fi
        cp -LR $file $startdir/src
        if ! [ "$protocol" = "http" -o "$protocol" = "https" -o "$protocol" = "ftp" ]; then
            if ! [[ $NOSRCPACK -eq 1 ]]; then
                cp -LR $startdir/$(basename $SOURCES) $startdir/pkg/usr/src/$pkgname-$pkgver/
            fi
        fi
    done
}

extract_source() {
    cd $startdir/src
    if [[ "$(ls $startdir/src)" ]]; then    
        for FILES in ${source[@]}; do
                FILES="$(basename $FILES | awk -F= '{print $NF}')"
            file_type=$(file -biLz "$FILES")
            unset cmd
            case "$file_type" in
                *application/x-tar*)
                    cmd="tar -xf" ;;
                *application/x-zip*)
                    cmd="unzip" ;;
                *application/zip*)
                    cmd="unzip" ;;
                *application/x-gzip*)
                    cmd="gunzip -d -f" ;;
                *application/x-bzip*)
                    cmd="bunzip2 -f" ;;
                *application/x-xz*)
                    cmd="xz -d -f" ;;
                *application/x-lzma*)
                    cmd="lzma -d -f" ;;
                *application/x-rar*)
                    cmd="unrar x" ;;
            esac
            if [ "$cmd" != "" ]; then
                echo "$cmd $FILES"
                        $cmd $FILES
            fi
        done
    elif [ ! "$source" ]; then
        echo -n "" # lame fix
    else
        echo "no files in the src directory $startdir/src"
        exit 2
    fi
}

build () 
{ 
    cd ${pkgname}-$pkgver;
    mv data/keymaps/i386/qwertz/cz{,-qwertz}.map;
    mv data/keymaps/i386/olpc/es{,-olpc}.map;
    mv data/keymaps/i386/olpc/pt{,-olpc}.map;
    mv data/keymaps/i386/fgGIod/trf{,-fgGIod}.map;
    mv data/keymaps/i386/colemak/{en-latin9,colemak}.map;
    patch -Np1 -i ../fix-euro2.patch;
    ./configure --prefix=/usr --sysconfdir=/etc --datadir=/usr/share/kbd --mandir=/usr/share/man --enable-optional-progs;
    exit;
    make KEYCODES_PROGS=yes RESIZECONS_PROGS=yes;
    make KEYCODES_PROGS=yes RESIZECONS_PROGS=yes DESTDIR="$PKG" install;
    mkdir -pm755 $PKG/etc/rc.d;
    cat <<EOF > $PKG/etc/rc.d/rc.font
#!/bin/bash
#
# This selects your default screen font from among the ones in
# /usr/share/kbd/consolefonts.
#
setfont -v
EOF

    chmod 644 $PKG/etc/rc.d/rc.font;
    install -Dm644 ../vlock.pam "$PKG"/etc/pam.d/vlock
}

create_slackdesc() {
mkdir $startdir/pkg/install
cat <<"EODESC" >$startdir/pkg/install/slack-desc
kbd: kbd (Keytable files and keyboard utilities)
kbd: 
kbd: 
kbd: 
kbd: 
kbd: 
kbd: 
kbd: 
kbd: 
kbd: 
kbd: 
EODESC
}

setup_dotnew() {
    for files in etc/rc.d/rc.font ; do
        fullfile="${startdir}/pkg/${files}"
        if [ -e "$fullfile" ]; then
            mv $fullfile ${fullfile}.new
        else
            echo "$fullfile was not found"
            exit 2
        fi
    done
    cat<<"EODOTNEW" >$startdir/pkg/install/doinst.sh
#Added by slkbuild 1.2
dotnew() {
        NEW="${1}.new"
        OLD="$1"
        if [ ! -e $OLD ]; then
                mv $NEW $OLD
        elif [ "$(cat $OLD | md5sum)" = "$(cat $NEW | md5sum)" ]; then
                rm $NEW
        fi
}
dotnew etc/rc.d/rc.font
EODOTNEW
}

copy_docs() {
    for stuff in ${docs[@]}; do
        if [ ! -d "$startdir/pkg/usr/doc/$pkgname-$pkgver" ]; then
            mkdir -p $startdir/pkg/usr/doc/$pkgname-$pkgver
        fi
        find $startdir/src -type f -iname "$stuff" -exec cp -LR '{}' $startdir/pkg/usr/doc/$pkgname-$pkgver \;
    done
}
create_source_file(){
    [ -f $package.src ] && rm $package.src
    if [ ! -z $sourcetemplate ]; then
        echo $sourcetemplate/SLKBUILD >> $package.src
        for SOURCES in ${source[@]}; do
            protocol=$(echo $SOURCES | sed 's|:.*||')
            if ! [ "$protocol" = "http" -o "$protocol" = "https" -o "$protocol" = "ftp" ]; then
                if [ ! -z $sourcetemplate ]; then
                    echo $sourcetemplate/$(basename $SOURCES) >> $package.src
                else
                    echo $(basename $SOURCES) >> $package.src
                fi
            else
                echo $SOURCES >> $package.src
            fi
        done
    fi
}
post_checks(){
    # Ideas taken from src2pkg :)
    if [ -d "$startdir/pkg/usr/doc/$pkgname-$pkgver" ]; then
        for DIRS in usr/doc/$pkgname-$pkgver usr/doc; do
            cd $startdir/pkg/$DIRS
            if [[ $(find . -type f) = "" ]] ; then
                cd ..
                rmdir $DIRS
            fi
        done
    fi
    # if the docs weren't deleted ...
    if [ -d "$startdir/pkg/usr/doc/$pkgname-$pkgver" ]; then
        cd $startdir/pkg/usr/doc/$pkgname-$pkgver
        #remove zero length files
        if [[ $(find . -type f -size 0) ]]; then
            echo "Removing some zero lenght files"
            find . -type f -size 0 -exec rm -f {} \;
        fi
    fi
    # check if we need to add code to handle info pages
    if [[ -d $startdir/pkg/usr/info ]] && [[ ! $(grep install-info $startdir/pkg/install/doinst.sh &> /dev/null) ]] ; then
        echo "Found info files - Adding install-info command to doinst.sh"
        INFO_LIST=$(ls -1 $startdir/pkg/usr/info)
        echo "" >> $startdir/pkg/install/doinst.sh
        echo "if [ -x usr/bin/install-info ] ; then" >> $startdir/pkg/install/doinst.sh
        for page in $(echo $INFO_LIST) ; do
            echo " usr/bin/install-info --info-dir=usr/info usr/info/$page 2>/dev/null" >> $startdir/pkg/install/doinst.sh
        done
        echo "fi" >> $startdir/pkg/install/doinst.sh
    fi
    [[ -e $startdir/pkg/usr/info/dir ]] && rm -f $startdir/pkg/usr/info/dir

}

####End Non Redundant Code############################
#Execution

check_for_root
clean_old_builds
prepare_directory
extract_source
set_pre_permissions
build
if [ ! "$?" = "0" ]; then
    echo "build() failed."
    exit 2
fi
create_slackdesc
post_checks
setup_dotnew
copy_docs
remove_libtool_archives
strip_binaries
gzip_man_and_info_pages
set_post_permissions
copy_build_script
create_package
create_source_file
echo "Package has been built."
