#!/usr/bin/perl
# remove_duplicate_songs.pl - prompts to delete similar songs by title
# Copyright (C) 2009 Peter Willis <peterwwillis@yahoo.com>
# 
# The idea is simple: list a bunch of files, strip it down to
# the most likely "title" of the file (as if it were a song name),
# sort them by size and delete all but the biggest file.
# End result should be trimming duplicate songs and leaving the
# (hopefully) best quality file behind.
#
# TODO: implement ID3 song title support, but probably not necessary

if ( ! @ARGV ) {
    die "Usage: $0 DIRECTORY [..]\n";
}

foreach my $dir (@ARGV) {
    next unless -d $dir;

    my @files = map { chomp $_; $_ } `find "$dir" -type f`;
    my $report = find_similar_files(\@files);

    foreach my $words ( keys %$report ) {
        my $ar = $report->{$words};
        if ( @$ar > 1 ) {
            print "Multiple files matched words \"$words\":\n";
            my @files = sort { $b->[0] <=> $a->[0] } @$ar;
            my $leave = shift @files; # leave the biggest
            print map { "        (" . $_->[0] . ") " . $_->[1] . "\n" } @files;
            print "I will keep \"$leave->[1]\" ($leave->[0]).\nDelete the previous songs? [y/N] ";
            my $answer = <STDIN>;
            chomp $answer;
            if ( $answer =~ /y/i ) {
                for (@files) {
                    print "    Unlinking \"$_->[1]\"\n";
                    unlink($_->[1]) || die "Error: could not unlink: $!\n";
                }
            }
            print "\n";
        }
    }
}

sub find_similar_files {
    my $fl = shift;
    my %files;
    for ( my $i = 0 ; $i < @$fl; $i++ ) {

        my $words;
        $_ = $fl->[$i];
        s/(\w)-(\w)/$1 $2/g;
        s/^.*[-\/]([^-\/].+)$/$1/ig;
        s/_/ /g;
        s/^\s+//g;
        s/\.\w+$//;
        s/[',]//g;
        while ( /(\w+)/g ) {
            $words .= " $1";
        }
        $words =~ s/^\s+//g;

        push @{ $files{ lc $words } }, [ -s $fl->[$i], $fl->[$i] ];
    }

    return \%files;
}

