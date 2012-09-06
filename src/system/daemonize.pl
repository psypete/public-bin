#!/usr/bin/perl
$log=0;

use POSIX (setsid);

if ( ! @ARGV ) {
	die "Usage: $0 PROGRAM [ARGS]\n";
}

fork && exit;

if ( $log ) {
	open FILE, ">/tmp/$>.log.daemonize" || die "no log open: $!\n";
	close(STDIN);
	open STDOUT, ">&FILE";
	open STDERR, ">&FILE";
} else {
#	close(STDIN);
#	close(STDOUT);
#	close(STDERR);
}

setsid();

#exec @ARGV;

open(COMMAND, "|-", "@ARGV");
$|=1;
sleep 2;
print "cd test\n";
print "mkdir foo\n";
close(COMMAND);

