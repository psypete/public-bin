#!/usr/bin/perl -w

$|=1;
use strict;
use Fcntl;
use Text::CSV;
use Data::Dumper;

# Each is a hash aref with:
#   *'column' - name or number of column
#   * 'function' (to call with: csv hash, row number, column number, column data)
my @COL_HANDLERS = (
    { 'column' => 'Sys_Admin', 'function' => sub { return [ split(/\//, $_[3]) ] } } ,
    { 'column' => 'Comments', 'function' => sub { return [ split(/\r/, $_[3]) ] } } ,
    { 'column' => 'IPAddresses', 'function' => sub { return [ split(/\s+/, $_[3]) ] } }
);

my $VERBOSE = exists $ENV{VERBOSE} ? $ENV{VERBOSE} : 0;


# Do everything and exit
exit main();


##############################################################################
##############################################################################


sub main {
    die "Usage: $0 SERVER_CSV_FILE NAME_MAPPING\n" unless @ARGV == 2;
    process_csv($ARGV[0], $ARGV[1]);
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
    my $csv = Text::CSV->new( { binary => 1 } ) or die "Cannot make CSV: $!";

    if ( !defined $filename ) {
        die "Error: no filename specified to write_csv";
    }

    # First collect field names
    my (%fields, @fields);
    foreach my $row ( @$rows ) {
        map { $fields{$_}++ } keys %$row;
    }

    @fields = sort { $a cmp $b } keys %fields;

    my $file_exist = -e $filename;
    # Now write to the file
    #open(my $fh, "+<$filename") || die "Error: cannot open $filename for writing: $!";
    my $flags = $file_exist ? O_RDWR|O_TRUNC|O_EXCL : O_RDWR|O_CREAT|O_EXCL;
    sysopen(my $fh, $filename, $flags) || die "Error: cannot open $filename for writing: $!";
    seek($fh, 0, 2);

    # Don't print out the fields if the file existed
    if ( ! $file_exist ) {
        $csv->print($fh, \@fields);
        print $fh "\n";
    }

    for ( my $i=0; $i<@$rows; $i++ ) {
        my @vals = map { exists $rows->[$i]->{$_} ? join("\r", @{$rows->[$i]->{$_}}) : "" } @fields;
        $csv->print($fh, \@vals);
        print $fh "\n";
    }

    close($fh);

}


# Do postprocessing on the csv data
sub post_process_csv {
    my $o = shift;

    # Step 1. clean up fields
    #   * take Sys_Admin column, replace 'name/name' with full names
    #   * in the Comments column separate entries by '\r'

    clean_up_columns($o);

    print "Sysadmin data:\n";
    #print Dumper($o->{'sysadmins'});
    mkdir "sysadmins";

    my %groups;
    for my $group (glob("groups/*.txt")) {
        map { chomp; uc($_) => $group } `cat $group`;
    }

    foreach my $admin ( keys %{ $o->{'sysadmins'} } ) {
        my $nadmin = $admin;
        $nadmin =~ s/\s/_/g;

        print "Writing $nadmin.csv\n";

        write_csv( $o->{'sysadmins'}->{$admin}, "sysadmins/$nadmin.csv" );
    }

    print "Building servers:\n";
    #print Dumper($o->{'building'});
    mkdir "building";

    foreach my $building ( keys %{ $o->{'building'} } ) {
        my $nbuilding = $building;
        $nbuilding =~ s/\s/_/g;
        print "Writing $nbuilding.csv\n";
        write_csv( $o->{'building'}->{$building}, "building/$nbuilding.csv");
    }

    write_csv( $o->{'fixed_csv'}  , "fixed_classe_data.csv" );
}


# Open CSV, go row by row, add rows to a new data structure.
# All columns are turned into arrays themselves and handlers are called for the
# appropriate column numbers.
# Then call postprocessing routines.
sub process_csv {
    my $file = shift;
    my $mapping_file = shift;
    my %o;

    $o{'fix_sysadmin_names'} = { map { chomp; $_ } map { split(/=/,$_,2) } `cat $mapping_file` };

    my $csvh = load_csv_file($file);

    for ( my $rownum=0 ; $rownum< @{$csvh->{'rows'}} ; $rownum++ ) {
        # This makes the row an anonymous array, with each column also an anonymous array.
        # Columns that are defined but the column text is zero bytes will be empty.
        my $row = [ map { [ length $_ ? $_ : () ] } @{ $csvh->{'rows'}->[$rownum] } ];

        foreach my $handler ( @COL_HANDLERS ) {
            my ($col, $func) = ( $handler->{'column'}, $handler->{'function'} );
            my $colnum;
            
            if ( $col =~ /^\d$/ ) {
                $colnum = $col;
            } else {
                $colnum = $csvh->{'headers'}->{$col};
            }

            $row->[$colnum] = &$func( $csvh, $rownum, $colnum, $csvh->{'rows'}->[$rownum]->[$colnum] );
            if ( ref $row->[$colnum] ne "ARRAY" ) {
                print STDERR "$0: Error: row column $colnum is not an array reference\n";
            }
        }

        push( @{$o{'rows'}}, $row );
    }

    $o{'headers'} = $csvh->{'headers'};
    $o{'revheaders'} = $csvh->{'revheaders'};

    post_process_csv(\%o);

    return \%o;
}


# read CSV file
# returns a hash which contains the column names and the rows
sub load_csv_file {
    my (@rows, @headers, %h);
    my $csv = Text::CSV->new( {binary => 1} ) || die "Error: no csv obj: $!";
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
    my $sysadmin_col = $o->{'headers'}->{'Sys_Admin'};
    my %fix_sysadmin_names = %{ $o->{'fix_sysadmin_names'} };
    my @serv_cols = qw(OS Cluster ServerName Rack Comments ServerType Comments_2 BuildingFloor IPAddresses TargetRack);
    #my @serv_cols = qw(ServerName ServerType Cluster Status BuildingFloor OS ServicePackPatchLevel Sys_Admin IPAddresses MACAddress ManufacturerName ModelNumber SerialNumber FunctionPurpose AppVersion Comments EndofSupportLife ANTIVirusProtection BackupVal HardwareSupportCostannually ContractNumber ContractTerms VendorName VendorAddress VendorPhone VendorContact DateServerwasinstalled Comments_2 LastUpdate UserID MoveFromGSB MoveGroup Rack SunsetDate PointofContact ITGAssetTag TargetRack);

    # Rules:
    # 1. if only one word, assume last name or full entry ('Willis', 'Desktop')
    # 2. New names are separated by '/'
    # 3. Each new name is either a last name, or if there are spaces between words, a full name

    # Extract all names, short and full
    my @names = map { s/^[^a-zA-Z0-9]+?//g; $_ } map { @{ $_->[ $o->{'headers'}->{'Sys_Admin'} ] } } @{$o->{'rows'}};
    my @fullnames = map { s/(\w+)/ucfirst($1)/eg; $_ } grep(/\s+/, @names);
    my %lastnames = map { uc( (split(/\s+/, $_, 2))[1] ) => $_  } @fullnames;

    # Replace last names with full names
    for ( my $i=0; $i < @{ $o->{'rows'} }; $i++ ) {
        my $r = $o->{'rows'}->[$i];
        my $rnum = @$r - 1;

        # Replaces any Sys_Admin column entry with the value from $lastnames{ uc($columnvalue) }
        $r->[$sysadmin_col] = [ map { s/^[^a-zA-Z0-9]+?//g; exists $fix_sysadmin_names{$_} ? $fix_sysadmin_names{$_} : $_ } map { exists $lastnames{ uc($_) } ? $lastnames{ uc($_) } : $_ } @{$r->[$sysadmin_col]} ];

        #$o->{'servers'} = [] if (!exists $o->{'servers'});
        #$o->{'servers'}->[$i] = {} if (!exists $o->{'servers'}->[$i]);

        # Populate useful server data in internal data structure
        map { $o->{'servers'}->[$i]->{ $_ } = $r->[ $o->{'headers'}->{ $_ } ] } @serv_cols;

        # Make an index of servers assigned to sysadmins
        foreach my $sysadmin ( @{ $r->[$sysadmin_col] } ) {
            push( @{$o->{'sysadmins'}->{ $sysadmin } }, $o->{'servers'}->[$i] );
        }

        # Make an index of servers in building floors
        push(
            @{
                $o->{'building'}->{
                    $r->[ $o->{'headers'}->{'BuildingFloor'} ]->[0]
                }
            }, $o->{'servers'}->[$i]
        );

        # Put the whole CSV, post-processed, into this array
        #print "r: " . Dumper($r);
        #print "revheaders: " . Dumper($o->{'revheaders'});

        push( 
            @{$o->{'fixed_csv'}},
            { 
                map {
                    $o->{'revheaders'}->[$_] => $r->[$_] 
                } (0..$rnum)
            } 
        );

    }


}

