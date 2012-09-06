#!/usr/bin/perl

use strict;
use Text::CSV;
use Data::Dumper;

die "Usage: $0 CSV_FILE NON_LOADED_IPS_FILE\n\nPrints the lines from CSV_FILE whose IPAddresses field entries are not in file NON_LOADED_IPS_FILE\n" unless @ARGV == 2;


#open(my $stdin, ">-") || die;

my $csv = Text::CSV->new({binary=>1});
open my $fh, $ARGV[0] || die "open: $!";
$csv->column_names( @{$csv->getline($fh)} );
my @cn = $csv->column_names;
#$csv->eol("\r\n");
$csv->eol("\n");

my %ips = map { chomp; $_ => 1 } `cat $ARGV[1]`;

while ( <$fh> ) {
    s/(\r|\n)//g;
    $_ .= "\n";
    $csv->parse($_);
    my @f = $csv->fields();
    #print "Line here\n";
    do_row($csv, { map { $cn[$_] => $f[$_] } (0..$#cn) }, \@f );
}
close $fh;

exit(0);


sub do_row {
    my $csv = shift;
    my $h = shift;
    my $a = shift;

    if ( exists $h->{IPAddresses} 
        and $h->{IPAddresses} =~ /(\d+\.\d+\.\d+\.\d+)/
    ) {

        if ( exists $ips{$1} ) {
            #print "Found ip $1 ; skipping line\n";
            return;
        } else {
            #print "Did not find ip $1\n";
            #print "$1\n";
        }
    }

    #$csv->print($stdin, $a);
    $csv->print(*STDOUT, $a);
}

