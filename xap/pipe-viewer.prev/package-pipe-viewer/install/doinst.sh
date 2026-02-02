
if [ -x /usr/bin/update-desktop-database ]; then
  /usr/bin/update-desktop-database -q usr/share/applications >/dev/null 2>&1
fi

if [ -e usr/share/icons/hicolor/icon-theme.cache ]; then
  if [ -x /usr/bin/gtk-update-icon-cache ]; then
    /usr/bin/gtk-update-icon-cache usr/share/icons/hicolor >/dev/null 2>&1
  fi
fi
( cd usr/share/applications ; rm -rf gtk-pipe-viewer.desktop )
( cd usr/share/applications ; ln -sf ../perl5/vendor_perl/auto/share/dist/WWW-PipeViewer/gtk-pipe-viewer.desktop gtk-pipe-viewer.desktop )
( cd usr/share/pixmaps ; rm -rf gtk-pipe-viewer.png )
( cd usr/share/pixmaps ; ln -sf ../icons/hicolor/48x48/apps/gtk-pipe-viewer.png gtk-pipe-viewer.png )
