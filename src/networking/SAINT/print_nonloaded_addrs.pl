#!/usr/bin/perl

use strict;
$|=1;

if ( @ARGV < 1 ) {
    die "Usage: $0 CSV_FILE\n\nPrints out IPs in CSV_FILE which match lines in groups/no_loaded_nets_ips.list\n";
}

my %all_ips = map { chomp; $_ => 1 } `csvcut.pl -n IPAddresses -r -f $ARGV[0]  | tail -n +2 | grep -e "\." | sort -u`;

my %loaded_ips = map { chomp; $_ => 1 } `cat groups/no_loaded_nets_ips.list`;

for ( keys %all_ips ) {
    if ( exists $loaded_ips{$_} ) {
        print "found loaded ip $_\n";
    }
}

