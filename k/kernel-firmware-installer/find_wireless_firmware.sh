#!/bin/sh
find /lib/modules/6.6.31 -mindepth 1 -maxdepth 1 -print | sort -zr
exit
dir="$(find /lib/modules/ -mindepth 1 -maxdepth 1 -print | sort -zr | head -zn1)"
find "$dir" -type f -name '*.ko' |
while read -r m ; do
 /sbin/modinfo "$m" |
 grep -E '^(firmware:|depends:.*firmware)' |
 sed -e "s#.*#$m#"
done |
sort -u |
while read -r m ; do
 s=${m##*/}
 (
  /sbin/modinfo "$m" |
  (
   grep -E '^description' ||
   echo 'description:    (none)'
  )
  /sbin/modinfo "$m" |
  grep -E '^firmware') |
  sort |
  sed -e '2,0s/^description:.*//' \
      -e '/^description:/s/\([A-Z][a-z0-9]\+\)\{2,\}/!\0/g' \
      -e "s#^description:[[:blank:]]*\(.*\)#||$s||''\1''||#" \
      -e 's#^firmware:[[:blank:]]*\(.*\)#[[DebianPkg:file:\1|\1]]<<BR>>#' |
  tr -d '\n' |
  sed -e 's/<<BR>>$//' \
      -e 's/$/||\n/'
done |
sort
