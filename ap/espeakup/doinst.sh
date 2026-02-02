config() {
        NEW="${1}.new"
        OLD="$1"
        if [ ! -e $OLD ]; then
                mv $NEW $OLD
        elif [ "$(cat $OLD | md5sum)" = "$(cat $NEW | md5sum)" ]; then
                rm $NEW
        fi
}
config etc/espeakup.conf



