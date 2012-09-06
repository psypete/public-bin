#!/usr/bin/perl

my $leases = "/var/lib/dhcp/dhcpd.leases";
my @cmds;

sub mogrify_leases {

	my $file = shift;
	my $COMMANDS = shift;
	my $curlease;
	my %leases;

	open(FILE, "<$file") || die "Error: couldn't open \"$file\": $!\n";

	while ( $line = <FILE> ) {
		chomp $line;
		my $print = 1;

		# found a new lease
		if ( $line =~ /^lease\s+(\S*)\s+\{$/ ) {
			$curlease = $1;
		}

		for ( my $l=0; $l<@$COMMANDS; $l++ ) {
			if ( $$COMMANDS[$l][0] =~ /^del/i and $$COMMANDS[$l][1] eq $curlease ) {
				$print = 0;
				last;
			}
		}

		if ( $print == 1 ) {
			print $line . "\n";
		}

		if ( $line =~ /^}$/ ) {
			undef $curlease;
		}

	}

	close(FILE);

}

if ( @ARGV < 1 or $ARGV[0] =~ /^-?-h/ ) {

	print STDERR "Usage: $0 COMMAND [OPTIONS]\n Commands:\n   del[ete] IP\t\tdelete a lease IP\n";
	exit(1);

}

for (my $i=0; $i<@ARGV; $i++) {
	if ( $ARGV[$i] =~ /^del/ and exists $ARGV[$i+1] and $ARGV[$i+1] =~ /\d+\.\d+\.\d+\.\d+/ ) {
		push( @cmds, [ "del", $ARGV[++$i] ] );
	}
}

mogrify_leases( $leases, \@cmds );

