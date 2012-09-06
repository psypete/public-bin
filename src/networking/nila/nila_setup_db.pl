#!/usr/bin/perl -w
# nila_setup_db.pl v0.1 - set up nila database
# Copyright (C) 2011-2012 Peter Willis <peterwwillis@yahoo.com>
#

use strict;
use DBI;

if ( @ARGV != 4 ) {
    die "Usage: $0 HOST PORT USER PASSWORD\n\nThis script will connect to your database server and create the nila database and tables. If they already exist it will verify they are set up correctly or die with an error.\n";
}


my $HOST = $ARGV[0];
my $DB_PORT = $ARGV[1];
my $USER = $ARGV[2];
my $PASSWORD = $ARGV[3];

my $DSN = "DBI:mysql:host=$HOST;port=$DB_PORT";
my $DATABASE = "nila";


main();
exit(0);


sub main {

    my $rc;

    my $DB = DBI->connect($DSN, $USER, $PASSWORD);
    make_database($DB) || die "Error: database creation failed";
    $DB->disconnect;

    # Reconnect with created database
    $DB = DBI->connect("$DSN;database=$DATABASE", $USER, $PASSWORD);
    make_table($DB) || die "Error: table creation failed";
    $DB->disconnect;

    print "Database '$DATABASE' is properly set up on $HOST:$DB_PORT\n";
}

sub make_database {
    my $DB = shift;
    my $arrays = $DB->selectall_arrayref("SHOW DATABASES", { RaiseError => 0 } );
    if ( ! grep(/^$DATABASE$/i, map { @$_ } @$arrays) ) {
        print "No '$DATABASE' database found; creating it...\n";
        $DB->func("createdb", $DATABASE, 'admin') || dberror($DB);
    }

    return 1;
}

sub dberror {
    die "Error: " . $_[0]->errstr;
}


sub make_table {
    my $DB = shift;
    my @Hosts = (
        # for now 'name' will be unique. i don't want it to be, but for updating host information
        # it just seems necessary... i want people to be able to update 'ip' for 'name=blahblah',
        # and i don't know how to do that exactly if there's a duplicate 'name' (other than erroring
        # out and prompting them to specify the nila_hosts_id)
        [ 'name', 'varchar(255)', 'no', '', undef, '' ],
        [ 'fqdn', 'blob', 'yes', '', undef, '' ],
        [ 'lan', 'varchar(255)', 'yes', '', undef, '' ],
        [ 'os', 'varchar(255)', 'yes', '', undef, '' ],
        [ 'conftag', 'varchar(255)', 'yes', '', undef, '' ],
        [ 'serial', 'varchar(255)', 'yes', '', undef, '' ],
        [ 'mac', 'varchar(255)', 'yes', '', undef, '' ],
        [ 'ip', 'blob', 'yes', '', undef, '' ],
        [ 'vlan', 'int(11)', 'yes', '', undef, '' ],
        [ 'offline', 'int(11)', 'no', '', undef, '' ],
        [ 'nila_hosts_id', 'bigint(20) unsigned', 'no', 'pri', undef, 'auto_increment' ]
    );

    my $Hosts_table = "CREATE TABLE Hosts (\n";
    for ( my $i=0; $i<@Hosts; $i++ ) {
        $_=$Hosts[$i];
        $Hosts_table .= "\t$_->[0] $_->[1] ";
        $Hosts_table .= "NOT NULL " if (lc $_->[2] eq "no");
        $Hosts_table .= "PRIMARY KEY " if (lc $_->[3] eq "pri");
        $Hosts_table .= "AUTO_INCREMENT " if (lc $_->[5] eq "auto_increment");
        $Hosts_table .= ",\n" unless ($i == $#Hosts);
    }
    $Hosts_table .= ")\n";

    my $tables = $DB->selectall_arrayref("SHOW TABLES", { RaiseError => 0 } );
    if ( ! grep(/^Hosts$/i, map { @$_ } @$tables) ) {
        print "No 'Hosts' table found; creating it...\n";
        my $rc = $DB->do($Hosts_table, { RaiseError => 0 } );
        if ( !defined $rc and $rc ne "0E0" ) { # if no rows affected, returns "0E0"
            print "rc: \"$rc\"\n";
            dberror($DB);
        }
    }

    # Verify table is built properly
    my $describe = $DB->selectall_arrayref("DESCRIBE Hosts", { RaiseError => 0} );
    dberror($DB) unless (@$describe);

    my %foundall = map { $_->[0] => 1 } @Hosts;

    for ( my $i=0; $i<@$describe; $i++ ) {
        my $col = $describe->[$i];
        #my $o_col = $Hosts[$i];

        for ( my $j=0; $j<@Hosts; $j++ ) {
            # Find a matching 'name' entry, then compare the rest of the entries for that column
            if ( $Hosts[$j]->[0] eq $col->[0] ) {
                my $o_col = $Hosts[$j];

                for ( my $k=1; $k<6; $k++ ) { # there's only 6 entries in the array
                    next if ($k == 4); # this entry is always undef, it seems, for MySQL anyway

                    if ( lc $col->[$k] ne lc $o_col->[$k] ) {
                        die "Error: Hosts table: existing column #$i:$k ($col->[$k]) does not match our column #$i:$k ($o_col->[$k])\n";
                    }
                }

                delete $foundall{$o_col->[0]};
            }
        }
    }

    if ( keys %foundall > 0 ) {
        die "Error: missing the following columns from Hosts table: " . join(" ", keys %foundall) . "\n";
    }

    return 1;
}

