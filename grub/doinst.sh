#!/bin/sh
config() {
  NEW="$1"
  OLD="$(dirname "$NEW")/$(basename "$NEW" .new)"
  # If there's no config file by that name, mv it over:
  if [ ! -r "$OLD" ]; then
    mv "$NEW" "$OLD"
  elif [ "$(md5sum "$OLD")" = "$(md5sum "$NEW")" ]; then
    # toss the redundant copy
    rm "$NEW"
  fi
  # Otherwise, we leave the .new copy for the admin to consider...
}

# Process config files in etc/grub.d/:
for file in etc/grub.d/*.new ; do
  config "$file"
done
config etc/default/grub.new

[ -f /etc/slint-version ] && sh /usr/sbin/post-upgrade-grub

