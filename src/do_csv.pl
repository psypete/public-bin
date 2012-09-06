#!/usr/bin/perl
use strict;
use Text::CSV;
use Data::Dumper;

open(my $stdin, ">-") || die;
my $csv = Text::CSV->new({binary=>1});
open my $fh, $ARGV[0] || die "open: $!";
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
while ( <$fh> ) {
    chomp;
    $csv->parse($_);
    my @f = $csv->fields();
    do_row($csv, { map { $cn[$_] => $f[$_] } (0..$#cn) }, \@f );
}
close $fh;

exit(0);


sub do_row {
    my $csv = shift;
    my $h = shift;
    my $a = shift;
    #$csv->print($stdin, $a) if ( $h->{'Sys_Admin'} =~ /^\s*?$/ );
    #$csv->print($stdin, $a) if ( $h->{'OS'} =~ /^\s*?$/ );
    #print Dumper($h);
    my @name;
    foreach my $n ( qw(Sys_Admin PointofContact UserID) ) {
        if ( exists $h->{$n} or $h->{$n} !~ /^\s*?$/ ) {
            push(@name, map { s/^(\w+),\s+(\S.+)$/$2 $1/g; $_ } split(/\//, $h->{$n}));
        }
    }
    my $c=0;
    foreach my $name (@name) {
        my $ln = $name;
        $ln =~ s/^\w+.*\s(\S+)$/$1/g;
        #print "checking name $name\n";
        if ( exists $groups{ uc $name } ) {
            print "Server $h->{ServerName} Group " . $groups{uc $name} . " Admin $name\n";
            last;
        } elsif ( exists $lngroups{ uc $ln } ) {
            print "Server $h->{ServerName} Group " . $lngroups{uc $ln} . " Admin $name\n";
            last;
        }
        $c++;
    }
    if ( !@name or @name == $c ) {
        print "No Group for Admin " . join("-",@name) . " ($h->{ServerName})\n";
    }
}

