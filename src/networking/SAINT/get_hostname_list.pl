#!/usr/bin/perl
# get_hostname_list.pl - resolve hostnames to IPs and vice versa, return the records

$|=1;
use strict;
use Socket;
use Data::Dumper;

if ( (! @ARGV and -t *STDIN) or (@ARGV and ! -f $ARGV[0]) ) {
    die "Usage: cat list_of_ip_addresses.txt | $0\nUsage: $0 list_of_ip_addresses.txt\n\nResolves a list of IP addresses to names, either passed via standard input or a filename as the first argument.\n\nExample:\n\n\tcsvgrep.pl -f active_server_list.csv -n IPAddresses \"\\.\" | csvcut.pl -r -n ServerName -n IPAddresses | tail -n +2 | $0\n";
}


# Get 'Servername,IPAddresses' list
if ( -f $ARGV[0] ) {
    open(PIPE, "< $ARGV[0]") || die "Error: cannot open file: $!\n";
} else {
    *PIPE = *STDIN;
}

my @list = map { chomp; [ split /,/, $_, 2 ] } <PIPE>;
close(PIPE);

my %checked;

foreach my $pair ( @list ) {

    next if exists $checked{$pair->[0]};

    print STDERR "INFO: Checking $pair->[0]\n";
    $checked{$pair->[0]}++;
    # Try to Resolve ServerName
    my @n = gethostbyname( $pair->[0] );

    # No name! Get reverse of IPAddress
    if ( !defined $n[0] or length($n[0]) < 1 ) {

        next if exists $checked{$pair->[1]};

        print STDERR "INFO: Checking $pair->[1]\n";
        $checked{$pair->[1]}++;
        @n = gethostbyaddr( inet_aton($pair->[1]), AF_INET );
        
        # Not even a reverse on the IP? I give up.
        if ( !defined $n[0] or length($n[0]) < 1 ) {
            print "Error: no hostname or reverse for \"$pair->[0],$pair->[1]\"\n";
            next;
        }
    }

    print "($pair->[0],$pair->[1])=$n[0]\n";

}

