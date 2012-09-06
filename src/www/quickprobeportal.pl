#!/usr/bin/perl
# quickprobeportal.pl - Cheap test of common holes in captive portals
# Copyright (C) 2010-2011 Peter Willis <peterwwillis@yahoo.com>
#
# This script comes with no warrany and no license for use.
# Just don't use it, and don't blame me for anything.


# WHY USE IT
#######################################################################
#
# You're looking to find a way out of the captive portal network and on to the
# internet. There are many protocols to abuse to this effect, the most
# reliable being IP over DNS and just plain-old ARP and IP spoofing of
# someone who's already authed to the captive portal.
#
# But that's no fun! This script will help you find some *other* hole
# to abuse for access through the captive portal. If there is an open proxy
# detected you may be able to tunnel out without any special software.
#
# You can find all these holes and more with tools like nmap. This
# script just makes it a little easier.
#
#
# HOW IT WORKS
#######################################################################
#
# The TARGET is a host on the network to abuse for access, usually the
# default gateway. We try to request HTTP access through the proxy and
# if it's successful we can tunnel through HTTP.
#
# If -s option is used the TARGET will be scanned and each open port
# will be tried as a TARGET host:port.
#
# The DESTINATION is something on the internet you want to get access
# to; this could be www.google.com:80 or one of your own servers. It
# is used for ICMP, UDP and proxytunnel testing.
#
# The REMOTE_PROXY is an optional host on the internet you can use to
# tunnel through. If you have set up SSH-over-HTTP, this will be the
# remote proxy used for proxytunnel.
#
#
# HOW TO USE IT
#######################################################################
#
# (without knowing anything about the captive portal)
#   foobar:~$ quickprobeportal.pl -t www.google.com:80 -d www.google.com:80
#
# (check default route's listening http server)
#   foobar:~$ quickprobeportal.pl -t 192.168.0.1:80 -d www.google.com:443
#
# (with SSH-over-HTTP)
#   foobar:~$ quickprobeportal.pl -t 192.168.0.1:80 -d remotehost.com:22 -r remotehost.com:443
#
#
# MORE READING
#######################################################################
#
# Some of the holes found require third-party software running on a
# remote server. Read up here on how to set them up:
#
# IP over ICMP
#   - http://code.gerade.org/hans/
#   - http://hackaday.com/2009/08/21/tunneling-ip-traffic-over-icmp/
#
# IP over DNS
#   - http://code.kryo.se/iodine/
#   - http://think-security.org/ip-over-dns/
#
# SSH over HTTP
#   - http://dag.wieers.com/howto/ssh-http-tunneling/
#   - http://wiki.kartbuilding.net/index.php/Corkscrew_-_ssh_over_https
#
# OpenVPN (udp port 53 tunnel, also works with http proxies)
#   - http://openvpn.net/
#


# TODO:
#  * use HEAD, OPTIONS, other methods to retrieve information from proxy


$|=1;
use strict;
use XML::Simple;
use Getopt::Std;
use IO::Socket::INET;


###
#my $NMAP_OPTIONS = "-p 1-65535 -A -P0 --script=all --open";
#my $NMAP_OPTIONS = "-p 1-1024 -A -P0 --script=all --open";
my $NMAP_OPTIONS = "-sT -P0 --open";
my $PROXYTUNNEL = "/home/psypete/Downloads/proxytunnel-1.9.0-modified/proxytunnel";
my $PROXYTUNNEL_OPTIONS = "-w 2";
my $PING_OPTIONS = "-q -n -c 1";
my $VERBOSE = exists $ENV{VERBOSE} ? $ENV{VERBOSE} : exists $ENV{DEBUG} ? $ENV{DEBUG} : 0;
my $VERSION = "0.1";
my $PARALLEL = 0;
#my $HTTP_TIMEOUT = 8;
#my $PING_TIMEOUT = 8;
my $HTTP_TIMEOUT = 4;
my $PING_TIMEOUT = 4;
my $UDP_TIMEOUT = 4;
my $PROXYTUNNEL_TIMEOUT = 30;
my $SLOW = 1;
my $CHECK_CRLF = 0;
###


main();
exit(0);


sub main {
    my %opt;
    getopts('vst:d:r:p', \%opt);

    die "Usage: $0 [OPTIONS] -t TARGET[:PORT] -d DESTINATION[:PORT] [-r REMOTE_PROXY]\nIf you do not specify a PORT some tests will be omitted.\n\nOptions:\n\t-v\t\tVerbose mode\n\t-s\t\tScan TARGET and test each open port\n\t-p\t\tParallelize scans\n" unless (exists $opt{t} and exists $opt{d});

    $VERBOSE=1 if exists $opt{v};

    $PARALLEL=1 if exists $opt{p};

    my %proxies;

    if ( $opt{"t"} =~ /^(.+):(\d+)$/ ) {
        $proxies{"target-host"} = [ $1 ];
        $proxies{"target-port"} = [ $2 ];
    } else {
        $proxies{"target-host"} = [ $opt{"t"} ];
        $proxies{"target-port"} = [ "80", "443", "3128", "8080" ];
    }
    $proxies{"target"} = [ $opt{"t"} ];

    $proxies{"target-uri"} = [ "/", "http://www.google.com/" ];
    $proxies{"target-response-regex"} = [ "Server: (gws|GFE)" ];

    if ( $opt{"d"} =~ /^(.+):(\d+)$/ ) {
        $proxies{"destination-host"} = [ $1 ];
        $proxies{"destination-port"} = [ $2 ];
    } else {
        $proxies{"destination-host"} = [ $opt{"d"} ];
    }
    $proxies{"destination"} = [ $opt{"d"} ];

    $proxies{"remote-proxy"} = [ $opt{"r"} ] if ( $opt{r} );

    check_icmp(\%proxies);
    check_udp(\%proxies);

    if ( exists $opt{s} ) {
        scan_for_holes(\%proxies);
    } else {
        check_target_stuff(\%proxies);
    }
}

sub check_target_stuff {
    my $self = shift;

    scan_proxy($self);
    scan_proxytunnel($self);
}


sub scan_for_holes {
    my $self = shift;

    foreach my $target ( @{ $self->{"target-host"} } ) {

        print STDERR "Scanning $target for holes\n" if $VERBOSE;
        system("nmap $NMAP_OPTIONS -oX nmap-$target.log $target");
        my $xml = XMLin("nmap-$target.log");
        if ( exists $xml->{"host"} ) {
            if ( exists $xml->{"host"}->{"ports"} and exists $xml->{"host"}->{"ports"}->{"port"} and ref $xml->{"host"}->{"ports"}->{"port"} eq "ARRAY" ) {
                my @a = @{ $xml->{"host"}->{"ports"}->{"port"} };
                foreach my $thing ( @a ) {
                    my %foobar = %$self;
                    my $port = $thing->{"portid"};

                    delete $foobar{"target"};
                    delete $foobar{"target-host"};
                    delete $foobar{"target-port"};

                    $self->{"target"} = [ "$target:$port" ];
                    $self->{"target-host"} = [ "$target" ];
                    $self->{"target-port"} = [ "$port" ];

                    if ( $PARALLEL ) {
                        my $pid = fork;
                        if ( $pid > 0 ) {
                            check_target_stuff($self);
                            exit;
                        }
                        print "Forked scan of " . join("", @{ $self->{target}}) . "\n";
                        sleep 1;
                    } else {
                        check_target_stuff($self);
                    }

                }
            }
        }
    }
}

sub check_icmp {
    my $self = shift;
    return 1 unless exists $self->{"destination-host"};

    foreach my $destination ( @{ $self->{"destination-host"} } ) {
        print STDERR "Checking $destination for icmp ping\n" if $VERBOSE;
        system("ping $PING_OPTIONS -w $PING_TIMEOUT $destination >/dev/null");
        if ( ( $? >> 8) == 0 ) {
            print "Found icmp ping hole for $destination! You can use IP over ICMP.\n";
        }
    }
}

sub check_udp {
    my $self = shift;
    return 1 unless exists $self->{"destination-host"};

    foreach my $destination ( @{ $self->{"destination-host"} } ) {
        print STDERR "Checking $destination:53 for UDP non-DNS traffic\n" if $VERBOSE;

        my $sock = IO::Socket::INET->new(PeerHost => $destination, PeerPort => 53, Proto => "udp", Type => SOCK_DGRAM, Blocking => 1) || die "Error: cannot listen: $! ($@)";

        # this is a dns packet request for www.google.com - but it might be invalid.
        # it's better not to send this because if there's a transparent dns proxy it
        # will just respond with a valid dns response and your packet may not have
        # come from the internet.
        #my @query = qw(af b5 01 00 00 01 00 00 00 00 00 00 03 77 77 77 06 67 6f 6f 67 6c 65 03 63 6f 6d 00 00 01 00 01);
        # this is an openvpn packet
        my @query = qw(38 31 c9 f3 7e cd 9b e9 6f 03 b2 8c 27 77 10 cb 58 f8 f6 b6 82 85 91 81 c7 4c 77 14 da 00 00 00 01 4d 62 fa 4c 00 00 00 00 00);
        my $str1 = join("", map { chr hex $_ } @query );
        #my $str2 = "testing 1 2 3\n";

        # send it 3 times basically just to make sure one of them gets through
        print $sock $str1;
        print $sock $str1;
        print $sock $str1;

        my $TIMEOUT = 4; # it's udp, srsly, either it worked or it didn't
        my $buf;
        eval {
            local $SIG{ALRM} = sub { die "alarm time out" };
            alarm $TIMEOUT;
            recv($sock, $buf, 1024, MSG_WAITALL) or die "recv: $!";
            alarm 0;
            1;  # return value from eval on normalcy
        };
        #or print STDERR "recv from $destination timed out after $TIMEOUT seconds ($! ; $@).\n";
        alarm 0;

        if ( length($buf) > 0 and $buf !~ /^\s+?$/ ) {
            print "Found non-DNS udp traffic from $destination:53! You can tunnel openvpn through udp port 53.\n";
        }
    }
}


sub scan_proxy {
    my $self = shift;
    my %args;

    foreach my $target ( @{ $self->{'target'} } ) {
        %args = ();
        $args{"host"} = $target;

        foreach my $method ( "GET", "POST", "CONNECT" ) {
            $args{"method"} = $method;

            foreach my $uri ( @{ $self->{"target-uri"} } ) {
                $args{"uri"} = $uri;

                my ($tmphost, $tmpport);
                if ( $args{"uri"} =~ /^\w+:\/\/([^\/]+).*$/ ) {
                    $tmphost = $1;
                    if ( $tmphost =~ s/:(\d+)$// ) {
                        $tmpport = $1;
                    } else {
                        $tmpport = "80";
                    }
                }

                # Leave only host:port of URI for CONNECT method
                if ( $method eq "CONNECT" ) {
                    $args{"uri"} = "$tmphost:$tmpport";
                }

                foreach my $ver ( "1.0", "1.1" ) {
                    $args{"http_ver"} = $ver;

                    if ( $ver eq "1.1" ) {
                        $args{"header:Host"} = $tmphost;
                    } else {
                        delete $args{"header:Host"};
                    }

                    # Okay, so i've only taken advantage of this hole once.
                    # It's still interesting to try...
                    my @crlf = ("\r\n");
                    if ( $CHECK_CRLF ) {
                        @crlf = ( "\r\n", "\n" );
                    }
                    foreach my $crlf ( @crlf ) {
                        $args{"crlf"} = $crlf;

                        my $sess = ProbeProxy->new( %args );
                        my $req = $sess->request;
                        $sess->do_http;
    
                        if ( $sess->response =~ /HTTP\/\d+\.\d+ (200|301|302)/ ) {
                            if ( exists $self->{"target-response-regex"} ) {
                                 foreach my $regex ( @{ $self->{"target-response-regex"} } ) {
                                     if ( $sess->response =~ /$regex/ ) {
                                         print "Found open proxy! request: \"$req\"\n";
                                     }
                                 }
                            }
                        }
                    }

                    select(undef, undef, undef, 1.5) if ($SLOW);
                }
            }
        }
    }
}

sub scan_proxytunnel {
    my $self = shift;

    foreach my $target ( @{ $self->{'target'} } ) {
        foreach my $destination ( @{ $self->{'destination'} } ) {

            if ( $self->{'remote-proxy'} ) {
                foreach my $remoteproxy ( @{ $self->{'remote-proxy'} } ) {
                    proxytunnel($target, $destination, $remoteproxy);
                }
            } else {
                proxytunnel($target, $destination);
            }

        }
    }
}

sub proxytunnel {
    my ($target, $destination, $remoteproxy) = @_;
    my $good = 0;
    my $cmd = "$PROXYTUNNEL $PROXYTUNNEL_OPTIONS -p $target -d $destination -H 'User-Agent: Mozilla/4.0 (compatible; MSIE 6.0; Win32)'";
    if ( defined $remoteproxy and length $remoteproxy ) {
        $cmd .= " -r $remoteproxy";
    }
    print STDERR "Doing proxytunnel \"$cmd\"\n" if $VERBOSE;
    my $TIMEOUT = 30;
    my $pid;
    eval {
        local $SIG{ALRM} = sub { die "alarm time out" };
        alarm $TIMEOUT;
        $pid = open(PIPE, "$cmd |") || die "Error: could not execute proxytunnel: $!\n";
        while ( <PIPE> ) {
            s/(\r|\n|\r\n)//g;
            if ( length $_ > 0 ) {
                $good++;
                last;
            }
        }
        1;
    };
    alarm 0;
    if ( $good ) {
        print "Got response from proxytunnel! Working command: \"$cmd\"\n";
    }
    kill(15, $pid);
    kill(9, $pid);
    close(PIPE);
}


##############################################################################################
package ProbeProxy;

use IO::Socket::INET;
#use Carp;

sub new {
    my $self = shift;
    my %h = @_;
    my %defs = ( "peerhost" => undef, "peerport" => 80, "proto" => "tcp" );
    if ( exists $h{"host"} ) {
        if ( $h{"host"} =~ /^(.+):(\d+)$/ ) {
            ($h{"peerhost"}, $h{"peerport"}) = ($1, $2);
        } else {
            $h{"peerhost"} = $h{"host"};
            $h{"peerport"} = "80";
        }
    }
    $self->put_defaults(\%h, \%defs);
    return bless \%h, $self;

}

sub do_http {
    my $self = shift;
    print STDERR "Doing http to $self->{peerhost}:$self->{peerport}\n" if $VERBOSE;
    my $connected = do_http_transport($self, host => $self->{"peerhost"}, port => $self->{"peerport"});

    # If connected but no data, check for ssl
    if ( $connected == 1 and (!exists $self->{"_response_bufer"} or @{ $self->{"_response_buffer"} } < 1) ) {
        if ( test_ssl($self->{"peerhost"}, $self->{"peerport"}) ) {
            print STDERR "SSL detected; retrying $self->{peerhost}:$self->{peerport}\n" if $VERBOSE;
            do_http_transport($self, host => $self->{"peerhost"}, port => $self->{"peerport"}, ssl => 1);
        }
    }
}

sub do_http_transport {
    my $self = shift;
    my %args = @_;

    my $TIMEOUT = 8;
    my $connected = 0;
    my ($conn, $readfh, $writefh, $pid);
    eval {
        local $SIG{ALRM} = sub { die "alarm time out" };
        local $SIG{PIPE} = 'IGNORE';
        alarm $TIMEOUT;
        if ( $args{"ssl"} ) {
            use IPC::Open2;
            print STDERR "Running 'ncat -w $TIMEOUT --ssl $args{host} $args{port}'\n" if $VERBOSE;
            $pid = open2($readfh, $writefh, "ncat -w $TIMEOUT --ssl $args{host} $args{port}");
        } else {
            $conn = IO::Socket::INET->new(PeerAddr => $args{"host"}, PeerPort => $args{"port"}, Proto => 'tcp', Timeout => $TIMEOUT);
            $readfh = $conn; $writefh = $conn;
        }
        if ( ! $pid && ! $conn ) {
            #carp("Could not connect to $args{host}:$args{port} : $!");
            return undef;
        } else {
            $connected = 1;
        }
        alarm($TIMEOUT);
        print $writefh $self->request;
        alarm($TIMEOUT);
        while ( <$readfh> ) {
            push( @{ $self->{"_response_buffer"} }, $_ );
        }
        if ( $pid ) {
            kill(15, $pid);
            kill(9, $pid);
            waitpid($pid, 0);
        }
        close($readfh);
        close($writefh);
        close($conn);
        1;
    };
    alarm 0;

    return $connected;
}


sub request {
    my $self = shift;
    $self->craft_request(@_);
    return $self->{"_request_data"};
}

sub response {
    my $self = shift;
    return exists $self->{"_response_buffer"} ? join( "", @{ $self->{"_response_buffer"} } ) : "";
}

sub craft_request {
    my $self = shift;
    my %args = @_;
    my %defs = ( "method" => "GET", "http_ver" => "1.0", "uri" => "/", "crlf" => "\r\n" );
    $self->put_defaults(\%args, $self); # global defaults override internal defaults
    $self->put_defaults(\%args, \%defs); # internal defaults

    $self->{"_request_data"} = sprintf("%s %s HTTP/%s%s", $args{method}, $args{uri}, $args{http_ver}, $args{crlf});

    $self->{"_request_data"} .= sprintf("Host: %s%s", $args{pass_host}, $args{crlf}) if (defined $args{"pass_host"});

    $self->{"_request_data"} .= sprintf("User-Agent: lynx/1.0.0%sAccept: text/html%sAccept-Encoding: none%s", $args{crlf}, $args{crlf}, $args{crlf});

    while ( my ($k,$v) = each %args ) {
        if ( $k =~ /^header:(.+)$/ ) {
            $self->{"_request_data"} .= sprintf("%s: %s%s", $1, $v, $args{crlf});
        }
    }

    $self->{"_request_data"} .= sprintf("%s", $args{crlf});
}


sub test_ssl {
    my ($host, $port) = @_;
    my $TIMEOUT = 8;
    system("cat /dev/null | ncat -w $TIMEOUT --send-only --ssl $host $port 2>/dev/null");
    if ( ($? >> 8) == 0 ) {
        return 1;
    }
    return 0;
}


sub put_defaults {
    my $self = shift;
    my ($dst, $src) = @_;
    while ( my ($k,$v) = each %$src ) {
        if ( !exists $dst->{$k} ) {
            $dst->{$k} = $v;
        }
    }
}

