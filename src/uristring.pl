#!/usr/bin/perl
use URI::Escape;
if ( ! @ARGV ) {
	die "Usage: $0 encode|decode URI ...\n";
}
my $cmd = shift @ARGV;
	foreach my $arg (@ARGV) {
	if ( $cmd eq "encode" ) {
		print uri_escape($arg) . "\n";;
	} elsif ( $cmd eq "decode"  ){
		print uri_unescape($arg) . "\n";
	}
}

