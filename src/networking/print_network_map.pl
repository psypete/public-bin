#!/usr/bin/perl
# print_network_map.pl - takes an nmap XML output and prints a basic map of the routes and hosts (requires --traceroute)

$|=1;
use strict;
use XML::Simple;
use Data::Dumper;


die "Usage: $0 XML\n" unless @ARGV == 1;

exit main();


sub main {

    my $XML = XMLin($ARGV[0], ForceArray => 1);

    my $data = collect_host_data($XML);
    #print Dumper($data);

    print_network_map($data);

}


# This just prints out $data->{'path'} in a nice way
sub print_network_map {
    my $d = shift;

    my $count = 0;
    my $pos = $d->{'path'}->{'127.0.0.1'};

    recurse_map($d, $pos, $count);

}

sub recurse_map {
    my $d = shift;
    my $ptr = shift;
    my $c = shift;
    my @keys = sort { 
        keys %{ $ptr->{$a} } <=> keys %{ $ptr->{$b} }
    } keys %$ptr;

    foreach my $key (@keys) {
        #my $space = "    " x $c;
        my $space = "\t" x $c;
        my $string = "$space $d->{'addrs'}->{$key}->{'type'} $key";
        if ( defined $d->{'addrs'}->{$key}->{'hostname'} ) {
            $string .= " ($d->{'addrs'}->{$key}->{'hostname'})";
        }
        print $string . "\n";

        if ( %{ $ptr->{$key} } ) {
            recurse_map( $d, $ptr->{$key}, $c+1 );
        }
    }
}


sub collect_host_data {
    my $x = shift;
    my $hosts = $x->{'host'};

    my %data = ( 'well' => {}, 'addrs' => {}, 'path' => { "127.0.0.1" => {} } );
    my $path; # = $data{'path'}->{"127.0.0.1"};

    for ( my $i = 0; $i < @$hosts; $i++ ) {
        my $host = $hosts->[$i];
        my $address = $host->{'address'}->[0]->{'addr'};
        my @hnames = keys %{ $host->{'hostnames'}->[0]->{'hostname'} };

        $data{'addrs'}->{$address} = {} if ( !exists $data{'addrs'}->{$address} );
        $data{'addrs'}->{$address}->{'hostname'} = shift @hnames;
        $data{'addrs'}->{$address}->{'address'} = $address;

        if ( exists $host->{'trace'} ) {
            my $trace = $host->{'trace'};
            
            my $j;
            for ( $j = 0; $j < @$trace; $j++ ) {
                my $t_j = $trace->[$j];

                if ( exists $t_j->{'hop'} ) {
                    my $hop = $t_j->{'hop'};

                    my $k;
                    for ( $k = 0; $k < @$hop; $k++ ) {
                        my $hop_k = $hop->[$k];

                        if ( exists $hop_k->{'ttl'} and exists $hop_k->{'ipaddr'} ) {

                            # Let's record the network path of each hop
                            if ( $k == 0 ) {
                                $path = $data{'path'}->{"127.0.0.1"};
                            } else {
                                $path->{ $hop_k->{'ipaddr'} } = {} if (!exists $path->{ $hop_k->{'ipaddr'} });
                                $path = $path->{ $hop_k->{'ipaddr'} };
                            }

                            # Make a link back from this hop to the host it came from
                            $data{'well'}->{ $hop_k->{'ttl'} }->{ $hop_k->{'ipaddr'} } = $data{'addrs'}->{$address};

                            # Default to assuming all traceroute hops are routers
                            $data{'addrs'}->{ $hop_k->{'ipaddr'} }->{'type'} = "router";
                            if ( !exists $data{'addrs'}->{ $hop_k->{'ipaddr'} }->{'hostname'} and exists $hop_k->{'host'} and length $hop_k->{'host'} ) {
                                $data{'addrs'}->{ $hop_k->{'ipaddr'} }->{'hostname'} = $hop_k->{'host'};
                            }
                        }
                    }

                    # But if it's the last hop, it could be a host at the end of a traceroute
                    $data{'addrs'}->{ $hop->[$k-1]->{'ipaddr'} }->{'type'} = "host";
                }
            }
        }
    }

    return \%data;
}

