#!/usr/bin/perl
use strict;
$|=1;

my $LDAP_SCRIPT="$ENV{HOME}/git/scripts/ldap_search.sh";
my $GROUPWISE_SCRIPT="$ENV{HOME}/git/scripts/groupwise_search.sh";

open my $stdout, ">names.map" || die;


for my $group ( glob("*.txt") ) {
    (my $GROUP=$group) =~ s/\.txt$//g;
    my @NAMES = map { chomp; $_ } `cat "$group"`;

    foreach my $NAME (@NAMES) {
        my (%AD_INFO, %GP_INFO);
        my ($ACCT,$MAIL);

        (my $LN=$NAME) =~ s/^.*\s(\S+)$/$1/g;
        (my $FN=$NAME) =~ s/^(\S+)\s.*$/$1/g;
        my $FNsub = substr($FN, 0, 1);

        #print "name $NAME fn $FN ln $LN\n";

        %AD_INFO = map { chomp; if ( /^(\w+): (.+)$/ ) { $1 => $2 } } `$LDAP_SCRIPT "(&(sn=$LN)(givenName=$FN))" cn saMAccountName sn givenName mail`;

        if ( ! %AD_INFO ) {
            %AD_INFO = map { chomp; if ( /^(\w+): (.+)$/ ) { $1 => $2 } } `$LDAP_SCRIPT "(&(sn=$LN)(givenName=$FNsub*))" cn saMAccountName sn givenName mail`;

            if ( ! %AD_INFO ) {
                print STDERR "Error: no name matching sn=$LN,givenName=$FNsub*\n";
                next;
            }
        }

        %GP_INFO = map { chomp; if ( /^(\w+): (.+)$/ ) { $1 => $2 } } `$GROUPWISE_SCRIPT "(&(sn=$LN)(givenName=$FN))" cn sn givenName mail`;

        if ( ! %GP_INFO ) {
            %GP_INFO = map { chomp; if ( /^(\w+): (.+)$/ ) { $1 => $2 } } `$GROUPWISE_SCRIPT "(&(sn=$LN)(givenName=$FNsub*))" cn sn givenName mail`;
        }

        if ( !exists $GP_INFO{'mail'} ) {
            $MAIL = $AD_INFO{'mail'};
        } else {
            $MAIL = $GP_INFO{'mail'};
        }

        $ACCT = $AD_INFO{'sAMAccountName'};

        #print STDERR "name $NAME gmail $GP_INFO{mail} admail $AD_INFO{mail}\n";
        print $stdout "name: $NAME fn: $FN ln: $LN account: ".lc $ACCT." mail: ".lc $MAIL." group: $GROUP\n";
    }

}


