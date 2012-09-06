#!/usr/bin/perl
# simpleconnectionpool.pl - make connection pools, load balance requests
#
# this script connects to a remote server and listens for client connections locally.
# it passes messages between the client and the server.
# the end result will be the ability to fine-tune the rate at which data enters the server
# so as not to overload it.


$|=1;
use strict;
use IO::Socket;
use IO::Select;
use Data::Dumper;

my $opts = {
    'localhost' => "ops255.dev.sportsline.com",
    'localport' => 3580,
    'peeraddr' => "ldapproxy.dev.sportsline.com:389",
    ReuseAddr => 0,
    'logpackets' => 1
};
my $ldapUnbindReq1 = pack("C*", 48, 5, 2, 1);
my $ldapUnbindReq2 = pack("C*", 66, 0);

main();


sub main {
    my @clientpool;
    my @serverpool;

    my $serv = IO::Socket::INET->new( PeerAddr => $opts->{peeraddr} ) || die "Error: could not connect to $opts->{peeraddr}: $!\n";
    $serverpool[0] = { 'sock' => $serv, 'host' => $opts->{peeraddr} };

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

        select(undef, undef, undef, 0.001);
    }
}

sub talk_to {
    my $o = shift;
    my $a = shift;
    my $s = shift;

    if ( @$a ) {

        if ( ref($$a[0]) eq "HASH" and keys(%{$a->[0]}) < 1 ) {
            shift @$a;
            print "RETURNING\n";
            return;
        }

        if ( my $pn = getpeername($$a[0]->{sock}) and $$a[0]->{sock}->connected ) {
            my ($port, $iaddr) = sockaddr_in( $pn );
            my $host = inet_ntoa($iaddr);
            #print STDERR "INFO: Still connected to $host:$port\n";
        } else {
            print STDERR "INFO: No longer connected to $$a[0]->{host}\n";
            if ( $o->{logpackets} && exists $o->{"fh:".$$a[0]->{host}} ) {
                close( $o->{ "fh:" . $$a[0]->{host} } );
                delete $o->{"fh:".$$a[0]->{host}};
            }
            shift @$a;
            return;
        }

        # Talk to the server
        if ( can_send($$s[0]->{sock}) && $$s[0]->{sendbuf} ) {
            print STDERR "INFO: Sending " . length($$s[0]->{sendbuf}) . " bytes to server\n";
            $$s[0]->{sock}->send( $$s[0]->{sendbuf} );
            undef $$s[0]->{sendbuf};
        }
        if ( can_recv($$s[0]->{sock}) ) {
            print STDERR "INFO: Receiving from server ... ";
            undef $$s[0]->{recvbuf};
            $$s[0]->{sock}->recv($$s[0]->{recvbuf}, 8192);
            print STDERR length($$s[0]->{recvbuf}) ." bytes\n";
            if ( !defined $$s[0]->{recvbuf} or length($$s[0]->{recvbuf}) < 1 ) {
                print STDERR "We were told we could recv but got no data. Connection must be closed!\n";
                # Send a packet to reset the getpeername structure
                $$a[0]->{sock}->send("\n");
            }
        }

        # Talk to the client
        if ( can_send($$a[0]->{sock}) && $$s[0]->{recvbuf} ) {
            print STDERR "INFO: Sending " . length($$s[0]->{recvbuf}) . " bytes to client\n";
            my $res = $$a[0]->{sock}->send( $$s[0]->{recvbuf} );
            undef $$s[0]->{recvbuf};
        }
        if ( can_recv($$a[0]->{sock}) ) {
            print STDERR "INFO: Receiving from client .. ";
            undef $$s[0]->{sendbuf};
            $$a[0]->{sock}->recv($$s[0]->{sendbuf}, 8192);
            print STDERR length($$s[0]->{sendbuf}) . " bytes\n";
            if ( !defined $$s[0]->{sendbuf} or length($$s[0]->{sendbuf}) < 1 ) {
                #print STDERR "We were told we could recv but got no data. Connection must be closed!\n";
                # Send a packet to reset the getpeername structure
                $$a[0]->{sock}->send("\n");
            } else {
                if ( $o->{logpackets} and exists $o->{"fh:".$$a[0]->{host}} ) {
                    syswrite($o->{"fh:".$$a[0]->{host}}, "\nPACKET\n" . $$s[0]->{sendbuf});
                }
            }
            filter_client_recv($o, $a, $s);
        }

    }
}

sub filter_client_recv {
    my ($o, $a, $s) = @_;
    if ( defined $$s[0]->{sendbuf} and length($$s[0]->{sendbuf}) > 0 ) {
        if ( $$s[0]->{sendbuf} =~ /^$ldapUnbindReq1.*$ldapUnbindReq2$/o ) {
            print STDERR "INFO: Skipping LDAP unbindRequest\n";
            undef $$s[0]->{sendbuf};
        }
    }
}

sub can_accept {
    my $o = shift;
    my $s = shift;
    if ( my $sock = $s->accept() ) {
        my ($port, $iaddr) = sockaddr_in( $sock->peername() );
        my $host = inet_ntoa($iaddr);
        print STDERR "INFO: Accepted connection from $host:$port\n";

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
        print STDERR "INFO: can_send() exception found\n";
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
        print STDERR "INFO: can_send() exception found\n";
    }
    return vec($rout,$fh,1);
}

sub start_listen {
    my $o = shift;
    my $listen = IO::Socket::INET->new( LocalHost => $o->{localhost}, LocalPort => $o->{localport}, Proto => 'tcp', Listen => SOMAXCONN, ReuseAddr => exists $o->{ReuseAddr} ? $o->{ReuseAddr} : 1, Blocking => 0, Timeout => 0 );
    if ( !defined $listen ) {
        die "Error: could not listen on $o->{localhost}:$o->{localport}: $!\n";
    }
    return($listen);
}

