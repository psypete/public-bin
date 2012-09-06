#!/usr/bin/perl

use strict;
use Text::CSV;
use Data::Dumper;
$|=1;


my %global = { 'rows' => [], 'fields' => {} };

die "Usage: $0 CSV_FILE NEWPREFIX MAXROWS FIELD1 [FIELD2 ..]\n\nTakes in a CSV file and outputs it into multiple files starting with NEWPRIX, distributing up to MAXROWS evenly based on groups of FIELDs.\n" unless (@ARGV > 3 or grep(/^(-h|--help)$/,@ARGV));

my $FILE_IN = shift @ARGV;
my $NEW_PREFIX = shift @ARGV;
my $MAX = shift @ARGV;


open my $fh, $FILE_IN || die "open: $!";
open(my $stdin, ">-") || die;

my $csv = Text::CSV->new({binary=>1});
$csv->column_names( @{$csv->getline($fh)} );
my @cn = $csv->column_names;
#$csv->eol("\r\n");
$csv->eol("\n");


#%h = map { $_ } $csv->column_names;
while ( <$fh> ) {
    chomp;
    $csv->parse($_);
    my @f = $csv->fields();
    do_row($csv, { map { $cn[$_] => $f[$_] } (0..$#cn) }, \@f );
}
close $fh;


output_csv();


exit(0);

#######################################################################


# First sort the data into groups.
# 
# Primarily make groups for each set of rows that has a particular field name
# (BuildingName records, Row records, BuildingName and Row records, and
#  those that have none)
# 
# Then build lists based on a maximum number where we iterate over each
# group, picking one from each group until we've hit the max.


sub output_csv {

    my @fields = keys %{ $global{'fields'} };

    my %groups;

    my $num_rows = @{$global{'rows'}};

    for ( my $ri = 0; $ri < $num_rows; $ri++ ) {
        foreach my $field (@fields) {
            my $a = $global{'fields'}->{$field};
            if ( ! @$a ) {
                next;
            }
            my $row = shift @$a;
            push( @{ $groups{$field} } , $row );
            undef $row;
        }
    }

    # Start building lists of $MAX
    my @lists;
    my @tmplist;
    for ( my $count=0; $count<$num_rows; ) {

        my $listnum = $count % $MAX;

        # Pick the next group name
        my $group = $fields[ $count % @fields ];
        #print "group $group listnum $listnum\n";

        if ( @{ $groups{$group} } ) {

            if ( $listnum == 149 ) {
                push(@lists, [ @tmplist ] );
                #print "got to 149, making new list (@tmplist)\n";
                @tmplist = ();
            }

            my $row = shift @{$groups{$group}};
            push(@tmplist, $row);
            $count++;

        } else {
            delete $groups{$group};
            #print "deleted group $group\n";

            my $fn = @fields;
            my $fi = ($count % $fn);
            my $f = $fields[$fi];
            splice( @fields, $fi, 1 );
            #print "deleted field $f\n";
        }

    }

    # Get the last one
    if ( @tmplist ) {
        push(@lists, [ @tmplist ] );
        @tmplist = ();
    }

    for ( @lists ) {
        print "num: " . scalar @$_ . "\n";
    }

    write_lists( \@lists );

}

sub write_lists {
    my $lists = shift;

    for ( my $c=0; $c < @$lists; $c++ ) {
        
        my $fname = "$NEW_PREFIX.$c";
        open(my $fd, ">$fname") || die "Error: could not open $fname for writing: $!\n";

        map {
            $csv->print($fd, $_->{'row'});
        } @{$lists->[$c]};

        close($fd);

    }
}


sub do_row {
    my $csv = shift;
    my $h = shift;
    my $a = shift;

    push( @{ $global{'rows'} }, { 'row' => $a, 'hash' => $h } );
    my $rows = $global{'rows'};
    my $row_i = $#$rows;

    # Make groups based on matching @ARGV fields in order
    # 
    # (One group of 'BuildingName\000Rack' if both exist,
    #  one group of 'BuildingName' if Rack doesn't exist,
    #  one group of '\000' or '' if only Rack exists)

    my @fields;
    foreach my $n ( @ARGV ) {
        if ( ! exists $h->{$n} or $h->{$n} =~ /^\s*?$/ ) {
            #print "$n not exist in " . Dumper($h);
            last;
        }

        push(@fields, $h->{$n});
    }

    my $gn = join("\000", @fields);


    if ( !exists $global{'fields'}->{$gn} ) {
        $global{'fields'}->{$gn} = [];
    }
    my $ar = $global{'fields'}->{$gn};

    push( @$ar, $rows->[$row_i] );

}

