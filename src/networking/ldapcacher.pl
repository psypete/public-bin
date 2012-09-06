#!/usr/bin/perl
# ldapcacher.pl - make connection pools, load balance requests, cache results
# Copyright (C) 2008-2012 Peter Willis <peterwwillis@yahoo.com>
#
# The purpose of this script is to open one connection to a remote LDAP server,
# take client connections locally, and pass the client messages to the server
# and back. The intention is to take the connection-handling load off the LDAP
# server and only pass messages (so if your ldap server has a connection limit,
# this can help you work around that).
#
# A piece of the LDAP protocol is implemented below. It intercepts the 
# LDAP unbind request, which would normally terminate the connection on
# the server side. Not sending this piece will allow the connection to
# stay open between the local host and the remote server. I have no idea
# if there are any negative consequences to this, it's just a hack.
#


$|=1;
use strict;
use IO::Socket;
use IO::Select;
use Data::Dumper;

my $opts = {
    'localhost' => "127.0.0.1",
    'localport' => 3580,
    'peeraddr' => "ldapproxy.dev.sportsline.com:389",
    ReuseAddr => 0,
    'logpackets' => 1
};

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
            print STDERR "RETURNING\n";
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

sub filter_client_send {
    my ($o, $a, $s) = @_;
    if ( defined $$s[0]->{recvbuf} and length($$s[0]->{recvbuf}) > 0 ) {
        #filter_ldap_searchRequest($o, $a, $s);
        1;
    }
}


# TODO: FIXME !!!!

sub filter_ldap_searchRequest {
    my ($o, $a, $s) = @_;

    my $ldapSearchReq1 = pack("C*", 48, 55, 02, 01); # LDAP packet, new message
    # MessageID
    my $ldapSearchReq2 = pack("C*", 99, 50); # protocolOp
    my $ldapSearchReq3 = pack("C*", 4, 15); # searchRequest
    # baseObject
    my $ldapSearchReq4 = pack("C*", 10, 1); # separator
    # scope
    # $ldapSearchReq4
    # derefAliases
    my $ldapSearchReq5 = pack("C*", 2, 1); # separator
    # sizeLimit
    # $ldapSearchReq5
    # typeLimit
    my $ldapSearchReq6 = pack("C*", 1, 1); # separator 2
    # typesOnly
    my $ldapSearchReq7 = pack("C*", 163, 14); # Filter
    my $ldapSearchReq8 = pack("C*", 4, 3); # filter equalityMatch
    # attributeDesc
    my $ldapSearchReq9 = pack("C*", 4, 7); # equals
    # assertionValue
    my $ldapSearchReq10 = pack("C*", 48, 0); # endSearchRequest

    # find a searchRequest, decode it, cache it
    if ( substr($$s[0]->{recvbuf},0,1) eq chr(48) ) { # Start of LDAP packet
        my $packetsize = substr($$s[0]->{recvbuf},1,1);
        my $packet = substr($$s[0]->{recvbuf},2,$packetsize);
        my ($messageid, $basedn, $scope, $derefaliases, $sizelimit, $typelimit, $typesonly);
        # LDAPMessage
        if ( substr($packet,0,2) eq chr(2).chr(1) ) {
            $messageid = substr($packet,2,1);
            $packet = substr($packet,3);
            # protocolOp searchRequest
            if ( substr($packet,0,1) eq chr(99) ) {
                my $protooplen = substr($packet,1,1);
                $packet = substr($packet,2);
                # searchRequest
                if ( substr($packet,0,1) eq chr(4) ) {
                    my $basednlen = substr($packet,1,1);
                    $basedn = substr($packet,2,$basednlen);
                    $packet = substr($packet,2+$basednlen);
                    if ( substr($packet,0,2) eq chr(10).chr(1) ) {
                        $scope = substr($packet,2,1);
                        $packet = substr($packet,3);
                    }
                    if ( substr($packet,0,2) eq chr(10).chr(1) ) {
                        $derefaliases = substr($packet,2,1);
                        $packet = substr($packet,3);
                    }
                    if ( substr($packet,0,2) eq chr(2).chr(1) ) {
                        $sizelimit = substr($packet,2,1);
                        $packet = substr($packet,3);
                    }
                    if ( substr($packet,0,2) eq chr(2).chr(1) ) {
                        $typelimit = substr($packet,2,1);
                        $packet = substr($packet,3);
                    }
                    if ( substr($packet,0,2) eq chr(1).chr(1) ) {
                        $typesonly = substr($packet,2,1);
                        $packet = substr($packet,3);
                    }
                    # Filter
                    if ( substr($packet,0,2) eq chr(163).chr(14) ) {
                        my $aatr;
                        # TODO: FIXME!!!! This is incomplete!
                    }
                }
            }
        }
    }
}


#    if ( $$s[0]->{recvbuf} =~ /^$ldapSearchReq1(.+)$ldapSearchReq2$ldapSearchReq3(.+)$/o ) {
#        my ($messageID, $searchRequest) = ($1, $2);
#        my ($baseObject, $scope, $derefAliases, $sizeLimit, $typeLimit, $typesOnly, @filter);
#        if ( $searchRequest =~ /^(.+)$ldapSearchReq4(.+)$ldapSearchReq4(.+)$/o ) {
#            ($baseObject, $scope) = ($1, $2);
#            $searchRequest = $3;
#            if ( $searchRequest =~ /^(.+)$ldapSearchReq5(.+)$ldapSearchReq5(.+)$ldapSearchReq6(.)(.+)$/o ) {
#                ($derefAliases, $sizeLimit, $typeLimit, $typesOnly) = ($1, $2, $3, $4);
#                $searchRequest = $5;
#            }
#            # Filter
#            if ( $searchRequest =~ /$ldapSearchReq7(.+)$/o ) {
#                my $filter = $1;
#                # equalityMatch
#                if ( $filter =~ /^$ldapSearchReq8(.+)$ldapSearchReq9(.+)$/
#                    my ($attributeDesc, $assertionValue) = ($1, $2);
#                    
#                push(@filter, 


sub filter_client_recv {
    my ($o, $a, $s) = @_;
    my $ldapUnbindReq1 = pack("C*", 48, 5, 2, 1);
    my $ldapUnbindReq2 = pack("C*", 66, 0);
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

