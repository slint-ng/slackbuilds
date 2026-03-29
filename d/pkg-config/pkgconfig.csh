#!/bin/csh
if ( $?PKG_CONFIG_PATH ) then
    setenv PKG_CONFIG_PATH ${PKG_CONFIG_PATH}:/usr/local/lib@LIBDIRSUFFIX@/pkgconfig:/usr/local/share/pkgconfig
else
    setenv PKG_CONFIG_PATH /usr/local/lib@LIBDIRSUFFIX@/pkgconfig:/usr/local/share/pkgconfig:/usr/lib@LIBDIRSUFFIX@/pkgconfig:/usr/share/pkgconfig
endif
