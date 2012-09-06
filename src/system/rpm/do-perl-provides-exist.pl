#!/usr/bin/perl
# do-perl-provides-exist.pl - give it some RPMs and watch it go!

die "Usage: $0 RPM [..]\nChecks if perl provides in RPM exist on the current system.\n" unless @ARGV;

foreach my $rpm (@ARGV) {
	my ($countprovides,$totalprovides,@PROVIDES);
	$totalprovides = @PROVIDES = grep(/^.+$/, map { $_ = (/^perl\((.+?)\)/ ? $1 : "") } `rpm -q --provides -p "$rpm" 2>/dev/null`);
	foreach my $provide (@PROVIDES) {
		$@='';
		$foo = eval "require $provide; return($provide"."::VERSION)";
		print "foo: --$version-- \$\@ --$@--\n";
		if ( "--$@--" ne "----" ) {
			print "Package $rpm missing provide $provide\n";
			$countprovides++;
		}
	}
	if ( defined $countprovides ) {
		print "Package $rpm: missing $countprovides of $totalprovides provides\n";
	}
}

	
