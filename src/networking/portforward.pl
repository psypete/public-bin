#!/usr/bin/perl
# portforward.pl
# Copyright (C) 2009 Peter Willis <peterwwillis@yahoo.com>

$|=1;
use strict;
use IO::Socket;
use IO::Select;

my $opts = {
    'localaddr' => ($ARGV[0] =~ /^(\d+)$/ ? "0.0.0.0:$1" : $ARGV[0]),
    'peeraddr' => ($ARGV[1] =~ /^(\d+)$/ ? "0.0.0.0:$1" : $ARGV[1]),
    ReuseAddr => 1,
    'logpackets' => 0,
    VERBOSE => 1,
    DAEMON => 0
};

if ( @ARGV < 2 ) {
    die "Usage: $0 SRC DST\n  SRC and DST may be just a port or a host:port\n  (host defaults to 0.0.0.0)\n";
}

if ( exists $opts->{DAEMON} and $opts->{DAEMON} ) {
    use POSIX qw(setsid);
    setsid();
    fork && exit;
}

main();


sub main {
    my @clientpool;
    my @serverpool;

    #@serverpool = start_connect($opts);

    my $sock = start_listen($opts);
    for ( ;; ) {
        if ( my ($fh, $host) = can_accept($opts, $sock) ) {
            if ( defined $fh and defined $host ) {
                push (@clientpool, { 'sock' => $fh, 'host' => $host } );
                next;
            }
        }

        talk_to($opts, \@clientpool, \@serverpool);

        if ( !defined $sock ) {
            die "Error: sock died! weird\n";
        }

        # TODO: rewrite this whole app using some event-driven thing
        # so this doesn't suck up the CPU.
        select(undef, undef, undef, 0.01);
    }
}

sub talk_to {
    my $o = shift;
    my $a = shift;
    my $s = shift;
    my $bufsiz = 8192;

    if ( @$a < 1 and @$s > 0 ) {

        print STDERR "All clients disconnected; killing server connection\n" if $o->{VERBOSE};
        close($$s[0]->{'sock'});
        shift @$s;

    } elsif ( @$a > 0 ) {

        if ( ref($$a[0]) eq "HASH" and keys(%{$a->[0]}) < 1 ) {
            shift @$a;
            print STDERR "RETURNING\n" if $o->{VERBOSE};
            return;
        }

        if ( my $pn = getpeername($$a[0]->{sock}) and $$a[0]->{sock}->connected ) {
            my ($port, $iaddr) = sockaddr_in( $pn );
            my $host = inet_ntoa($iaddr);
            #print STDERR "INFO: Still connected to $host:$port\n";
        } else {
            print STDERR "INFO: No longer connected to $$a[0]->{host}\n" if $o->{VERBOSE};
            if ( $o->{logpackets} && exists $o->{"fh:".$$a[0]->{host}} ) {
                close( $o->{ "fh:" . $$a[0]->{host} } );
                delete $o->{"fh:".$$a[0]->{host}};
            }
            shift @$a;
            return;
        }

        my $connect = 0;
        if ( @{$a} > 0 and @{$s} < 1 ) {
            $connect = 1;
        } elsif ( @{$a} > 0 and @{$s} > 0 and (! getpeername($$s[0]->{sock}) or ! $$s[0]->{sock}->connected) ) {
            print STDERR "INFO: No longer connected to server $$s[0]->{host}\n" if $o->{VERBOSE};
            shift @$s;
            $connect = 1;
        }
        if ( $connect ) {
            push @{$s}, start_connect($o);
        }

        # Talk to the server
        if ( can_send($$s[0]->{sock}) && $$s[0]->{sendbuf} ) {
            print STDERR "INFO: Sending " . length($$s[0]->{sendbuf}) . " bytes to server\n" if $o->{VERBOSE};
            $$s[0]->{sock}->send( $$s[0]->{sendbuf} );
            undef $$s[0]->{sendbuf};
        }
        if ( can_recv($$s[0]->{sock}) ) {
            print STDERR "INFO: Receiving from server ... " if $o->{VERBOSE};
            undef $$s[0]->{recvbuf};
            $$s[0]->{sock}->recv($$s[0]->{recvbuf}, $bufsiz);
            print STDERR length($$s[0]->{recvbuf}) ." bytes\n" if $o->{VERBOSE};
            if ( !defined $$s[0]->{recvbuf} or length($$s[0]->{recvbuf}) < 1 ) {
                print STDERR "INFO: We were told we could recv from server but got no data. Connection must be closed!\n" if $o->{VERBOSE};
                # Send a packet to reset the getpeername structure
                $$s[0]->{sock}->send("\n");
            }
        }

        # Talk to the client
        if ( can_send($$a[0]->{sock}) && $$s[0]->{recvbuf} ) {
            print STDERR "INFO: Sending " . length($$s[0]->{recvbuf}) . " bytes to client\n" if $o->{VERBOSE};
            my $res = $$a[0]->{sock}->send( $$s[0]->{recvbuf} );
            undef $$s[0]->{recvbuf};
        }
        if ( can_recv($$a[0]->{sock}) ) {
            print STDERR "INFO: Receiving from client .. " if $o->{VERBOSE};
            undef $$s[0]->{sendbuf};
            $$a[0]->{sock}->recv($$s[0]->{sendbuf}, $bufsiz);
            print STDERR length($$s[0]->{sendbuf}) . " bytes\n" if $o->{VERBOSE};
            if ( !defined $$s[0]->{sendbuf} or length($$s[0]->{sendbuf}) < 1 ) {
                print STDERR "INFO: We were told we could recv from client but got no data. Connection must be closed!\n" if $o->{VERBOSE};
                # Send a packet to reset the getpeername structure
                $$a[0]->{sock}->send("\n");
            } else {
                if ( $o->{logpackets} and exists $o->{"fh:".$$a[0]->{host}} ) {
                    syswrite($o->{"fh:".$$a[0]->{host}}, "\nPACKET\n" . $$s[0]->{sendbuf});
                }
            }
            #filter_client_recv($o, $a, $s);
        }

    }
}


sub can_accept {
    my $o = shift;
    my $s = shift;
    if ( my $sock = $s->accept() ) {
        my ($port, $iaddr) = sockaddr_in( $sock->peername() );
        my $host = inet_ntoa($iaddr);
        print STDERR "INFO: Accepted connection from $host:$port\n" if $o->{VERBOSE};

        if ( $o->{logpackets} ) {
            my $fh;
            $o->{"conn:$host:$port"}++;
            open($fh, ">packets_$host-$port\_".$o->{"conn:$host:$port"}.".dump");
            $o->{"fh:$host:$port"} = $fh;
        }

        return($sock, "$host:$port");
    #} else {
    #    print STDERR "INFO: can_accept() failed: $! ($@)\n";
    }
}

sub can_send {
    my $s = shift || return;
    my $fh = fileno($s);
    my ($win, $wout, $ein, $eout);
    vec($win,$fh,1)=1;
    vec($ein,$fh,1)=1;
    select(undef,$wout=$win,$eout=$ein,0);
    if ( vec($eout,$fh,1) == 1 ) {
        print STDERR "INFO: can_send() exception found\n" if $opts->{VERBOSE};
    }
    return vec($wout,$fh,1);
}

sub can_recv {
    my $s = shift || return;
    my $fh = fileno($s);
    my ($rin, $rout, $ein, $eout);
    vec($rin,$fh,1)=1;
    vec($ein,$fh,1)=1;
    select($rout=$rin,undef,$eout=$ein,0);
    if ( vec($eout,$fh,1) == 1 ) {
        print STDERR "INFO: can_send() exception found\n" if $opts->{VERBOSE};
    }
    return vec($rout,$fh,1);
}

sub start_listen {
    my $o = shift;
    my $listen = IO::Socket::INET->new( LocalAddr => $o->{localaddr}, Proto => 'tcp', Listen => SOMAXCONN, ReuseAddr => exists $o->{ReuseAddr} ? $o->{ReuseAddr} : 1, Blocking => 0, Timeout => 0 );
    if ( !defined $listen ) {
        die "Error: could not listen on $o->{localhost}:$o->{localport}: $!\n";
    }
    return($listen);
}

sub start_connect {
    my $o = shift;
    my $sock = IO::Socket::INET->new( PeerAddr => $o->{peeraddr} ) || die "Error: could not connect to $o->{peeraddr}: $!\n";
    print STDERR "INFO: Connected to server $o->{peeraddr}\n" if $o->{VERBOSE};
    return( { 'sock' => $sock, 'host' => $o->{peeraddr} } );
}

