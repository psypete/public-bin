#!/usr/bin/perl
# findphonewords.pl - find words in phone numbers
# 
use strict;

my @args;
my $EXACT = 0;
my $dict = '/usr/share/dict/words';
my @words = (
    qr/./,
    qr/./,
    qr/[abc]/,
    qr/[def]/,
    qr/[ghi]/,
    qr/[jkl]/,
    qr/[mno]/,
    qr/[pqrs]/,
    qr/[tuv]/,
    qr/[wxyz]/
);

die "Usage: $0 [OPTIONS] NUMBERS\nOptions:\n  -e\t\tReturns words that exactly match the numbers\n  -w LIST\t\tAlternate wordlist to use\n" unless @ARGV;

for (my $i=0;$i<@ARGV;$i++) {
    $_=$ARGV[$i];
    if ( $_ eq "-e" ) {
        $EXACT = 1;
    } elsif ( $_ eq "-w" ) {
        $dict = $ARGV[++$i];
    } elsif ( /^\d+$/ ) {
        push @args, $_;
    }
}

for ( @args ) {
    findwords($_);
}

sub findwords {
    my $numbers = shift;
    my @numbers = split(//, $numbers);
    my $regex = "^";

    for ( @numbers ) {
        $regex .= $words[$_];
    }

    my %matches;
    open(DICT, "<$dict") || die "Error: could not open $dict ($!)\n";
    my $ownregex;
    while ( <DICT> ) {
        chomp;
        map { $matches{$_}++ } ( /($regex)/g );

        if ( ! $EXACT ) {
            foreach my $num ( 0..$#numbers ) {
                $ownregex = "^";
                map { $ownregex .= $words[$_] } @numbers[0..$num];
                #print "ownregex: $ownregex\n";
                map { $matches{$_}++ } ( /($ownregex)/g );
            }
            foreach my $num ( 0..$#numbers ) {
                $ownregex = "^";
                map { $ownregex .= $words[$_] } @numbers[$num..$#numbers];
                map { $matches{$_}++ } ( /($ownregex)/g );
            }
        }
    }
    close(DICT);

    print "word matches for $numbers: ", (join(", ", sort { length($b) <=> length($a) } keys %matches)), "\n";
}

