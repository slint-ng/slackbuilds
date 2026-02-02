#!/usr/bin/env bash
pushd /opt/I38 || exit
./i38.sh "$@"
popd || exit
exit 0
