config() {
  NEW="$1"
  OLD="$(dirname $NEW)/$(basename $NEW .new)"
  # If there's no config file by that name, mv it over:
  if [ ! -r $OLD ]; then
    mv $NEW $OLD
  elif [ "$(cat $OLD | md5sum)" = "$(cat $NEW | md5sum)" ]; then
    # toss the redundant copy
    rm $NEW
  fi
  # Otherwise, we leave the .new copy for the admin to consider...
}

create_user_and_group() {
  if ! grep -q fcron /etc/group; then
    groupadd -g 289 fcron
  fi
  if ! grep -q fcron /etc/passwd; then
    useradd  -u 289 -g fcron -d /var/spool/fcron -M -s /bin/false fcron
  fi
}

create_user_and_group
config etc/fcron.conf.new
config etc/fcron.allow.new
config etc/fcron.deny.new
if [ ! -f /var/spool/fcron/root.orig ]; then
	cp /etc/fcron/root.orig /var/spool/fcron/
	fcrontab -z -u root
	chown root:root /var/spool/fcron/*
fi
