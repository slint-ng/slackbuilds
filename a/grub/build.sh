build() {
  for i in ${_platform}; do
    echo "Unset CFLAGS for build..."
    unset CFLAGS
    cp -r "${srcdir}/grub" "${srcdir}/grub-${i}"
    cd "${srcdir}/grub-${i}"
    echo "Run ./configure for ${i} build..."

    # Handle different platforms and append to _configure_options
    _configure_options=""
    if [ "$i" = "i386-pc" ]; then
      _configure_options="--enable-efiemu --with-platform=pc --target=i386"
    elif [ "$i" = "i386-efi" ]; then
      _configure_options="--disable-efiemu --with-platform=efi --target=i386"
    elif [ "$i" = "x86_64-efi" ]; then
      _configure_options="--with-platform=efi --target=x86_64"
    fi

    ./configure PACKAGE_VERSION="${epoch}:${pkgver}-${pkgrel}" ${_configure_options}

    if [ "$i" = "x86_64-efi" ]; then
      echo "Build language and doc files only for most common variant..."
      # language directory does not like -j option, build it first with -j1
      make -j1 po/
    else
      sed -i -e 's#po docs##' Makefile
    fi

    echo "Run make for ${i} build..."
    make

    # Ensure reproducibility of info pages if SOURCE_DATE_EPOCH is set
    if [ -n "$SOURCE_DATE_EPOCH" ]; then
      echo "Make info pages reproducible..."
      find . -name '*.texi' -exec touch -d "@${SOURCE_DATE_EPOCH}" {} \;
    fi
  done
}
