#!/usr/bin/perl
# csvcut.pl - Extracts parts of a CSV by field name or column number and prints out the result

use strict;
use warnings;

use Getopt::Long;
my (@opt_columns, @column_names, $rq, $file);

GetOptions(
    "column=i@" => \@opt_columns,
    "remove-quotes" => \$rq,
    "name=s@" => \@column_names,
    "file=s" => \$file
) or die "Failed parsing options\n";

die "Usage: cat CSV_FILE | csvcut.pl [--file FILE] [--remove-quotes] --column=#|--name=NAME [..]\n" if (int(@opt_columns) == 0 and int(@column_names) == 0);;

@opt_columns = map { $_-1 } @opt_columns; # convert 1-based to 0-based

use Text::CSV_XS;
my $csv = Text::CSV_XS->new ( { binary => 1 } );

my $stdin;
if ( defined $file and length $file ) {
    open($stdin, "<$file") or die "Couldn't open file $file: $!";
} else {
    open($stdin, "<-") or die "Couldn't open stdin\n";
}
open(my $stdout, ">-") or die "Couldn't open stdout\n";

my $count = 0;
my @colnames;

while (my $row = $csv->getline($stdin)) {
    my @nrow;

    # If we got --column or --names was already resolved
    if ( @opt_columns ) {
        @nrow = map { exists $row->[$_] ? $row->[$_] : () } @opt_columns;

    # If we didn't get --column and we did get --names and we didn't resolve it to @colnames yet
    } elsif ( @column_names and ! @colnames ) {
        @colnames = @$row;

        foreach my $name (@column_names) {
            for (my $i=0; $i<@colnames; $i++ ) {
                if ( $name eq $colnames[$i] ) {
                    push( @opt_columns, $i );
                }
            }
        }

        @nrow = map { exists $row->[$_] ? $row->[$_] : () } @opt_columns;

    }

    #= @{$row}[@opt_columns];
    if ( @nrow ) {
        #print STDERR "nrow \"@nrow\" num " . int(@nrow) . "\n";
        if ( defined $rq and $rq > 0 ) {
            print join(",", @nrow);
        } else {
            $csv->print($stdout, \@nrow);
        }
        print "\n";
    }
}
