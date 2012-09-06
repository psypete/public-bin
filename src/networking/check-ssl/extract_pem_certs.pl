#!/usr/bin/perl
# extract_pem_certs.pl - extracts pem certs from a file and saves them to individual files

$|=1;
use strict;

my ($begin, $end) = (0, 0);
my $counter = 0;
my ($host, @cert, %all);

die "Usage: $0 FILE DIR\n\nExtracts PEM certs from FILE and saves them in DIR.\n\nIf FILE is a .nmap scan result file, names the output file that of the scanned host.\n" if @ARGV < 2;

open(FILE, "<$ARGV[0]") || die "COuldn't open: $!";
while ( <FILE> ) {

    chomp;

    if ( /Nmap scan report for (.+)/ ) {
        $host = $1;
    } elsif ( /BEGIN CERTIFICATE/ ) {
        $end = 0;
        $begin = 1;
    }

    if ( $begin == 1 and $end == 0 ) {
        #if ( /^\|[ _](.+)$/ ) {
            #my $stuff = $1;
            my $stuff = $_;
            $stuff =~ s/^\|[ _]//g;
            $stuff =~ s/(\r|\n)//g;
            push(@cert, $stuff);
        #}
    }

    if ( /END CERTIFICATE/ ) { 
        $end = 1;
        $begin = 0;
        $counter++;
    }

    if ( $end == 1 ) {
        if ( !defined $host ) {
            $all{$counter} = [ @cert ];
        } else {
            $all{$host} = [ @cert ];
        }
        $end = 0;
        @cert = ();
    }

}
close(FILE);

if ( ! -d "$ARGV[1]" ) {
    mkdir("$ARGV[1]") || die "Error: cannot make '$ARGV[1]' dir: $!";
}

for ( keys %all ) {
    open(CERT, ">$ARGV[1]/$_") || die "Error: cannot make $ARGV[1]/$_: $!";
    print "printing to $ARGV[1]/$_: " . join("", @{ $all{$_} }) . "\n";
    print CERT join("\n", @{ $all{$_} } );
    print CERT "\n";
    close(CERT);
}

