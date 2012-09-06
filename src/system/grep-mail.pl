#!/usr/bin/perl
use strict;
die "Usage: $0 DIRECTORY MAILREGEX\n" unless @ARGV==2;
$|=1;
$ARGV[0] =~ s/\/$//g;
chdir($ARGV[0]) || die "Error: couldn't chdir to directory $ARGV[0] ($!)\n";
opendir(DIR,".") || die "Error: couldn't open current directory (wtf??)\n";
while (my $d=readdir(DIR)) {
	open(FILE,"<$d") || die "Error: couldn't open $d ($!)\n";
	while (my $s = <FILE>) {
		if ($s =~ /$ARGV[1]/) {
			print "$ARGV[0]/$d\t$s\n";
		}
	}
	close(FILE);
}
closedir(DIR);

