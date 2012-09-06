#!/usr/bin/perl

$|=1;
use strict;
use Encode;
use Text::CSV;
use Data::Dumper;

@ARGV == 3 || die "Usage: $0 SERVER_CSV_FILE MAPPING_FILE OUTFILE\n";

my %mapfile = map { chomp; $_ } map { split(/=/,$_,2) } `cat $ARGV[1]`;

open(my $stdout, ">$ARGV[2]") || die;
open my $fh, $ARGV[0] || die "open: $!";

my $csv = Text::CSV->new( { binary => 1 } );
$csv->column_names( @{$csv->getline($fh)} );
my @cn = $csv->column_names;
$csv->eol("\r\n");

my %groups;
my %lngroups;
my @groups = glob("groups/*.txt");
for my $group (@groups){
    my $gn = $group;
    $gn =~ s/^.*\/(.+)\.txt$/$1/g;
    map { 
        chomp;
        $groups{uc $_} = $gn;
        if ( /^\w+.*\s(\S+)$/ ) {
            $lngroups{uc $1} = $gn;
        }
    } `cat $group`;
}

#print "groups:" . Dumper(\%groups) . Dumper(\%lngroups);

#%h = map { $_ } $csv->column_names;
while ( my $buf = <$fh> ) {
    s/(\r|\n)//g;
    $csv->parse($buf) || $csv->error_diag;
    my @f = $csv->fields();
    #print "fields: @f\n";
    do_row($csv, { map { $cn[$_] => $f[$_] } (0..$#cn) }, \@f );
}
close $fh;

exit(0);


#################################################################################################


sub lookup_admin {
    my $h = shift;
    my @columns = @_;

    # Expand names in this row
    my @name;
    #foreach my $n ( qw(Sys_Admin PointofContact UserID) ) {
    foreach my $n ( @columns ) {
        if ( exists $h->{$n} or $h->{$n} !~ /^\s*?$/ ) {
            my @tmp = map { s/^(\w+),\s+(\S.+)$/$2 $1/g; $_ } split(/\//, $h->{$n});
            push(@name, map { exists $mapfile{$_} ? $mapfile{$_} : $_ } @tmp);
        }
    }

    # Guess the group based on Sys_Admin's assigned group
    # This should be most reliable as Sys_Admin is person who owns the device
    my $c=0;
    foreach my $name (@name) {
        my $ln = $name;
        $ln =~ s/^\w+.*\s(\S+)$/$1/g;
        #print "checking name $name\n";
        if ( exists $groups{ uc $name } ) {
            print STDERR "Server $h->{ServerName} field @columns matched uppercase '$name'\n";
            print $stdout "Server $h->{ServerName} Group " . $groups{uc $name} . " Admin $name\n";
            #last;
            return 1;
        } elsif ( exists $lngroups{ uc $ln } ) {
            print STDERR "Server $h->{ServerName} field @columns matched uppercase '$ln'\n";
            print $stdout "Server $h->{ServerName} Group " . $lngroups{uc $ln} . " Admin $name\n";
            #last;
            return 1;
        }
        $c++;
    }

    if ( @name == $c ) {
        return(0);
    }

    return 1;
}


sub do_row {
    my $csv = shift;
    my $h = shift;
    my $a = shift;

    # Look up server group by Sys_Admin group (most reliable)
    if ( lookup_admin($h, qw(Sys_Admin) ) ) {
        return;
    }


    # Look for the OS, ManufacturerName, ModelNumber, etc to classify hardware
    # Not as reliable, but close
    my $groupguess;
    if ( $h->{OS} =~ /(windows|esx|netware)/i ) {
        print STDERR "$h->{ServerName} is guessed as 'lan' (field OS matched windows/esx/netware)\n";
        $groupguess = "lan";
    }
    elsif ( $h->{OS} =~ /(linux|solaris|aix|hp-ux|openvms)/i or $h->{ServerType} =~ /(unix|vms)/i ) {
        print STDERR "$h->{ServerName} is guessed as 'unix' (field OS matched linux/solaris/aix/hp-ux/openvms)\n";
        $groupguess = "unix";
    }
    elsif ( $h->{ModelNumber} =~ /(juniper|alcatel|cisco|catalyst)/i or $h->{OS} =~ /cisco/i ) {
        print STDERR "$h->{ServerName} is guessed as 'network' (field ModelNumber matched juniper/alcatel/cisco/catalyst or field OS matched cisco)\n";
        $groupguess = "network";
    }

    if ( defined $groupguess ) {
        print $stdout "Server $h->{ServerName} Group $groupguess (gg)\n";
        return;
    }

    # Finally, try to match the host to a group via the Point of Contact or User ID
    # (this basically always works, but is much more unreliable)
    #if ( ! lookup_admin($h, qw(PointofContact UserID) ) and !defined $groupguess ) {
    if ( ! lookup_admin($h, qw(PointofContact) ) and !defined $groupguess ) {
        print $stdout "No Group for $h->{ServerName}\n";
    }
}

sub mark_utf8 { pack "U0C*", unpack "C*", join('',@_); }

