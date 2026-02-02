#!/usr/bin/perl -w
system "cp $ARGV[0] $ARGV[0]~";
$Main::bs = undef;
$Main::be = undef;
$Main::changed = 0;

$Main::soort = substr($ARGV[0],length($ARGV[0])-4,4);
$Main::infile = $ARGV[0];
$Main::encoded = 0;
if ($Main::soort eq ".mp3" or $Main::soort eq ".ogg")
{
  $Main::encoded = 1;
  }
  

use ExtUtils::testlib;

use Term::ReadKey;

use Audio::Ecasound qw(:simple :iam);
if ($Main::encoded eq 1)
{
  &convert_first;
  }
  

use strict;
# :iam is nicer without strict 'subs'
no strict 'subs';
on_error('');

# no strict 'subs' lets you do this:
eci("cs_add play_chainsetup
c_add chain1");
eci("-i:$Main::infile
        -o:/dev/dsp
cs_connect"); 

eci("ai-select $Main::infile");

$Main::masterformat = eci("ai-get-format");

 
    
eci("start");
use lib "./blib/lib";
use Term::Screen::ReadLine;

$Term::Screen::ReadLine::scr = new Term::Screen::ReadLine;

# test getch
# clear buffer out
$Term::Screen::ReadLine::scr->flush_input();
$Term::Screen::ReadLine::scr->at(25,0);
printf "master format is: %s ",$Main::masterformat;
$Term::Screen::ReadLine::scr->at(21,0)->puts("Digital audio, Enter Key (q to quit): ")->at(21,40);


$Term::Screen::ReadLine::ch = '';
while(($Term::Screen::ReadLine::ch = $Term::Screen::ReadLine::scr->getch()) ne 'q') 
{
       $Main::keepme = eci("getpos");

if ($Term::Screen::ReadLine::ch eq 'k1')
{
print "stop";
  eci("stop");
}
if ($Term::Screen::ReadLine::ch eq 'k2')
{
print "play";
eci("start");
}
if ($Term::Screen::ReadLine::ch eq 'kl')
{
&move_around;
}

if ($Term::Screen::ReadLine::ch eq 'kr')
{
  &move_around;
}
if ($Term::Screen::ReadLine::ch eq 'k3')
{
print "fast rewind";
eci("rewind 60");
}
if ($Term::Screen::ReadLine::ch eq 'k4')
{
print "fast forward";
eci("forward 60");
}
if ($Term::Screen::ReadLine::ch eq 'k5')
{

  $Main::bs = eci("getpos");
  
  printf "marked block startat : %d", $Main::bs;
}
if ($Term::Screen::ReadLine::ch eq 'k6')
{
$Main::be = eci("getpos");
printf "marked block end at : %d", $Main::be;
}

if ($Term::Screen::ReadLine::ch eq 'k7')
{
   $Main::vra = 0;
   $Main::blockout = "block$Main::soort";
  &writeblock;
printf "played %d second block", $Main::time;
}

if ($Term::Screen::ReadLine::ch eq 'k8')
{
    printf "\n file name to write block as? ";
  $Main::vra = 1;
  &writeblock;
printf "written %d second block to %s ", $Main::time, $Main::blockout;
}
if ($Term::Screen::ReadLine::ch eq 'k9')
{
  &delblock;

}
if ($Term::Screen::ReadLine::ch eq 'k10')
{
&record;
print "insert real-time";
}
if ($Term::Screen::ReadLine::ch eq 'k11')
{
  Term::ReadKey::ReadMode(1);
  system "pickafile";
    Term::ReadKey::ReadMode(0);
    $Main::fromfile =  `cat \$HOME/.kies/.\`getterm\`file`;
        chomp $Main::fromfile;
        &check_for_encoded;
        &record;
printf "inserted file : %s ",$Main::fromfile;
}
if ($Term::Screen::ReadLine::ch eq 'k12')
{
  $Main::einde = eci("cs-get-length");
    eci("setpos $Main::einde");
printf "go to end at : %d", $Main::einde;
}
if ($Term::Screen::ReadLine::ch eq 'kh')
{
    eci("setpos 0");
printf "go to start";
}
if ($Term::Screen::ReadLine::ch eq 'w')
{
printf "now at : %f ",$Main::keepme;
}
if ($Term::Screen::ReadLine::ch eq 'j')
{
printf "jump to? ";
    $Main::jump = $Term::Screen::ReadLine::scr->readline;
        eci("setpos $Main::jump");
}
if ($Term::Screen::ReadLine::ch eq 'h')
{
  $Term::Screen::ReadLine::scr->at(25,1)->puts("f1 stop f2 play f3 fr f4 ff f5 begin-block f6 end-block f7 play-block f8 write-block f9 del-block f10 record f11 ins-file f12 goto end");
}



      $Term::Screen::ReadLine::scr->at(21,40);
}

$Term::Screen::ReadLine::scr->at(22,0);


#stop;
eci("cs_disconnect");
eci("cs-remove default");


if ($Main::encoded eq 1 and $Main::changed eq 1)
{
   &convert_back;
   }
print "exiting.";
   
sub convert_first
{
printf "decoding %s first, please wait.",$Main::infile;
if ($Main::soort eq ".ogg")
{
  system "ogg123 $Main::infile -dwav -f editme.wav";
}
if ($Main::soort eq ".mp3")
{
system "mpg123 $Main::infile -w editme.wav";
}
$Main::orig_soort = $Main::soort;


  $Main::soort = ".wav";
$Main::infile = "editme.wav";
}

sub convert_back
{
printf "encoding %s first, please wait.",$ARGV[0];
if ($Main::orig_soort eq ".ogg")
{
  system "oggenc $Main::infile -o $ARGV[0]";
  }
  if ($Main::orig_soort eq ".mp3")
  {
    system "lame $Main::infile $ARGV[0]";
    }
unlink $Main::infile;


}


sub check_for_encoded

{
$Main::fromfiletype = substr($Main::fromfile,length($Main::fromfile)-4,4);

printf "decoding %s first, please wait.",$Main::fromfile;
if ($Main::fromfiletype eq ".ogg")
{
  system "ogg123 $Main::fromfile -dwav -f realtime.wav";
}
if ($Main::fromfiletype eq ".mp3")
{
system "mpg123 $Main::fromfile -w realtime.wav";
}
if ($Main::fromfiletype eq ".ogg" or $Main::fromfiletype eq ".mp3")
{
$Main::fromfile = "realtime.wav";
print "in if file type is : ",$Main::fromfiletype," from file is ",$Main::fromfile,"\n";

}
print "fromfile is ",$Main::fromfile;


}

sub delblock
{
if (!defined($Main::bs))
{
   printf "no block start defined\n";
       return;
       }
if (!defined($Main::be))
{
   printf "no block end defined\n";
       return;
       }
       
$Main::changed = 1;

unlink "l$Main::soort";
unlink "r$Main::soort";

$Main::time = $Main::be - $Main::bs;

eci("stop
 cs-disconnect default
cs-remove default");
#create chain to grab left side
eci("cs-add default
-i:$Main::infile
-o:l$Main::soort -t:$Main::bs
cs-connect
run");
eci("cs-disconnect default
cs-remove default");

#create chain to grab right side
eci("cs-add default
-i:$Main::infile -y:$Main::be
-o:r$Main::soort
cs-connect
run");
eci("cs-disconnect default
cs-remove default");


#restore modified file
unlink $Main::infile;
#create chain to concat left and right sides
eci("cs-add default
-i:r$Main::soort
-o:l$Main::soort -y:$Main::bs
cs-connect
run");
while (eci("engine-status") eq "running")
{
#wait
}

eci("cs-disconnect default
cs-remove default");
rename "l$Main::soort", $Main::infile;
$Main::bs = undef;
$Main::be = undef;
printf "deleted %d second block", $Main::time;
&playagain;
}

sub writeblock
{
if (!defined($Main::bs))
{
   printf "no block start defined\n";
       return;
       }
if (!defined($Main::be))
{
   printf "no block end defined\n";
       return;
       }

if ($Main::vra eq 1) {
  $Main::blockout = $Term::Screen::ReadLine::scr->readline;
  }


$Main::time = $Main::be - $Main::bs;

eci("stop
 cs-disconnect default
cs-remove default");
unlink "block$Main::soort";

#create chain to write block
eci("cs-add default
-i:$Main::infile -y:$Main::bs
-o:$Main::blockout -t:$Main::time
cs-connect");
eci("run");
if ($Main::vra ne 1)
  {
eci("cs-disconnect
  cs-remove default
  cs-add default
  -i:block$Main::soort
  -o:/dev/dsp
  cs-connect default
  start");
  
       
$Term::Screen::ReadLine::ch = '';
while(($Term::Screen::ReadLine::ch = $Term::Screen::ReadLine::scr->getch()) ne 'q') 
{
if ($Term::Screen::ReadLine::ch eq 'k1')
{
print "stop";
  eci("stop");
}
if ($Term::Screen::ReadLine::ch eq 'k2')
{
print "play";
eci("start");
}
if ($Term::Screen::ReadLine::ch eq 'kl')
{
&move_around;
}

if ($Term::Screen::ReadLine::ch eq 'kr')
{
  &move_around;
}
if ($Term::Screen::ReadLine::ch eq 'k3')
{
print "fast rewind";
eci("rewind 60");
}
if ($Term::Screen::ReadLine::ch eq 'k4')
{
print "fast forward";
eci("forward 60");
}
if ($Term::Screen::ReadLine::ch eq 'k12')
{
  $Main::einde = eci("cs-get-length");
    eci("setpos $Main::einde");
printf "go to end at : %d", $Main::einde;
}

      $Term::Screen::ReadLine::scr->at(21,40);
}

       }
       
eci("cs-disconnect default
cs-remove default");
&playagain;

}

sub record
{
$Main::changed = 1;

unlink "l$Main::soort";
unlink "r$Main::soort";

eci("stop");
$Main::plek = eci("getpos");

eci("cs-disconnect default
cs-remove default");
#create chain to grab left side
eci("cs-add default
-i:$Main::infile
-o:l$Main::soort -t:$Main::plek
cs-connect
run");
eci("cs-disconnect default
cs-remove default");

#create chain to grab right side
eci("cs-add default
-i:$Main::infile -y:$Main::plek
-o:r$Main::soort
cs-connect
run");
eci("cs-disconnect default
cs-remove default");
if ($Term::Screen::ReadLine::ch eq "k10")
  {
  
#record from soundcard
    unlink "realtime$Main::soort";
eci("cs-add default
-f:$Main::masterformat
-i:/dev/dsp
-o:realtime$Main::soort -ea:900
cs-connect");

$Term::Screen::ReadLine::ch = '';
while(($Term::Screen::ReadLine::ch = $Term::Screen::ReadLine::scr->getch()) ne 'q') 
{
if ($Term::Screen::ReadLine::ch eq 'k1')
{
print "stop";
  eci("stop");
}
if ($Term::Screen::ReadLine::ch eq 'k2')
{
print "start";
eci("start");
}
}
$Term::Screen::ReadLine::ch = "";
eci("cs-disconnect
cs-remove default");
    $Main::fromfile = "realtime$Main::soort";
    
}

#restore modified file
unlink $Main::infile;
#create chain to concat left, recorded and right files
 
eci("cs-add default
-f:$Main::masterformat
-i:resample-hq,auto,$Main::fromfile
-o:l$Main::soort -y:$Main::plek
cs-connect
run");
$Main::plek = $Main::plek + eci("getpos");

eci("cs-disconnect default
cs-remove default");
 
eci("cs-add default
-i:r$Main::soort
-o:l$Main::soort -y:$Main::plek
cs-connect
run
cs-disconnect
cs-remove default");

rename "l$Main::soort", $Main::infile;
&playagain;
}

sub playagain 
{

eci("cs-add default
-i:$Main::infile
-o:/dev/dsp
cs-connect default
setpos $Main::keepme
start");

}

sub move_around
{
$Main::move_count = 1;
$Main::engine = eci("engine-status");
if ($Main::engine eq 'running')
{
  eci("stop");
  }
if ($Term::Screen::ReadLine::ch eq 'kl')
{
  $Main::direction = 'rewinding';
  }
  else
  {
    $Main::direction = 'forwarding';
    }
    
  
while($Term::Screen::ReadLine::scr->key_pressed(1)) 
{
$Main::move_count = $Main::move_count + 1;
$Term::Screen::ReadLine::ch = $Term::Screen::ReadLine::scr->getch();
}
if ($Main::direction eq 'rewinding')
{
  eci("rewind $Main::move_count");
  }
  else 
  {
    eci("forward $Main::move_count");
    }
 printf "%s %d seconds",$Main::direction,$Main::move_count;    
    
if ($Main::engine eq 'running')
{
eci("start");
}

}
