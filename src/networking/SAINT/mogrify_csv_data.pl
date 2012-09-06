#!/usr/bin/perl -w

$|=1;
use strict;
use Fcntl;
use Text::CSV_XS;
use Data::Dumper;

# Each is a hash aref with:
#   * 'column' - name or number of column
#   * 'function' (to call with: csv hash, row number, column number, column data)

my $VERBOSE = exists $ENV{VERBOSE} ? $ENV{VERBOSE} : 0;
my %GLOBAL;

# Do everything and exit
exit main();


##############################################################################
##############################################################################


sub main {
    die "Usage: $0 SERVER_CSV_FILE NAME_MAPPING\n" unless @ARGV == 2;

    # The map of names to fix Sys_Admin later
    $GLOBAL{'sysadmin_name_map'} = { map { chomp; $_ } map { split(/=/,$_,2) } `cat $ARGV[1]` };

    my $csvh = load_csv_file( $ARGV[0] );

    my @PROCESS_COL_HANDLERS = (
        { 'column' => 'Sys_Admin', 'function' => \&sysadmin_preprocess_handler } ,
        { 'column' => 'Comments', 'function' => sub { return [ split(/\r/, $_[3]) ] } } ,
        { 'column' => 'IPAddresses', 'function' => sub { return [ split(/\s+/, $_[3]) ] } }
    );

    process_csv( $csvh, \@PROCESS_COL_HANDLERS );

    # Now do some more processing of all the Sys_Admin names
    my %sysad_lastnames;
    my $sysad_col = $csvh->{'headers'}->{'Sys_Admin'};
    my @names =  map {  @{ $_->[$sysad_col] }  } @{$csvh->{'rows'}};

    # Makes @fullnames by using only names with spaces and converts the first character to uppercase
    my @fullnames = map {
        s/(\w+)/ucfirst($1)/eg;
        $_ 
    } grep(
        /\s+/,
        map { 
            @{ $_->[$sysad_col] }
        } @{$csvh->{'rows'}}
    );

    # Makes an entry in %sysad_lastnames like ( 'PENTANGELI' => 'Frank Pentangeli' )
    map {
        $sysad_lastnames{ uc (
            (split(/\s+/, $_, 2))[1]
        ) } = $_
    } @fullnames;

    # Finish the last round of processing
    my @POST_PROCESS_COL_HANDLERS = (
        { 'column' => 'Sys_Admin', 'function' => \&sysadmin_postprocess_handler }
    );

    $csvh->{ '_sysad_lastnames' } = \%sysad_lastnames;
    process_csv($csvh, \@POST_PROCESS_COL_HANDLERS);

    post_process_csv($csvh);
}


# Do postprocessing on the csv data
sub post_process_csv {
    my $o = shift;

    clean_up_columns($o);
    write_csv( $o->{'fixed_csv'}  , "fixed_classe_data.csv" );
}


sub sysadmin_preprocess_handler {
    my ($o, $rownum, $colnum, $col) = @_;

    # Multiple names sometimes exist separated by a '/'
    my @names = map {
        s/^[^a-zA-Z0-9]+?//g;
        s/[^a-zA-Z0-9]+$//g;
        $_
    } split(/\//, $col);

    my $foo = [ @names ];

    #print "returning: $foo\n";

    return $foo;
}


sub sysadmin_postprocess_handler {
    my ($o, $rownum, $colnum, $col) = @_;

    if ( !defined $col or length($col) < 1 ) {
        print "Col undefined; skipping\n";
        return;
    } elsif ( ref($col) ne "ARRAY" ) {
        print "Col is $col; skipping\n";
        return;
    }

    my @col = map {
        s/^[^a-zA-Z0-9]+?//g;
        # Fixes last or full names from the map file
        if ( exists $GLOBAL{'sysadmin_name_map'}->{$_} ) {
            $GLOBAL{'sysadmin_name_map'}->{$_}
        } else {
            $_
        }
    } map {
        # Expands uppercase last name into full name
        if ( exists $o->{'_sysad_lastnames'}->{ uc($_) } ) {
            $o->{'_sysad_lastnames'}->{ uc($_) }
        } else {
            $_
        }
    } @$col;

    return [ @col ];
}


# $row = [
    # One line
    #{ key=[value], key=[value], key=[value] },
    # Second line
    #{ key=[value], key=[value] }
# ]

# Write a csv based on rows of an index from the internal data structure $o
sub write_csv {
    my $rows = shift;
    my $filename = shift;
    my $csv = Text::CSV_XS->new( { binary => 1 } ) or die "Cannot make CSV: $!";

    if ( !defined $filename ) {
        die "Error: no filename specified to write_csv";
    }

    # First collect field names
    my (%fields, @fields);
    foreach my $row ( @$rows ) {
        map { $fields{$_}++ } keys %$row;
    }

    @fields = sort { $a cmp $b } keys %fields;

    #my $file_exist = -e $filename;
    # Now write to the file
    #open(my $fh, "+<$filename") || die "Error: cannot open $filename for writing: $!";
    #my $flags = $file_exist ? O_RDWR|O_TRUNC|O_EXCL : O_RDWR|O_CREAT|O_EXCL;
    #sysopen(my $fh, $filename, $flags) || die "Error: cannot open $filename for writing: $!";
    #seek($fh, 0, 2);

    open(my $fh, ">$filename") || die "Error: cannot open $filename for writing: $!";

    # Don't print out the fields if the file existed
    #if ( ! $file_exist ) {
        $csv->print($fh, \@fields);
        print $fh "\n";
    #}

    for ( my $i=0; $i<@$rows; $i++ ) {
        #print "row " . Dumper($rows->[$i]);
        my @vals = map {
            if ( exists $rows->[$i]->{$_} and ref($rows->[$i]->{$_}) eq "ARRAY" ) {
                join( "\r", @{$rows->[$i]->{$_}} )
            } elsif ( exists $rows->[$i]->{$_} and ! ref($rows->[$i]->{$_}) ) {
                $rows->[$i]->{$_}
            } else {
                ""
            }
        } @fields;
        $csv->print($fh, \@vals);
        print $fh "\n";
    }

    close($fh);

}


# Open CSV, go row by row, add rows to a new data structure.
# All columns are turned into arrays themselves and handlers are called for the
# appropriate column numbers.
# Then call postprocessing routines.
sub process_csv {
    my $csvh = shift;
    my $handlers = shift;

    for ( my $rownum=0 ; $rownum< @{$csvh->{'rows'}} ; $rownum++ ) {
        my $row = [ map { [ length $_ ? $_ : () ] } @{ $csvh->{'rows'}->[$rownum] } ];

        foreach my $handler ( @$handlers ) {
            my ($col, $func) = ( $handler->{'column'}, $handler->{'function'} );
            my $colnum;
            
            # Look up the column to work on
            $colnum = ( $col =~ /^\d$/ ? $col : $csvh->{'headers'}->{$col} );
            # And replace the column with the handler function's output
            #$row->[$colnum] = &$func( $o, $csvh, $rownum, $colnum, $csvh->{'rows'}->[$rownum]->[$colnum] );
            $csvh->{'rows'}->[$rownum]->[$colnum] = &$func( $csvh, $rownum, $colnum, $csvh->{'rows'}->[$rownum]->[$colnum] );

            #if ( ref $row->[$colnum] ne "ARRAY" ) {
            if ( ref($csvh->{'rows'}->[$rownum]->[$colnum]) ne "ARRAY" ) {
                print STDERR "$0: Error: row column $colnum is not an array reference\n";
            }
        }

        #push( @{$o->{'rows'}}, $row );
    }

    #$o->{'headers'} = $csvh->{'headers'};
    #$o->{'revheaders'} = $csvh->{'revheaders'};

    #return $o;
    return $csvh;
}


# read CSV file
# returns a hash which contains the column names and the rows
sub load_csv_file {
    my (@rows, @headers, %h);
    my $csv = Text::CSV_XS->new( {binary => 1} ) || die "Error: no csv obj: $!";
    open(my $fd, shift) || die "Error: cant open csv: $!";

    while ( <$fd> ) {
        chomp;
        s/[^[:print:]]+//g;

        if ( $csv->parse($_) ) {
            if ( ! @headers ) {
                @headers = $csv->fields();
            } else {
                push(@rows, [ $csv->fields() ]);
            }
        } else {
            print STDERR "Error: could not parse line: $! $@\n";
        }
    }

    close($fd);


    my $c = 0;
    $h{'headers'} = { map { $_ => $c++ } @headers };
    $c = 0;
    $h{'revheaders'} = [ @headers ];
    $h{'rows'} = \@rows;

    print STDERR "headers " . Dumper( $h{'headers'} ) if $VERBOSE;
    return \%h;
}


# Handle Sys_Admin name here
sub clean_up_columns {
    my $o = shift;
    #my @serv_cols = qw(OS Cluster ServerName Rack Comments ServerType Comments_2 BuildingFloor IPAddresses TargetRack);

    for ( my $i=0; $i < @{ $o->{'rows'} }; $i++ ) {
        my $r = $o->{'rows'}->[$i];
        my $rnum = @$r - 1;

        # Put the whole CSV, post-processed, into this array
        #print "r: " . Dumper($r);
        #print "revheaders: " . Dumper($o->{'revheaders'});

        push( @{$o->{'fixed_csv'}}, { 
                map {
                    $o->{'revheaders'}->[$_] => $r->[$_] 
                } (0..$rnum)
            }
        );
    }

}

