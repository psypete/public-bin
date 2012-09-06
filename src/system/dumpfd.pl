#!/usr/bin/perl
# dumpfd.pl - dump read/write fds from a process using strace
# Copyright (C) 2012 Peter Willis <peterwwillis@yahoo.com>

use strict;
select STDERR;
$|=1;
select STDOUT;
$|=1;

if ( ! @ARGV ) {
    die <<EOF;
Usage: $0 PID | sshd:PID | shell:PID [..]

If PID is passed, a process will have its stdin printed to stdout and its stdout and stderr printed
to stderr

If a literal 'sshd:' followed by a PID is passed, it is assumed this is an sshd child process and
the same basic mechanism happens, only with the file descriptors of the program it's communicating
with (with or without a pty allocated)

If a literal 'shell: followed by a PID is passed, only writes to stdout or stderr will be output. 
This allows for a better real-time experience for programs that echo all input and output by default
EOF
}

for ( @ARGV ) {
    my $ssh = 0;
    if ( s/^sshd://i ) {
        $ssh = 1;
    } elsif ( s/^shell://i ) {
        $ssh = 2;
    }

    if ( ! -d "/proc/$_" && ! kill(0, $_) ) {
            die "Error: invalid pid $_";
    }

    trace_pid($_, $ssh);
}

sub trace_pid {
    my $pid = shift;
    my $ssh = shift;
    my $out;
    my $prev = "";

    open(my $fd, "strace -s16384 -etrace='read,write' -xx -ff -p $pid 2>&1 |") || die "Error: cannot open strace pipe: $!";

    while ( <$fd> ) {
        if ( /^(\[pid (\d+)\] )?(read|write)\((\d+), "(.+)", \d+\)\s+=\s+(\d+)$/ ) {
            my ($blah, $cpid, $call, $fdnum, $buff, $len) = ($1, $2, $3, $4, $5, $6);
            #print STDERR "ssh $ssh blah $blah cpid $cpid call $call fdnum $fdnum buff $buff len $len\n";
            $buff =~ s/\\x([a-f0-9]{2,2})/chr hex $1/oeg;

            # it seems like the sshd child only uses an fd past 7 for the connection to the
            # application (on my linux box anyway)

            if ( $call eq "write" ) {

                if ( $ssh == 1 and $fdnum < 8 ) {
                    next;
                } elsif ( $ssh == 2 and $fdnum > 2 ) {
                    next;
                } elsif ( !$ssh and ( $fdnum != 1 && $fdnum != 2 ) ) {
                    next;
                }

                if ( (!$ssh || $ssh == 2) and $fdnum == 1 ) {
                    print STDOUT $buff;
                } elsif ( (!$ssh || $ssh == 2) and $fdnum == 2 ) {
                    print STDERR $buff;
                }

            } elsif ( $call eq "read" ) {

                if ( $ssh == 1 and $fdnum < 8) {
                    next;
                } elsif ( $ssh == 2 ) {
                    next;
                } elsif ( !$ssh and $fdnum != 0 ) {
                    next;
                }

                print STDOUT $buff;
            }
        }
    }

    close($fd);
}

