#!/usr/bin/perl

use DB_File;
use Data::Dumper;

my %OPTIONS;

for ( @ARGV ) {
    if ( /^-h/ or /^--help/ ) {
        die "Usage: $0 SYSTEM|PATH [..]\nIndexes and reports on files, either specifically everything on this system or anything in the path you specify.\n";
    } elsif ( /^system$/i ) {
        $OPTIONS{SYSTEM}++;
    } else {
        $OPTIONS{PATHS}
    }
}

process_paths();
exit(0);


sub process_system {
    


# This subroutine gets filesystems which are mounted to some local device
# (we assume anything starting with a '/' is a local path) and saves their
# device number so later we can compare searched files to files with a
# local device number, so we don't process network-mounted files etc.
sub getdevices {
    my %devices;
    open(MOUNTS, "/proc/mounts") || die "Error: no /proc/mounts?";
    while ( <MOUNTS> ) {
        if ( /^\/[\S]+\s+([\S]+)/ ) {
            $devices{$1} = (stat($1))[0];
        }
    }
    close(MOUNTS);
    return(\%devices);
}

