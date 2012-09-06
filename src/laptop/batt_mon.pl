#!/usr/bin/perl
# batt_mon.pl v0.1 - monitor battery use, give warnings, take actions
# Copyright (C) 2009 Peter Willis <peterwwillis@yahoo.com>
#
# Pretty simple.
# Either report on current battery usage,
# or monitor battery usage and warn/sleep/hibernate as needed.

$|=1;
use strict;

# Default settings. Edit as appropriate
my $SLEEP = 60; # Time to wait in seconds between polls
my $ALERT_ON_WARN = 1; # Should we alert X and beep if warn state is reached?
my $SLEEP_ON_LOW = 0; # Should we sleep if low state is reached?
my $HIBERNATE_ON_LOW = 1; # Should we hibernate if low state is reached?
my $NOTIFY = "xosd"; # Notification method

my $APP_NAME = "batt_mon";

if ( ! @ARGV ) {
    die "Usage: $0 CMD [batt ..]\nCommands:\n  monitor\t\tMonitor battery state, take action accordingly\n  report\t\tReport battery status\n";
}

my $CMD = shift @ARGV;

for ( ;; ) {

    # List batteries or get list from cmdline
    my @batts;
    if ( @ARGV ) {
        @batts = @ARGV;
    } else {
        opendir(DIR,"/proc/acpi/battery") || die "Error: no ACPI battery stats\n";
        @batts = grep(!/^\.\.?$/,readdir(DIR));
        closedir(DIR);
    }

    foreach my $batt (@batts) {

        my ($capacity, $warning, $low, $state, $rate, $left);

        # Collect battery stats
        open(BATT, "/proc/acpi/battery/$batt/info") || die "no info for $batt";
        while (<BATT>) {
            if ( /design capacity:\s+(\d+)/ ) {
                $capacity = $1;
            } elsif ( /design capacity warning:\s+(\d+)/ ) {
                $warning = $1;
            } elsif ( /design capacity low:\s+(\d+)/ ) {
                $low = $1;
            }
        }
        close(BATT);
        open(BATT, "/proc/acpi/battery/$batt/state") || die "no state for $batt";
        while (<BATT>) {
            if ( /charging state:\s+(\w+)/ ) {
                $state = $1;
            } elsif ( /present rate:\s+(\d+)/ ) {
                $rate = $1;
            } elsif ( /remaining capacity:\s+(\d+)/ ) {
                $left = $1;
            }
        }
        close(BATT);
        
        my $warning_p = int ( ($warning/$capacity) * 100 );
        my $low_p = int ( ($low/$capacity) * 100 );
        my $rate_p = int ( ($rate/$capacity) * 100 );
        my $left_p = int ( ($left/$capacity) * 100 );

        if ( $CMD eq "report" or $ENV{VERBOSE} or $ENV{DEBUG} ) {
            print "$batt: state $state warning $warning_p\% low $low_p\% left $left_p\%\n";
        }

        # Only action alerts while monitoring on battery
        if ( $CMD eq "monitor" and $state eq "discharging" ) {
            my ($warn_state, $low_state) = (0, 0);
            if ( $left_p <= $warning_p ) {
                $warn_state++;
            }
            if ( $left_p < $low_p ) {
                $low_state++;
            }

            if ( $low_state ) {
                if ( $ALERT_ON_WARN ) {
                    batt_warning("ALERT! BATTERY DANGEROUSLY LOW! $low_p\% LEFT");
                }
                if ( $SLEEP_ON_LOW ) {
                    batt_warning("Battery low. Sleeping computer now.");
                    sleep($SLEEP); # Give people a chance to react
                    batt_sleep();
                }
                if ( $HIBERNATE_ON_LOW ) {
                    batt_warning("Battery low. Hibernating computer now.");
                    sleep($SLEEP); # Give people a chance to react
                    batt_hibernate();
                }
            } elsif ( $warn_state ) {
                if ( $ALERT_ON_WARN ) {
                    my $alert = "Alert: Battery at $left_p\%!";
                    if ( $SLEEP_ON_LOW ) {
                        $alert .= " Sleeping when battery < $low_p\%";
                    } elsif ( $HIBERNATE_ON_LOW ) {
                        $alert .= " Hibernating when battery < $low_p\%";
                    }
                    batt_warning($alert);
                }
            }
        }

    }

    sleep $SLEEP;
}

# 

sub batt_warning {
    if ( $NOTIFY eq "libnotify" ) {
        send_libnotify(@_);
    } elsif ( $NOTIFY eq "kdialog" ) {
        send_kdialog(@_);
    } elsif ( $NOTIFY eq "dzen" ) {
        send_dzen(@_);
    } elsif ( $NOTIFY eq "xosd" ) {
        send_xosd(@_);
    }
    send_logger(@_);
}

sub send_xosd {
    my $log = shift;
    my $d = shift || 5;

    probe_x_function( \&_send_xosd, $log, $d );
}

sub _send_xosd {
    my $d = $_[1];
    # red text, default font at 24 point, top centered offset 10 pixels, shadow
    my $opts = "-d $d -c red -f \"-*-*-bold-*-*-*-24\" -A center -o 10 -s 1";
    if ( ! open(PIPE, "| osd_cat $opts") ) {
        print STDERR "Error: could not open pipe to osd_cat: $!\n";
        return 0;
    }
    print PIPE $_[0];
    close(PIPE);
}

sub send_logger {
    open(PIPE, "| logger -s") || die "Error: couldn't open pipe to logger: $!\n";
    print PIPE "$APP_NAME\[$$\]: $_[0]\n";
    close(PIPE);
}

sub batt_sleep {
    system("chvt 1");
    sleep(5);
    if ( ! open(BATT, ">/sys/power/state") ) {
        print STDERR "Error: can not write to /sys/power/state: $!\n";
        return 0;
    }
    print BATT "mem";
    close(BATT);
}

sub batt_hibernate {
    if ( ! open(SWAP,"/proc/swaps") ) {
        print STDERR "Error: no swap partition information?\n";
        return 0;
    }
    my @swaps = grep(!/^Filename/,<SWAP>);
    close(SWAP);
    if ( ! @swaps ) {
        print STDERR "Error: no swap paritions found. Swap needed for hibernate mode.\n";
        return 0;
    }
    system("chvt 1");
    sleep(5);
    if ( ! open(BATT, ">/sys/power/state") ) {
        print STDERR "Error: can not write to /sys/power/state: $!\n";
        return 0;
    }
    print BATT "disk";
    close(BATT);
}

# The idea here is to cycle through all the displays found
# and pass the right DISPLAY= and XAUTHORITY= variables
# so an X application can run correctly despite not knowing anything
# about the running X server.
#
# WARNING
#
# This could be incredibly insecure. In fact it probably is.
# Oops.
# (Letting a non-root user control an app running as root is a pretty
# bad thing in general)
#
# The safest thing would probably be to create a user:group specific
# to this app and have the called function copy the following files
# to a temp dir only owned by this app's user, change to that user
# and run the app, so the X windows user could only control files
# relating to their own X server. If you're saying to yourself
# "Oh i'll just use the nobody user" you don't really get security
# at all and you should step away from the root prompt right now.
#
# WARNING
sub probe_x_function {
    my $function = shift;

    # Try each :DISPLAY found via their sockets
    foreach my $display ( glob("/tmp/.X11-unix/X*") ) {
        $display =~ s/^.*X(\d+)$/$1/;
        $ENV{DISPLAY} = ":$display";

        # Try each possible readable Xauthority file
        foreach my $auth ( ("$ENV{HOME}/.Xauthority", glob("/var/run/xauth/*")) ) {
            if ( -r $auth ) {
                $ENV{XAUTHORITY} = $auth;
                &$function(@_);
            }
        }
    }
}

