#!/usr/bin/perl
# bluelock.pl v0.4 - lock a screen once a bluetooth device's RSSI increases
# Copyright (C) 2008 Peter Willis <peterwwillis@yahoo.com>
#
# Changes since v0.3:
#  - Try adding a bit more sleeping to let rfcomm connect successfully, and
#    don't count the connection time against the counter.
#  - Handle rfcomm execution/reaping better
#  - Use 'hci0' instead of 'bluelock0' for default rfcomm/hci device name
#
# Changes since v0.2:
#  - Only poll essi after establishing an rfcomm connection, so as to get more
#    reliable results. May add an option in the future which doesn't rely on
#    the device supporting an rfcomm connection (assuming not all devices do?)
#
# Changes since v0.1:
#  - Ensure only 1 instance running at a time (improves cron use)
#
# Edit the values below depending on your bluetooth settings and locker tool.
# I have mine set to lock 15 seconds after the RSSI is greater than 1; of course
# the RSSI fluctuates above this quite commonly but it usually hits 1 or 0
# within 15 seconds and resets the timer. Expand these values to fit your needs.
#
# Also, since hcitool needs to be root to initiate a connection you'll probably
# want to set this up as a cronjob run as root every minute. You can change the
# locker to su to a user to lock a display as mine does (DISPLAY default set
# below as well).
#

use strict;
use POSIX qw(setsid);

$|=1;
$SIG{CHLD} = 'IGNORE';

if ( !exists $ARGV[0] ) {
    die "Usage: $0 BDADDR\n";
}

# Useful if the locker is for a display running on :0
if ( !exists $ENV{DISPLAY} ) {
        $ENV{DISPLAY} = ":0";
}
my $VERBOSE = exists $ENV{VERBOSE} ? $ENV{VERBOSE} : 0;
my $EXPIRE = 15; # time in seconds before locking
my $THRESH = 1; # when the RSSI is above this, start the expire timer
my $LOCKER = "su pwillis -c \"alock -auth md5:file=/spln/pwillis/home/.alockrc -bg shade:color=green -cursor glyph:name=coffee_mug\"";
my $HCITOOL = "/usr/bin/hcitool";
my $RFCOMM = "/usr/bin/rfcomm";
my $BADDR = $ARGV[0];
my $TIMER = time();
my $COUNTDOWN = 0;

# Check if another instance of bluelock is already running
if ( open(LOCK,"<$ENV{HOME}/.bluelock") ) {
        my $pid = <LOCK>;
        chomp $pid;
        if ( kill(0,$pid) ) {
                print "BLUELOCK ALREADY RUNNING ($pid); EXITING\n";
                exit(1);
        }
        close(LOCK);
}

# Set our PID as the currently-running bluelock
if ( open(LOCK,">$ENV{HOME}/.bluelock") ) {
        print LOCK "$$\n";
        close(LOCK);
}

my ($rfcomm_good, $RF_FH);

for ( ;; ) {

    try_locker();

    # Keep an rfcomm connection open so we can rssi continuously
    my $rfpid = fork();
    if ( $rfpid == 0 ) {
        close(STDIN);
        close(STDOUT);
        close(STDERR);
        setsid();
        chdir("/");
        exec($RFCOMM, "connect", "hci0", $BADDR);
        exit(0);
    }

    if ( ! check_rfcomm(30) ) {
	kill(9, $rfpid);
        sleep 5;
        next;
    }

    # Poll RSSI information for as long as the rfcomm is open
    for ( ;; ) {
        my ($FH);
        my $RSSI = 9999;

        try_locker();

        # Instead of checking for a $pid above, just see if there's any rfcomm
        # connection live and go back to the beginning if there's not
        if ( ! check_rfcomm(1) ) {
            kill(9, $rfpid);
            sleep 5;
            last;
        }

        open($FH, "$HCITOOL rssi $BADDR |");
        while ( <$FH> ) {
            if ( /^RSSI return value: -?([\d]+)/ ) {
                $RSSI = $1;
                print "FOUND RSSI $RSSI\n" if $VERBOSE >= 3;
            }
        }
        # When RSSI goes over THRESH, TIMER stops being set, and it will
        # eventually be $EXPIRE below the current time.
        if ( $RSSI <= $THRESH ) {
            $TIMER = time();
            print "RSSI $RSSI <= THRESH $THRESH\n" if $VERBOSE >= 2;
        }
        # The quicker this polls, the more likely we could get a really low RSSI
        #select undef, undef, undef, 0.50;
        select undef, undef, undef, 1.00;
    }
}

sub try_locker {
    # Start by seeing if the timer expired, and if so run $LOCKER
    my $tmptime = time();
    print "tmptime - TIMER = " . ($tmptime - $TIMER) . "\n" if $VERBOSE;
    if ( ($tmptime - $TIMER) > $EXPIRE ) {
        print "LOCKING\n" if $VERBOSE;
        system($LOCKER);
        sleep 30; # just to give the user time to unlock the screen if this was an accident 
        $TIMER = time();
    }   
}

sub check_rfcomm {
    my $times = shift;

    # Check for an open rfcomm connection for up to 30 seconds.
    # Will add lost time back to the timer below
    my $rfcomm_good = 0;
    my $i;
    for ( $i = 0; $i < $times; $i++ ) {
        if ( open(my $tmpfh, "$RFCOMM show -a 2>/dev/null |") ) {
            while ( <$tmpfh> ) {
                if ( /^([\w]+):.+\s$BADDR\s.+connected/ ) {
                    $rfcomm_good++;
		    #print "FOUND RFCOMM CONNECTED TO DEVICE $1\n" if $VERBOSE;
                }
            }
            close($tmpfh);
        }
        last if $rfcomm_good;
        sleep 1;
    }

    $TIMER += $i;

    if ( ! $rfcomm_good ) {
        print "ERROR: NO RFCOMM CONNECTION FOUND\n" if $VERBOSE;
    }

    return $rfcomm_good;
}

