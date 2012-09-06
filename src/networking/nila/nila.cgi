#!/usr/bin/perl
# nila.cgi v0.1 - network inventory and lookup assistant CGI backend
# 
# Copyright (C) 2011-2012 Peter Willis <peterwwillis@yahoo.com>
#

$|=1;
use strict;
use DBI;
# Make sure you do NOT enable nph unless web server has it enabled too!
use CGI qw/:standard :push/;
use DB_File;
use Data::Dumper;
use MIME::Base64;


my $Q = new CGI;
my $DB;
my %STATE;
my %PARAM;
my $QUERY_SEPARATOR = "\000";
my $VERBOSE = 1;
my $DB_CONN = "DBI:mysql:host=127.0.0.1;port=3306;database=nila";
#my @DB_AUTH = ("root","Password1");
my @DB_AUTH = ();
my $DB_CREDS_FILE = "nila_db.creds";

my %TABLE_FIELDS = ( Hosts => [ qw(name fqdn lan os conftag serial mac ip vlan offline nila_hosts_id) ] );
my $HTTP_HEADER = { -connection => 'close' };


main();

exit(0);

sub myparam {
    return $PARAM{$_[0]}
}

sub main {

    my %obj;
    my ($op, $t);

    #if ( $Q->request_method() eq "POST" ) {
    #    %PARAM = map { $_ => $Q->url_param($_) } $Q->url_param();
    #} else {
        %PARAM = $Q->Vars();
    #}

    # ( operation => 'get|update', type => 'network', query-data_type=>"list|json", query-record_name="", query-args=>[] )
    if ( !defined myparam('op') or !defined myparam('t') ) {
        $HTTP_HEADER->{'-status'} = "400";
        html_error("op and t must be supplied (have: " . join(";",map{"$_=$PARAM{$_}"}keys %PARAM) . ")");
    }

    my $obj = prep_operations();

    # if requested type was text/csv, return a csv with header:
    # operation-number, result, description
    
    # since we can have multiple objects all with different data types, we use
    # multipart messages to deliver each separate object and leave it up to the
    # client to summarize them
    
    print multipart_init() if ( @$obj > 1 );

    my $ok = 0;
    my $opnum = 1;
    foreach my $op ( @$obj ) {
        my $ret;

        print STDERR "o $op->{op} " . Dumper($op) if ($VERBOSE);

        if ( lc $op->{'op'} eq "get" ) {
            $ret = do_get_operation($op);
        } elsif ( lc $op->{'op'} eq "update" ) {
            $ret = do_update_operation($op);
        } elsif ( lc $op->{'op'} eq "delete" ) {
            $ret = do_delete_operation($op);
        } else {
            $HTTP_HEADER->{'-status'} = "501";
            html_error("'op' should be get, update or delete");
        }

        # print status of operation.
        # if csv content_type, print out a csv record

        if ( ref($ret) eq "HASH" ) { # this should probably be an object at some point
            #html_print( $op, join("\n", @$ret), "\n" );
            
            print multipart_start( -type => $op->{'content_type'} ) if ( @$obj > 1 );

            if ( $op->{'data_type'} eq "csv" ) {
                html_print( format_list( $op, $op->{'data'} ) );
            }

            print multipart_end if ( @$obj > 1 );

            $ok++;

        } elsif ( defined $ret ) {

            print multipart_start( -type => $op->{'content_type'} ) if ( @$obj > 1 );
            html_print( $op, $ret );
            print multipart_end if ( @$obj > 1 );

            $ok++;

        }

        $opnum++;
    }

    print multipart_final if ( @$obj > 1 );

    exit(0) if $ok;

    # if we didn't already print and exit, print a default page
    $HTTP_HEADER->{'-status'} = "400";
    html_print("your request could not be processed\n");
}

sub prep_operations {
    my %o = ( op => myparam('op'), type => myparam('t'), data_type => "csv", content_type => "text/plain" );
    my @ops;
    my @values = param("q-query");

    #foreach my $rec_nam ( myparam("q-query") ) {
    foreach my $rec_nam ( @values ) {
        my %copy_o = %o;

        $rec_nam =~ s/^base64:(.+)$/decode_base64($1)/eg;

        print STDERR "rec_nam $rec_nam\n";

        # note that we're already looping over q-query with the expectation that each
        # separate query will be a different q-query
        my $qq = parse_csv( [ join(",", split(/$QUERY_SEPARATOR/, $rec_nam)) ] );

        $copy_o{'query'} = $qq->[0];
        $copy_o{'record'} = myparam('q-rec') if ( defined myparam("q-rec") );
        $copy_o{'data_type'} = myparam("q-dt") if ( defined myparam("q-dt") );
        $copy_o{'args'} = [ param("q-args") ] if ( param("q-args") );

        # If they didn't specify a record to get, get anything that matches the query
        if ( !exists $copy_o{'record'} ) {
            $copy_o{'record'} = "*";
        }

        my @accept = $Q->Accept();

        if ( grep(/^text\/csv$/, @accept) ) {
            $copy_o{'data_type'} = "csv";
            $copy_o{'content_type'} = "text/csv";
        }

        push @ops, \%copy_o;
    }

    return ( \@ops );
}

sub do_update_operation {
    my $o = shift;
    my $ans;

    if ( ! authenticate_update($o) ) {
        $HTTP_HEADER->{'-status'} = "401";
        html_error("could not authenticate");
    }

    if ( $o->{'type'} eq "hosts" ) {
        $ans = do_update_hosts($o);
    }

    if ( !defined $ans or ! ref($ans) ) {
        $HTTP_HEADER->{'-status'} = "500";
        html_error("error: update failed");
    }


    # result of 'update' operation is a csv:
    $o->{'data'} = [ [ "result", "description" ] ];

    my ($result, $description) = ( "failure", exists $ans->{'error'} ? $ans->{'error'} : "unknown" );
    if ( $ans->{'success'} == $ans->{'count'} ) {
        $result = "success";
        $description = "";
    }

    push( @{$o->{'data'}}, [ $result, $description ] );

    return $o;
}

# updates the database, one record at a time.
#   the table name is $o->{type}
#   the row data is $o->{args}, entries separates by newlines
sub do_update_hosts {
    my $o = shift;
    my $table = ucfirst sanitize($o->{'type'});

    my $data = $o->{'query'};
    my $queries = parse_queries($data);

    if ( !defined $queries ) {
        $HTTP_HEADER->{'-status'} = "400";
        html_error("invalid query format detected");
    } elsif (! @$queries ) {
        $HTTP_HEADER->{'-status'} = "200";
        html_error("no queries found");
    }

    # array of hashes! lots more convenient.
    my %hashdata = map { my ($a,$b)=("","");($a,$b)=split(/=/,$_,2) } @$data;

    # this is not used yet
    #my %args = split(/\000/, @{ $o->{'args'} });
    
    my @lookup = ( ["name","=",$hashdata{'name'}], ["offline","like","*"] );
    $o->{'lookup'} = { $table => { 'record' => "name", 'conditionals' => \@lookup } };
    print STDERR "lookup " . Dumper($o->{'lookup'}) if $VERBOSE;

    #my $result = lookup(table => $table, record => "name", conditionals => \@lookup);
    my $result = lookup($o);
    print STDERR "result " . Dumper($result);

    # 'name' entries in the database that matched what we're trying to set
    # since 'name' is supposed to be unique (for now), error out if there's a duplicate 'name'
    # entry found.
    my %found;
    for ( @$result ) {
        if ( exists $found{ $_->[0] } ) {
            $HTTP_HEADER->{'-status'} = "400";
            html_error("duplicate name \"$_->[0]\" detected");
        }
        $found{ $_->[0] }++;
    }
    print STDERR "found " . Dumper(\%found) if $VERBOSE;

    # build the update table
    my (@update_table,@insert_table);
    if ( exists $found{ $hashdata{'name'} } ) {
        push(@update_table, \%hashdata);
    } else {
        push(@insert_table, \%hashdata);
    }

    print STDERR "update: " . Dumper(\@update_table) if $VERBOSE;
    print STDERR "insert: " . Dumper(\@insert_table) if $VERBOSE;

    # We pass both 'update' and 'insert' at once so if any of this fails it'll all fail as one big
    # transaction instead of bits of it working and other bits not working. Well, if autocommit is
    # off.
    
    #my $result = update(
    $o->{'update'} = {
            'table' => {
                $table => {
                    'elements' => \@update_table
                }
            }
        };
    $o->{'insert'} = {
            'table' => {
                $table => {
                    'elements' => \@insert_table
                }
            }
        };
    $result = update($o);

    return $result;
}

sub do_get_operation {
    my $o = shift;
    my $ans;
    my @ret;

    if ( $o->{'type'} eq "hosts" ) {
        $ans = do_get_hosts($o);
    }

    if ( ref($ans) eq "ARRAY" ) {
        $o->{'data'} = [];
        #push( @{$o->{'data'}}, [ $TABLE_FIELDS{ucfirst $o->{'type'}} ] );
        push( @{$o->{'data'}}, $TABLE_FIELDS{ucfirst $o->{'type'}} );
        push( @{$o->{'data'}}, @{ $ans } );
    } else {
        push( @{$o->{'data'}}, $ans );
    }

    return $o;
}

sub do_get_hosts {
    my $o = shift;
    my @lookup;

    my $queries = parse_queries($o->{'query'});

    if ( !defined $queries ) {
        $HTTP_HEADER->{'-status'} = "400";
        html_error("invalid query format detected");
    } elsif (! @$queries ) {
        $HTTP_HEADER->{'-status'} = "200";
        html_error("no queries found");
    }

    $o->{'lookup'} = { $o->{'type'} => { 'record' => $o->{'record'}, 'conditionals' => $queries } };
    # my $ans = lookup( table => $o->{'type'}, conditionals => $queries, record => $o->{'record'} );
    print STDERR "ookup o: " . Dumper($o);
    my $ans = lookup($o);
    return $ans;
}

sub do_delete_operation {
    my $o = shift;
    my $ans;
    my @ret;

    if ( ! authenticate_update($o) ) {
        $HTTP_HEADER->{'-status'} = "401";
        html_error("could not authenticate");
    }

    if ( $o->{'type'} eq "hosts" ) {
        $ans = do_delete_hosts($o);
    }

    # result of 'update' operation is a csv:
    $o->{'data'} = [ [ "result", "description" ] ];

    my ($result, $description);
    if ( 
        exists $ans->{'success'} and exists $ans->{'count'} and
        length $ans->{'success'} and length $ans->{'count'} and
        $ans->{'success'} == $ans->{'count'} 
    ) {
        $result = "success";
        $description = "(count $ans->{count} success $ans->{success})";
    } else {
        $result = "failure";
        $description = exists $ans->{'error'} ? $ans->{'error'} : "unknown";
    }

    push( @{$o->{'data'}}, [ $result, $description ] );

    return($ans);
}

# returns either do_get_hosts(), or the number of successful records, or nothing
sub do_delete_hosts {
    my $o = shift;
    my $table = ucfirst sanitize($o->{'type'});
    my $dbstatus;
    my $ret;
    my $SQL;
    
    db_connect();

    my $lookup = do_get_hosts($o);
    print STDERR "lookup: " . Dumper($lookup) if $VERBOSE;
    
    if ( @$lookup < 1 ) {
        $o->{'error'} = "no rows found to delete";
        return $o;
    }

    $o->{'conditionals'} = parse_queries($o->{'query'});

    if ( !defined $o->{'conditionals'} ) {
        $HTTP_HEADER->{'-status'} = "400";
        html_error("invalid query format detected");
    } elsif (! @{ $o->{'conditionals'} } ) {
        $HTTP_HEADER->{'-status'} = "200";
        html_error("no queries found");
    }

    my $gotname = 0;
    for ( @{ $o->{'conditionals'} } ) {
        if ( $_->[0] =~ /^\s*name\s*$/ ) {
            $gotname++;
        }
    }

    my $del_action;
    if ( $gotname < @{$o->{'conditionals'}} ) {
        $del_action = "update";
    } elsif ( $gotname ) {
        $del_action = "delete";
    }

    # if they passed more than just a 'name' to delete
    if ( $del_action eq "update" ) {
        my %setvals;
        for ( @{ $o->{'conditionals'} } ) {
            if ( $_->[0] ne "name" ) {
                $setvals{ $_->[0] } = "\000NULL\000";
            }
        }

        print STDERR "somehow, $gotname bigger than " . @{$o->{'conditionals'}} . "\n";
        #return;

        $o->{'update'} = {
            'table' => {
                $table => {
                    'elements' => [\%setvals],
                    'conditionals' => $o->{'conditionals'} 
                } 
            } 
        };

    } elsif ( $del_action eq "delete" ) {
        # generates 'where name=blah'
        $SQL = "DELETE FROM $table";

        $ret = generate_sql_where($o);

        if ( !defined $ret->{'sql'} or $ret->{'sql'} =~ /^\s*$/ ) {
            $ret->{'error'} = "no generate_sql_where from \$o";
            return $ret;

        } else {
            $SQL .= $ret->{'sql'};
            # Do not allow wildcard deletion for rows
            $SQL =~ s/\%/\\%/g;

        }
    }

    # If they didn't pass --really-delete, tell them what was going to happen
    if (!exists $o->{'args'} or ! grep(/^--really-delete$/, @{$o->{'args'}}) ) {

        $o->{'success'} = 0;

        if ( $del_action eq "update" ) {
            $o->{'error'} = "update";
            my $elm = $o->{'update'}->{'table'}->{$table}->{'elements'}->[0];
            print STDERR "elm: " . Dumper( $elm );

            $o->{'error'} .= "; for " . join("", @{$o->{'lookup'}->{'hosts'}->{'conditionals'}->[0]} );
            $o->{'error'} .= " set " . join(",", map { $_=($_."=".$elm->{$_});s/\000//g;$_ } keys %$elm);

        } elsif ( $del_action eq "delete" ) {
            $o->{'error'} = "delete";
            print STDERR "$0: going to run: \"$SQL\"";

        }

        $o->{'error'} .= "; --really-delete needed; effects ".@$lookup." rows";
        return $o;
    }

    # Finally, execute the sql stuff

    if ( $gotname < @{$o->{'conditionals'}} ) {

        $ret = update($o);
        
    } elsif ( $gotname ) {

        print STDERR "$0: doing SQL \"$SQL\"\n" if $VERBOSE;
        $dbstatus = $DB->do($SQL, {RaiseError => 0});

        # No rows affected but returned true
        if ( $dbstatus eq "0E0" ) {
            $ret->{'error'} = "No rows affected";

        # True but 
        } elsif ( $dbstatus and ( $dbstatus < $o->{'count'} ) ) {
            $ret->{'error'} = "affected rows $dbstatus (less than expected $o->{count})";
            $ret->{'success'} = 0;
          
        } elsif ( ! $dbstatus ) {
            $ret->{'error'} = "delete failed ($DBI::errstr)";
            $ret->{'success'} = 0;
        }
    }

    return $ret;
}

sub parse_queries {
    my $q = shift;
    my @a;

    for (@$q) {
        if ( /^([^=]+?)(=|!=|\slike\s)(.+)$/ ) {
            my ($a,$b,$c) = ($1,$2,$3);
            $b =~ s/\s//g;
            push(@a, [ $a, $b, $c ]);
        } else {
            print STDERR "error: query \"$_\" not a valid key=val pair\n" if $VERBOSE;
            return undef;
        }
    }
    
    return \@a;
}

sub authenticate_update {
    return 1;
}

# html_error("stuff");
# html_error( $o, "stuff" );
sub html_error {
    # Default to '500' error
    if ( !exists $HTTP_HEADER->{'-status'} ) {
        $HTTP_HEADER->{'-status'} = "500";
    }
    if ( ref($_[0]) ) {
        my $o = shift;
        $HTTP_HEADER->{'-type'} = $o->{'content_type'};
    }
    print $Q->header(%$HTTP_HEADER) unless $STATE{'printed_header'};
    print $Q->start_html("Error"),
        $Q->h1("The following errors were found while processing your request"),
        "\n" . join("\n", @_) . "\n",
        $Q->end_html;
    $STATE{'printed_header'}++;

    exit(1);
}

# can be html_print($o, $text) or html_print($text)
sub html_print {
    $HTTP_HEADER->{'-status'} = ref($_[0]) ? $_[0]->{'content_type'} : exists $HTTP_HEADER->{'-status'} ? $HTTP_HEADER->{'-status'} : "200";

    print $Q->header(%$HTTP_HEADER) unless $STATE{'printed_header'};
    print join("\n", @_), "\n";
    $STATE{'printed_header'}++;
}

sub sanitize {
    return quotemeta($_[0]);
}

sub lookup {
    #my %opts = @_;
    my $opts = shift;
    my ($LOCK, $X, %H, @DATA);
    my $answer;

    # NOTE: the ucfirst below makes the first letter of the table capitalized (ucfirst)
    # 
    #my $table = exists $opts{'table'} ? "$opts{table}" : "hosts";

    foreach my $t ( keys %{ $opts->{'lookup'} } ) {
        my $h = $opts->{'lookup'}->{$t};
        my $table = ucfirst sanitize($t);
        print STDERR "table $table\n";

        # turns 'host,lan,os' into 'sanitize(host),sanitize(lan),sanitize(os)' (sort of)
        my $cols = join( ",", map { $_ eq "*" ? "*" : sanitize($_) } split(/,/, $h->{'record'}) );

        my $SQL = "SELECT $cols FROM $table";
        my %copy = %$opts;
        $copy{'conditionals'} = $h->{'conditionals'};

        my $sqlo = generate_sql_where(\%copy);
        $SQL .= $sqlo->{'sql'};

        my $tmp = db_query($SQL);
        if ( !defined $tmp ) {
            $HTTP_HEADER->{'-status'} = "500";
            html_error("Error: bad answer from sql: $DBI::err " . $DB->{'mysql_error'});
        }
        #elsif ( ref($tmp) eq "ARRAY" ) {
        #    $answer = [] if (!defined $answer);
        #    push(@{$answer}, $tmp);
        #} else {
            $answer = $tmp;
        #}
    }

    # an aref of arefs
    return $answer;
}

sub generate_sql_where {
    my $opts = shift;

    return "" unless (exists $opts->{'conditionals'});

    my $goodcond = 0;
    my $cond_line = " WHERE";

    for ( my $i=0; $i<@{ $opts->{'conditionals'} }; $i++ ) {
        my $c = $opts->{'conditionals'}->[$i];
        my ($key,$op,$val) = @$c;

        if ( $op !~ /^(like|=|!=)$/ ) {
            warn "Error: conditional \"$op\" is invalid operator";
            next;
        }

        $val = sanitize($val);

        # Turn '*' character into match-all SQL character
        if ( $val =~ s/\\\*/%/g ) {
            $op = "like";
        }
        #print STDERR "val: \"$val\"\n";

        $cond_line .= " AND" if ($i > 0);
        $cond_line .= " " . sanitize($key) . " $op '$val'";

        $goodcond++;
    }

    # by default filter out all offline entries
    if ( 
        ! grep(/^--offline$/, @{$opts->{'args'}}) and
        ! grep { $_->[0] =~ /^offline$/i } @{ $opts->{'conditionals'} }
    ) {
        $cond_line .= " AND offline != 1";
    }

    $opts->{'sql'} = $cond_line;
    $opts->{'success'} = $goodcond;
    $opts->{'count'} = @{$opts->{'conditionals'}};

    return $opts;
}


# NOTE: updates based on 'name' key, until i fix that.
# 'update' does an update of tables based on 'name',
# 'insert' just inserts stuff verbatim
# update( 'update' => {'table'=>{'Hosts'=>[{'name'=>'rkvrhld117','os'=>'RHEL5.6'}]}})
sub update {
    #my %opts = @_;
    my $opts = shift;

    db_connect();

    foreach my $type ( ("update", "insert") ) {
        foreach my $table ( keys %{ $opts->{$type}->{'table'} } ) {
            my ($elements, $conditionals) = ($opts->{$type}->{'table'}->{$table}->{'elements'}, $opts->{$type}->{'table'}->{$table}->{'conditionals'});
            foreach my $hashpairs ( @$elements ) {
                my $SQL;

                # i'd like to keep the ability to update records en-masse without hostnames,
                # but we never insert a new row without a host name
                if ( $type eq "insert" and !exists $hashpairs->{'name'} ) {
                    $HTTP_HEADER->{'-status'} = "400";
                    html_error("no 'name' specified in one of the update fields");
                }

                # since 'name' is supposed to be unique and we don't want something messed
                # up like setting 'name' to '*', constrain it to only a valid hostname's
                # characters.
                # NOTE: unicode users will probably kill me for this .....
                if ( exists $hashpairs->{'name'} and $hashpairs->{'name'} !~ /^[a-zA-Z0-9-]+$/ ) {
                    $HTTP_HEADER->{'-status'} = "400";
                    html_error("name key has invalid characters");
                }

                if ( $type eq "insert" ) {
                    $SQL = "INSERT INTO " . sanitize($table) . " (" . 
                        join(",",
                            map {  sanitize($_)  } keys %$hashpairs
                        ) .
                        ") VALUES (" .
                        join(",",
                            map {
                                # If you want to actually 'NULL' a record, or make it undefined,
                                # you have to remove the quotes from NULL. This special value will
                                # be our indicator to do that.
                                if ( $_ eq "\000NULL\000" ) {
                                    "NULL"
                                } else {
                                    "\"" . sanitize($_) . "\""
                                }
                            } values %$hashpairs
                        ) .
                        ");";

                } elsif ( $type eq "update" ) {
                    # UPDATE Hosts SET k1=v1, k2=v2 WHERE name=blah
                    # notice here how we match based on 'name=$hashpairs->{$_}', so we are
                    # restricted to having unique 'name' here.

                    $SQL = "UPDATE " . sanitize($table) . " SET " .
                        join(", ",
                            map {
                                # If you want to actually 'NULL' a record, or make it undefined,
                                # you have to remove the quotes from NULL. This special value will
                                # be our indicator to do that.
                                if ( $hashpairs->{$_} eq "\000NULL\000" ) {
                                    sanitize($_)."=NULL";
                                } else {
                                    sanitize($_)."=\"".sanitize($hashpairs->{$_})."\""
                                }
                            } keys %$hashpairs
                        );

                    if ( defined $conditionals and @$conditionals ) {
                        my %copy = %$opts;
                        $copy{'conditionals'} = $conditionals;

                        my $sqlo = generate_sql_where( \%copy );
                        $SQL .= $sqlo->{'sql'};

                    } else {
                        if ( !exists $hashpairs->{'name'} ) {
                            $HTTP_HEADER->{'-status'} = "400";
                            html_error("no name found in update\n");
                        }

                        $SQL .= " WHERE name=\"" . sanitize($hashpairs->{'name'}) . "\"";
                    }
                }

                print STDERR "$0: Doing SQL: \"$SQL\"\n" if $VERBOSE;

                if ( $DB->do($SQL) ) {
                    #$HTTP_HEADER->{'-status'} = "500";
                    #html_error("update failed");
                    $opts->{'success'}++;
                } else {
                    $opts->{'error'} .= ($opts->{'count'}+1) . ": could not do SQL: \"" . $DB->{'mysql_error'} . "\"\n";
                }

                $opts->{'count'}++;
            }
        }
    }

    if ( ! $DB->commit() ) {
        #$HTTP_HEADER->{'-status'} = "500";
        #html_error("could not commit to database");
        $opts->{'error'} .= "could not commit to database: \"" . $DB->{'mysql_error'} . "\"\n";
    }

    return $opts;
}

sub db_connect {
    if ( !defined $DB ) {
        if ( defined $DB_CREDS_FILE ) {
            if ( ! open(FILE, "<$DB_CREDS_FILE") ) {
                $HTTP_HEADER->{'-status'} = "500";
                html_error("Error: could not read database credentials file: $!");
            }
            @DB_AUTH = map { s/(\r|\n|\r\n)//g; $_ } <FILE>;
            close(FILE);
        }

        $DB = DBI->connect($DB_CONN, $DB_AUTH[0], $DB_AUTH[1], { RaiseError => 0, AutoCommit => 0 });
        if ( ! $DB ) {
            $HTTP_HEADER->{'-status'} = "503";
            html_error("Error: could not connect to database: $! (" . $DB->{'mysql_error'} . " $DBI::err");
        }
    }
}

sub db_query {
    my $SQL = shift;
    db_connect();

    print STDERR "$0: doing SQL: \"$SQL\"\n" if $VERBOSE;
    return $DB->selectall_arrayref($SQL, { RaiseError => 0 });
}

sub encode_string {
    my $oldstr = $_[0];
    $oldstr =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
    return $oldstr;
}

sub decode_string {
    my $oldstr = $_[0];
    $oldstr =~ s/\%([A-Fa-f0-9]{2})/pack('C', hex($1))/seg;
    return $oldstr;
}

# takes an object reference and an aref of arefs.
# based on $o->{'data_type'} will split the data accordingly.
# currently only supports 'csv' data_type.
#
# format_list( $object, $arefs )

sub format_list {
    my ($o, $aref) = @_;
    my $type = $o->{'data_type'};
    my ($row,$col);
    if ( $type eq "csv" ) {
        ($row,$col)=("\n", ",");
        return join($row, map {
            join $col, map {
                # if commas exist but whole row isn't quoted
                if ( $_ !~ /^\s*"/ && /,/ ) {
                    # escape any extraneous quotes
                    s/"/\\"/g;
                    # return row quoted
                    "\"$_\""
                } else {
                    $_
                }
            } @$_
        } @$aref);
    }
}

# ugh. i know there must be a regex i can use instead of this,
# but i'm stupid and lazy and it works.
sub parse_csv {
    my $aref = shift;
    my @queries;
    my @q;

    foreach my $q ( @$aref ) {
        my @a = split //, $q;
        my ($quot,$s) = (0,0);
        my @r;

        my $i;
        for ( $i=0; $i<@a; $i++ ) {
            if ( $a[$i] eq '"' ) {
                if ( $a[$i-1] ne "\\" && ! $quot ) {
                    $quot++;
                    next
                } elsif ( $a[$i-1] ne "\\" && $quot ) {
                    $quot--;
                    next 
                }
            }
            if ( $a[$i] eq "," && ! $quot ) {
                push(@r, join('', @a[$s..$i-1]));
                $s=$i+1;
            }
        }
        push(@r, join('', @a[$s..$i])) if ($s != @a);

        push(@q, \@r);
    }

    return \@q;
}

