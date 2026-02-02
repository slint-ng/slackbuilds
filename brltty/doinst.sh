
config() {
  NEW="$1"
  OLD="`dirname $NEW`/`basename $NEW .new`"
  # If there's no config file by that name, mv it over:
  if [ ! -r $OLD ]; then
    mv $NEW $OLD
  elif [ "`cat $OLD | md5sum`" = "`cat $NEW | md5sum`" ]; then # toss the redundant copy
    rm $NEW
  fi
  # Otherwise, we leave the .new copy for the admin to consider...
}
config etc/brltty.conf.new
config etc/rc.d/rc.brltty.new
if [ ! -f etc/brlapi.key ]; then
	brltty-genkey
	chgrp braille etc/brlapi.key
	chmod 640 etc/brlapi.key
fi
mkdir -p /var/brltty
if [ "$(grep ^pulse-access /etc/group)" = "" ]; then
	groupadd -g 493 pulse-access
fi
if [ "$(grep ^brltty /etc/passwd)" = "" ]; then
	brltty-mkuser -N
fi
brltty-setcaps $(which brltty)


