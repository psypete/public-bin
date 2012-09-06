#!/usr/bin/perl
# sortfiles.pl - auto-sort files into directory hirearchy by date
# Copyright (C) 2009 Peter Willis <peterwwillis@yahoo.com>
#
use strict;
use File::Copy;

if ( ! @ARGV ) {
    die "Usage: $0 DIRECTORY [..]\nAutomatically sorts files in DIRECTORY based on date.\nNOTE: This program is *not* recursive.\n";
}

foreach my $dir (@ARGV) {
    next unless -d $dir and -w $dir;
    sort_directory($dir);
}

sub sort_directory {
    my $d = shift;
    my %ds;
    print STDERR "Sorting files in directory \"$d\" ...\n";

    opendir(DIR, $d) || die "Error: could not open dir \"$d\": $!\n";

    foreach my $file (readdir(DIR)) {
        next unless ( $file !~ /^\.\.?$/ and -f "$d/$file" );

        if ( ! -w "$d/$file" ) {
            print STDERR "Error: cannot move file $d/$file: $!\n";
            next;
        }

        my @s = stat("$d/$file");
        my ($day, $mon, $yr) = (localtime($s[9]))[3,4,5];
        $day = sprintf("%0.2d", $day);
        $mon = sprintf("%0.2d", ++$mon);
        $yr += 1900;

        if ( !exists $ds{"$d/$yr/$mon/$day"} ) {
            mkdir("$d/$yr") if (! -d "$d/$yr");
            mkdir("$d/$yr/$mon") if (! -d "$d/$yr/$mon");
            if ( ! -d "$d/$yr/$mon/$day" ) {
                mkdir("$d/$yr/$mon/$day") || die "Error: bad mkdir($d/$yr/$mon/$day)\n";
            }
            $ds{"$d/$yr/$mon/$day"}++;
        }

        print "Moving $d/$file to $d/$yr/$mon/$day/$file\n";

        move("$d/$file", "$d/$yr/$mon/$day/$file");
    }

    closedir(DIR);
}

