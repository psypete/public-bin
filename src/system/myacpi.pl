#!/usr/bin/perl
# myacpi.pl - listen for acpi events as my user and take actions
# Copyright (C) 2010 Peter Willis <peterwwillis@yahoo.com>
#
# i could set up scripts in /etc/acpi/ but it's just barely annoying enough for me not to care to
# set it up when i can just run it out of my home environment.
#

$|=1;

use strict;
my $HOME = (getpwuid($>))[7] || $ENV{HOME};


if ( $ARGV[0] eq "-d" ) {
    close(STDIN);
    close(STDOUT);
    close(STDERR);
    use POSIX qw(setsid);
    setsid();
    fork && exit;
} elsif ( $ARGV[0] =~ /^(-h|--help)$/ ) {
    die "Usage: $0 [-d]\n";
}

lockme();
acpi_listen();
exit(0);

sub acpi_listen {
    my $r = open(PIPE, "acpi_listen |") || die "Error: could not run acpi_listen: $!";
    select PIPE;
    $|=1;
    select STDOUT;

    while ( <PIPE> ) {
        chomp;
        my @stuff = split(/\s+/, $_);
        run_event(@stuff);
    }
}

# there's probably no reason i couldn't just background each one of these runs to prevent an
# event subroutine from blocking the loop above.
sub run_event {
    my ($type, $cmd, $arg1, $arg2) = @_;

    if ( $type eq "hotkey" ) {
        if ( $cmd eq "ATKD" ) {

            if ( $arg1 eq "00000031" ) { # volume down
                volume_down();
            } elsif ( $arg1 eq "00000030" ) { # volume up
                volume_up();
            } elsif ( $arg1 eq "00000032" ) { # volume mute
                volume_mute();
            } elsif ( $arg1 eq "0000005d" ) { # wifi toggle
                toggle_wifi();
            }

        } elsif ( $cmd eq "SLPB" ) { # sleep button
            suspend();
        }
    } elsif ( $type eq "button/lid" ) {
        if ( $cmd eq "LID" ) {
            do_lid();
        }
    }
}

sub volume_down {
    system("amixer set Master 2dB-");
}

sub volume_up {
    system("amixer set Master 2dB+");
}

sub volume_mute {
    system("amixer set Master toggle");
}

sub toggle_wifi {
    my @INTERFACES = map { chomp $_ ; $_ } `iwconfig 2>&1 | grep IEEE | awk '{print \$1}'`;
    my @UP_INTFS = map { chomp $_ ; $_ } `ifconfig 2>&1 | grep 'Link ' | awk '{print \$1}'`;
    foreach my $intf (@INTERFACES) {
        if ( ! grep(/^$intf$/, @UP_INTFS) ) {
            system("sudo ifconfig $intf up");
        } else {
            system("sudo ifconfig $intf down");
        }
    }
}

sub suspend {
    system("sudo suspend.sh");
}

sub do_lid {
    system("xlock &");
}

sub lockme {
    if ( -e "$HOME/.myacpilck" ) {
        open(FILE,"<$HOME/.myacpilck") || die "Error: Could not open $HOME/.myacpilck";
        my $foo = <FILE>;
        close(FILE);
        chomp $foo;
        if ( kill(0, $foo) ) {
            die "Error: $0 already running (pid $foo)\n";
        }
    }

    unlink("$HOME/.myacpilck");
    
    open(FILE, ">$HOME/.myacpilck") || die "Error: could not make lock $HOME/.myacpilck";
    print FILE "$$\n";
    close(FILE);
}

