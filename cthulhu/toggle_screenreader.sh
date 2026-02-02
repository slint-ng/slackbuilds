#!/usr/bin/env bash

# This file is part of I38.

# I38 is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
                                                                                                                                                                          
# I38 is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
# PURPOSE. See the GNU General Public License for more details.
                                                                                                                                                                          
# You should have received a copy of the GNU General Public License along with I38. If not, see <https://www.gnu.org/licenses/>.

#!/bin/bash

# Function to check if a process is running
is_running() {
    pgrep -x "$1" >/dev/null
    return $?
}

# Speak messages
speak() {
    spd-say -P important -Cw -- "$*"
}

# Make sure both screen readers are available
for i in $(command -v cthulhu 2> /dev/null) $(command -v orca 2> /dev/null) ; do
    if ! command -v "$i" &> /dev/null ; then
        speak "${i##*/} not found, cannot switch to it."
        exit 1
    fi
done

# Toggle between screen readers
if is_running "cthulhu"; then
    speak "Switching from Cthulhu to Orca..."
    pkill -15 cthulhu
    sleep .5
    command orca &
elif is_running "orca"; then
    speak "Switching from Orca to Cthulhu..."
    pkill -15 orca
    sleep .5
    command cthulhu &
fi

exit 0
