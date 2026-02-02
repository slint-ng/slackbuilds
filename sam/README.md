#Speech-friendly Alsa Mixer (sam)
---------------------------------

Controling Alsa using a console terminal only is somewhat cumbersome.
The interactive tools is not speech-friendly, so I tried my hand at writing
a mixer which works well with  a screen reader, Speakup in my case.

##Features
----------
###Allow selection of the sound card to work on when there are more than one
such device in your machine.
When there is only one, it directly presents the different mixers
for configuration.
###All selections, be it sound cards, mixers or a given feature of a
###specific mixer are selected by scrolling through the available options
###using the up and down arrows, then entering on the desired one.
q leave the selection list and/or quits.  Shift-q exits the program from
anywhere.  F1 Displays any extra information if available.
When the name of the desired option is known, one can instead press its
first letter. First-letter navigation is case-insensitive.
That will then take you to the first selection starting with the pressed
letter.  Pressing the same letter again, will move you to the next option
starting with that letter ifmore than one option like that exists. 
Repeating the letter will cycle among all those options starting with that
letter.

###The settable features of a mixer can be  listed by pressing f1.
They are presented as a selection list, showing briefly all relevant information, e.g. 
"playback volume down from 84 percent" is the option to lower the playback volume
setting of the playback volume.  As you can see, it also tells you what the
current setting is.
##Limitations
-------------
Alsa allows the different channels of a mixer to be set individually.
Sam always set them together. So you cannot set the left channel to 20
percent and the right one to 50 percent using Sam.

##Requirements
--------------
Python and specifically the alsaaudio python module.
On all my machines, that was installed already, but the latest version
0.8.4, is required.
Catchkey, supplied with Sam for catching the keys you press.
Note, the program will not work correctly from a terminal under X-windows.
It only works in a true console, Usually set up as tty1 through tty6 on most
machines.

#Installation
-------------

1. Install python-alsaaudio package.
This is for Debian-based distributions like Ubuntu.
apt-get install python-alsaaudio
Note the version must be 0.8.4 and might not be the one provided by your
package manager.  In such a case, try installation using pip.

2. Install pyalsaaudio using pip.
  pip install --upgrade  pyalsaaudio or
  pip3 install --upgrade  pyalsaaudio if your distribution runs python3 by
default.
On my Ubuntu ,machine, I had to remove the package installed version first.
apt-get purge python-alsaaudio
3. Alternatively, grab the tar.gz from https://files.pythonhosted.org/packages/52/b6/44871791929d9d7e11325af0b7be711388dfeeab17147988f044a41a6d83/pyalsaaudio-0.8.4.tar.gz
and install by extracting the file, going into the created directory and
running
python setup.py build install as root.

4. Copy sam and catchkey into your execution path, e.g.
sudo cp sam /usr/local/bin/.
and sudo cp catchkey /usr/local/bin/.

#Running sam
------------

from the dollar prompt, just type sam and enter.
You do need to have permissions to control your sound devices from your
user.

#Copyright
----------

(C) 2019 Willem van der Walt <wvdwalt@csir.co.za>
Sam is released under the GNU license version 3 or later.
See the file COPYING for details.


