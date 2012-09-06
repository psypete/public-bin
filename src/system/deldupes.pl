#!/usr/bin/perl
# deldupes.pl - delete duplicate files
# Copyright (C) 2010 Peter Willis <peterwwillis@yahoo.com>

$|=1;
use strict;

main();
exit(0);

sub main {
    my @dirs;
    my $DELETE = 0;

    for ( @ARGV ) {
        if ( $_ eq "-h" or $_ eq "--help" ) {
            usage();
        } elsif ( $_ eq "--delete" ) {
            $DELETE = 1;
        } elsif ( -d $_ ) {
            push @dirs, "\"$_\"";
        }
    }

    usage() unless @dirs;

    print STDERR "This may take a long time. Please wait...\n\n";

    my %sums;
    my $progress = 0;
    my @progress_a = qw( \ | / - \ | / - );
    my $progress_c = scalar @progress_a;
    open(my $pipe, "find @dirs -type f -exec md5sum {} \\\; |") || die "Error: cannot run find: $! ($@)\n";
    while ( <$pipe> ) {
        chomp $_;
        # For some reason, md5sum likes to prepend a '\' to some output
        s/^\\//g;
        if ( /^(\w+)\s+(.+)$/ ) {
            push @{ $sums{$1} }, $2;
        } else {
            print "Invalid md5sum \"$_\"\n";
        }
        print STDERR "Checking files " . $progress_a[ $progress++ % $progress_c ] . "\r";
    }

    delete_em(\%sums, $DELETE);

}

sub delete_em {
    my $href = shift;
    my $del = shift;
    my %delh;

    while ( my ($md5, $aref) = each %$href ) {
        if ( @$aref > 1 ) {
            my @tmp = @$aref;
            my $orig = shift @tmp;
            print "Original:  \"$orig\"\n";
            print "" . ($del ? "Deleting: ":"Duplicate: ") . (join " ", map { "\"$_\"" } @tmp) . "\n";
            unlink(@tmp) if $del;
            print "\n";
        }
    }
 }


sub usage {
    die "Usage: $0 [OPTIONS] DIRECTORY [..]\nOptions:\n  --delete\t\t\tActually delete the duplicates found\n";
}
