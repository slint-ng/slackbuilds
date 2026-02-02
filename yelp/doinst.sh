if [ -x /usr/bin/update-desktop-database ]; then
  /usr/bin/update-desktop-database -q usr/share/applications >/dev/null 2>&1
fi

if [ -x /usr/bin/update-mime-database ]; then
  /usr/bin/update-mime-database usr/share/mime >/dev/null 2>&1
fi

if [ -e usr/share/icons/hicolor/icon-theme.cache ]; then
  if [ -x /usr/bin/gtk-update-icon-cache ]; then
    /usr/bin/gtk-update-icon-cache -f usr/share/icons/hicolor >/dev/null 2>&1
  fi
fi

if [ -e usr/share/glib-2.0/schemas ]; then
  if [ -x /usr/bin/glib-compile-schemas ]; then
    /usr/bin/glib-compile-schemas usr/share/glib-2.0/schemas >/dev/null 2>&1
  fi
fi
#mv usr/bin/yelp /usr/libexec/yelp
#cat << EOF > usr/bin/yelp
##!/bin/sh
#LD_LIBRARY_PATH=/usr/libexec/yelp-webkit/lib64/ /usr/libexec/yelp
#EOF
#chmod 755 /usr/bin/yelp /usr/libexec/yelp
#chown root: /usr/bin/yelp