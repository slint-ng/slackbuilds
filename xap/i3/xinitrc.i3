#!/bin/sh

# Merge in defaults and keymaps
[ -f $usermodmap ] && /usr/bin/xmodmap $usermodmap
[ -f ~/.Xresources ] && xrdb -merge -I$HOME ~/.Xresources

export $(dbus-launch)
exec i3
