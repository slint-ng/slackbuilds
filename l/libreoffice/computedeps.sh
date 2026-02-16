# THis scripts adds .dep files to files in $A including "libreoffice",
# and case occurring, a matcing dictionary package name.
CWD=$(pwd)
rm -f nomatch
A=../../slint/locales
B=../../slint/dict
(cd $A || exit
for i in *txz; do
	dict=$(echo $i|sed "s/l10n/dict/")
	if [ -f $B/$dict ]; then
		depdict=$(echo $dict|sed "s/-[^-]*-[^-]*-[^-]*$//")
		echo "libreoffice,$depdict" > ${i%txz}dep 
	else 
	echo "libreoffice" > ${i%txz}dep
	echo $i >> $CWD/nomatch
	fi
done
)

