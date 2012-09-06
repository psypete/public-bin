#!/usr/bin/perl
# csvgrep.pl - Greps a CSV's rows with a regex on particular field names or column numbers and returns the result

use strict;
use warnings;

use Getopt::Long;
use Text::CSV_XS;

my (@opt_columns, @column_names, $rq, $file, $invert, $REGEX);

# Parse options

GetOptions(
    "column=i@" => \@opt_columns,
    "remove-quotes" => \$rq,
    "name=s@" => \@column_names,
    "file=s" => \$file,
    "invert-match|v" => \$invert
) or die "Failed parsing options\n";

die "Usage: cat CSV_FILE | csvcut.pl [--file FILE] [--remove-quotes] --column=#|--name=NAME [..] REGEX\n" if ((int(@opt_columns) == 0 and int(@column_names) == 0) or !@ARGV);


# Initialize variables

$REGEX = shift @ARGV;

@opt_columns = map { $_-1 } @opt_columns; # convert 1-based to 0-based

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



# Process the CSV

my @nrow;
while (my $row = $csv->getline($stdin)) {
    @nrow = ();

    # If we got --column or --names was already resolved
    if ( @opt_columns ) {

        foreach my $optcol (@opt_columns) {
            #if ( exists $row->[$optcol] and $row->[$optcol] =~ /$REGEX/ ) {
            if ( exists $row->[$optcol] and 
                ( 
                    ( $invert and $row->[$optcol] !~ /$REGEX/ ) or
                    ( ! $invert and $row->[$optcol] =~ /$REGEX/ )
                )
            ) {

                @nrow = @$row;
                last;
            }
        }

        #@nrow = map { exists $row->[$_] ? $row->[$_] : () } @opt_columns;

    # If we didn't get --column and we did get --names and we didn't resolve it to @colnames yet
    } elsif ( @column_names and ! @colnames ) {
        @colnames = @$row;

        # Push the column numbers we want to grep to @opt_columns
        foreach my $name (@column_names) {
            for (my $i=0; $i<@colnames; $i++ ) {
                if ( $name eq $colnames[$i] ) {
                    push( @opt_columns, $i );
                }
            }
        }

        @nrow = @$row;

    }

    #= @{$row}[@opt_columns];
    if ( @nrow and (!defined $invert or $invert < 1) ) {
        #print STDERR "nrow \"@nrow\" num " . int(@nrow) . "\n";

        printrow();

    } elsif ( defined $invert and $invert > 0 ) {

        printrow();
    }
}

sub printrow {

    #print "hey hey (@nrow)\n";

    if ( defined $rq and $rq > 0 ) {
        print join(",", @nrow), "\n";
    } elsif ( @nrow ) {
        $csv->print($stdout, \@nrow);
        print "\n";
    }
}

