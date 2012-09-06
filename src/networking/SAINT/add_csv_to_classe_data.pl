#!/usr/bin/perl
use strict;
use Text::CSV_XS;
use Data::Dumper;

die <<EOUSAGE unless @ARGV == 2;
Usage: $0 CLASSE_DATA_CSV ADDITIONAL_CSV_DATA

Concatenates the rows of CSV1 with CSV2, but rearranges CSV2's columns 
to be the same as CSV1. Result should be one uniform CSV based on CSV1's
column names.
EOUSAGE

my $csv1 = open_csv($ARGV[0]);

my %fields;
my @f1cols = $csv1->column_names;
for ( my $f1c=0; $f1c<@f1cols; $f1c++ ) {
    $fields{$f1c} = $f1cols[$f1c];
}

my $csv2 = open_csv($ARGV[1]);

# First print out the first CSV,

$csv1->print( \*STDOUT, [ $csv1->column_names ] );

my $csv1fh = $csv1->{'_my_fh_'};
#while ( my $row = $csv1->getline($csv1fh) ) {
while ( my $tmp = <$csv1fh> ) {
    $csv1->parse($tmp) || die "Error: could not parse \"$tmp\": $!";
    $csv1->print( \*STDOUT, [ $csv1->fields ] );
}

$csv1->eof or $csv1->error_diag();

# Then print out the second's data in the matching columns from the first

loop_over_csv($csv2, \&do_row);


#######################################################################
#######################################################################


sub open_csv {
    my $filename = shift;

    my $csv = Text::CSV_XS->new({binary=>1});
    open(my $fh, $filename) || die "open: $!";
    $csv->{'_my_fh_'} = $fh;
    $csv->{'_my_filename_'} = $filename;

    $csv->column_names( @{$csv->getline($fh)} );
    $csv->eol("\r\n");

    return $csv;
}

sub loop_over_csv {
    my $csv = shift;
    my $handler = shift;

    my $fh = $csv->{'_my_fh_'};

    my @cn = $csv->column_names;

    while ( <$fh> ) {
        s/(\r|\n)//g;
        $csv->parse($_);
        my @f = $csv->fields();
        &$handler($csv, { map { $cn[$_] => $f[$_] } (0..$#cn) }, \@f );
    }

}


#######################################################################
#######################################################################


sub do_row {
    my $csv = shift;
    my $h = shift;
    my $a = shift;
    my @name;

    my $_linec;
    my @line;
    for ( my $i=0; $i<@f1cols; $i++ ) {
        if ( exists $h->{ $fields{$i} } ) {
            push(@line, $h->{ $fields{$i} } );
        } else {
            push(@line, '');
        }
    }

    print join(",", @line) . "\n";
}

