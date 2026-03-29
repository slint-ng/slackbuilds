#!/bin/sh
if [ -n "$PKG_CONFIG_PATH" ]; then
  PKG_CONFIG_PATH=${PKG_CONFIG_PATH}:/usr/local/lib@LIBDIRSUFFIX@/pkgconfig:/usr/local/share/pkgconfig
else
  PKG_CONFIG_PATH=/usr/local/lib@LIBDIRSUFFIX@/pkgconfig:/usr/local/share/pkgconfig:/usr/lib@LIBDIRSUFFIX@/pkgconfig:/usr/share/pkgconfig
fi
export PKG_CONFIG_PATH
