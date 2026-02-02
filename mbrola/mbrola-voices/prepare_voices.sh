#!/bin/sh
CWD=$(pwd)
( cd voices
for i in $(ls ls *zip); do 
	mkdir -p ${i%.zip}
	unzip  $i -d ${i%.zip}
done
)
