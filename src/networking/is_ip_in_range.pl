#!/usr/bin/perl

$|=1;
use strict;

my %opts;


if ( ! options() ) {

    die <<EOUSAGE;
Usage: $0 OPTIONS [IP ..]

Options:
  -r RANGE      A subnet ('1.2.3.4/25' or '1.2.3.4/255.255.253.0') or an 
                explicit range ('1.2.3.4-1.2.50.66')
  -f FILE       A file with a list of IP addresses to be checked against RANGE
  -v            Verbose mode

This script checks to see if IP is within RANGE.
You can specify multiple -r options, and the IPs that follow the option will
be checked against that range.

If you specify multiple -r options without any IPs, the first set of IPs will
be used to check each range.

Examples:
    $0 -r 192.168.0.0/16 192.169.3.4
    $0 -r 10.0.1.0/24 -r 10.1.1.0/24 -r 10.2.1.0/24 10.1.1.55 10.1.1.56 10.1.1.57
    $0 -r 8.0.0.0/8 8.8.8.8 -r 4.0.0.0/8 4.2.2.1 4.2.2.2
EOUSAGE

}


main();

exit(0);



sub main {

    foreach my $key (
        sort {
            $a cmp $b
        } grep(/^r:/, keys %opts)
    ) {
        my $range;
        ($range = $key) =~ s/^r://;
        my $a = $opts{$key};

        # Nifty recursive dereferencing!
        while ( ref($a) eq "REF" ) {
            $a = $$a;
        }

        my @r = get_range($range);
        is_in_range( $range, \@r, $a );
    }

}


sub options {
    my ($gotip, $gotrange) = (0, 0);

    # process arguments
    for ( my $i=0; $i<@ARGV; $i++ ) {
    
        if ( $ARGV[$i] eq "-r" and (($i+1) < @ARGV) ) {
    
            my $oldr;
            if ( exists $opts{'r'} ) {
                $oldr = $opts{'r'};
            }
            $opts{'r'} = $ARGV[++$i];
            $opts{'r:'.$opts{'r'}} = [];
    
            # Never added any IPs to $oldr, so link previous range to new range
            if ( defined $oldr and (!exists $opts{"r:$oldr"} or @{ $opts{"r:$oldr"} } < 1) ) {
                my $foo = \$opts{"r:$opts{r}"};
                $opts{"r:$oldr"} = $foo;
            }

            $gotrange++;
    
            next;

        } elsif ( $ARGV[$i] eq "-f" and (($i+1) < @ARGV) ) {
            open(my $fd, "<$ARGV[++$i]") || die "Cannot read $ARGV[$i]: $!";
            push( @{$opts{"r:$opts{r}"}}, map { s/(\r|\n)//g; $_ } <$fd> );

            $gotip++;

        } elsif ( $ARGV[$i] eq "-v" ) {
            $opts{'verbose'}++;
    
        } else {
            push( @{ $opts{'r:'.$opts{'r'}} }, $ARGV[$i] );

            $gotip++;

        }
    
    }

    return ( $gotip && $gotrange );
}
    
    
sub get_range {
    my $range = shift;
    my @range;

    # Handle subnet range
    if ( $range =~ /^(.+)\/(.+)$/ ) {
        my ($r_ip, $r_mask) = ($1, $2);

        $r_ip = ip2dec($r_ip);

        # handle "1.2.3.4/8"
        if ( $r_mask !~ /\./ ) {
            #$r_mask = ((4294967295 << $r_mask) & 4294967295);
            # if r_mask was 8, r_mask becomes 255.0.0.0
            $r_mask = (~(4294967295 >> $r_mask) & 4294967295);
        }

        elsif ( $r_mask =~ /\./ ) {
            $r_mask = ip2dec($r_mask);
        }
        
        @range = (
            ($r_ip & $r_mask) & 4294967295,
            (($r_ip & $r_mask) + ( ~ $r_mask )) & 4294967295
        );

    # Handle explicit range
    } elsif ( $range =~ /^(.+)-(.+)$/ ) {
        @range = ( ip2dec($1), ip2dec($2));
    }

    print "Range: " . dec2ip($range[0]) . " - " . dec2ip($range[1]) . "\n" if exists $opts{verbose};

    return @range;
}



sub is_in_range {
    my $rangename = shift;
    my $r = shift;
    my $ips = shift;
    my $ip_d;

    for ( @$ips ) {
        $ip_d = ip2dec($_);

        if ( ($ip_d > $r->[0]) && ($ip_d < $r->[1]) ) {
            print "$_ is in range $rangename\n";
        } else {
            print "$_ not in range $rangename\n" if exists $opts{verbose};
        }
    }

}


sub print_stats {

    my ($ipaddress, $netmask);

    # Calculate network address by logical AND operation of addr & netmask
    # and convert network address to IP address format
    my $netaddress = dec2ip( ($ipaddress & $netmask) );
    
    print "Network address : $netaddress \n";


    # Calculate broadcase address by inverting the netmask
    # and do a logical or with network address
    my $broadcast = dec2ip( (($ipaddress & $netmask) + ( ~ $netmask )) );

    print "Broadcast address: $broadcast\n";


    ##########
    my $numhosts = ( $netmask ^ ip2dec("255.255.255.255") ) - 2;

    print "Number of hosts: $numhosts\n";
}


# this sub converts a decimal IP to a dotted IP
sub dec2ip ($) {
    join '.', unpack 'C4', pack 'N', shift;
}


# this sub converts a dotted IP to a decimal IP
sub ip2dec ($) {
   return ((unpack N => pack CCCC => split /\./ => shift) & 4294967295);
}

