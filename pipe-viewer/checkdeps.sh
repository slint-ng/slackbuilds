CWD=$(pwd)
cd /repo/x86_64/slint-15.0/slint
while read i; do
	echo "--- $i ---"
	find  . -name "${i}*txz"
done < "$CWD"/pipe-viewer.sqf
