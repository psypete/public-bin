#!/usr/bin/perl

if ( $ARGV[0] !~ /^(-d|-i)$/ or @ARGV < 2 ) {
    die "Usage: $0 OPT <ip> [..]\nOPT is either -d (output decimal) or -i (output ip)\n";
}

my $opt = shift @ARGV;

if ( $opt eq "-i" ) {
    print join("\n", map { dec2ip($_) } @ARGV), "\n";
} elsif ( $opt eq "-d" ) {
    print join("\n", map { ip2dec($_) } @ARGV), "\n";
}
 
# this sub converts a decimal IP to a dotted IP
sub dec2ip ($) {
    join '.', unpack 'C4', pack 'N', shift;
}
 
 
# this sub converts a dotted IP to a decimal IP
sub ip2dec ($) {
    unpack N => pack CCCC => split /\./ => shift;
}

