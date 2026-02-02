if  ls /var/lib/pkgtools/packages/|grep -q at-spi2-atk- ; then
	/sbin/removepkg at-spi2-atk
fi
if ls /var/lib/pkgtools/packages/|grep -q atk- ; then
	/sbin/removepkg atk
fi
