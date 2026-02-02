#!/bin/sh

# add a dummy dotool to $PATH so this doesn't require /dev/uinput
export PATH="$PWD/dummy:$PATH"

if test "$(NUMEN_PIPE=/tmp/numen-test-pipe numen --audio=test.wav test.phrases)" = \
'n
u
m
e
n'
then
	echo PASSED TEST
else
	echo FAILED TEST
	exit 1
fi
