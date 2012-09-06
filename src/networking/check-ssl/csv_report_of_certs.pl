#!/usr/bin/perl
# csv_report_of_certs.pl - print a CSV file with a summary of certificate information
# Copyright (C) 2012 Peter Willis <peterwwillis@yahoo.com>

$|=1;
use strict;
use Digest::MD5;
use IPC::Open2;
use Date::Parse;

my $VERBOSE = exists $ENV{VERBOSE} ? $ENV{VERBOSE} : 0;

# 
# The way SSL cert lookups work, afaik:
# 1. Load the original server's certificate
# 2. Look for Authority Key Identifier in any of the root CA certs.
# 3. If not found, Look for 'Authority Information Access -> CA Issuers'
#    in server cert.
# 4. Download the CA Issuer URL, decode the certificate
# 5a. Compare the original certficate's Authority Key Identifier to
#     the Subject Key Identifier of the CA Issuer cert
# 5b. If 4a does not match look for a CA Issuer in this new cert and
#     go back to step 3
# 6a. Look for the Authority Key Identifier of this latest cert in
#     the root CA certsfor each cert as its Subject Key identifier.
# 6b. If there is no Key Identifier in the CA cert, compare the
#     Subject of the CA certs to the Issuer of the last chained
#     cert
# 

die "Usage: $0 OPTIONS CERTIFICATE [..]\n\nOptions:\n  -s N\t\tSort by field number N\n  -n\t\tSort numerically\n  -r\t\tReverse sort results\n" unless @ARGV;

my $SORT = 1; # Default sort
my $SORTTYPE = "alpha";
my $REVERSE = 0;
my $DATERECORD = 6;

my @CERTS;
while ( $_ = shift @ARGV ) {
    if ( $_ eq "-s" ) {
        $SORT = shift @ARGV;
    } elsif ( $_ eq "-n" ) { 
        $SORTTYPE = "numeric";
    } elsif ( $_ eq "-r" ) {
        $REVERSE = 1;
    } else {
        push(@CERTS, $_);
    }
}
$SORT--;

my %VALID;
my @f = map { s/(\r|\n)//g; $_ } `cat is_cert_valid.log`;
for (@f) {
    if ( /^(.+) is valid$/ ) {
        my $fn = $1;
        $fn =~ s/^.*\///g;
        $VALID{$fn}++;
    }
}

main(@CERTS);
exit(0);


sub main {

    #print "Common Name,Subject Alternate Name,Expiration Date,Trusted,Expired\n";
    #print "IP Address,Domain Name,Valid CA,Self Signed,Organization,Expiration Date,Expired\n";
    print "IP Address,Domain Name,Valid CA,Self Signed,Domain Organization,Certificate Issuer,Expiration Date,Expired\n";

    my @lines;
    foreach my $cert (@_) {
        my $ret = [ get_cert_data($cert) ];
        if ( !defined $ret or ! @$ret ) {
            next;
        }
        push(@lines, $ret);
    }

    my @newlines;

    # Sort correctly; first two fields are not numeral, the rest are
    if ( $SORTTYPE eq "numeric" ) {
        @newlines = sort { my $z;if($REVERSE){$z=$a;$a=$b;$b=$z;}; $b->[$SORT] <=> $a->[$SORT] } @lines;
    } else {
        @newlines = sort { my $z;if($REVERSE){$z=$a;$a=$b;$b=$z;}; $b->[$SORT] cmp $a->[$SORT] } @lines;
    }


    # Print the CSV
    for ( @newlines ) {

        # Convert epoch time to localtime
        $_->[$DATERECORD] = localtime($_->[$DATERECORD]);

        print join(",", map { "\"$_\"" } @$_) . "\n";
    }
}


sub get_cert_data {
    my $file = shift;
    my $expired = 0;
    my $trusted = 0;

    my $data = load_certificate($file);
    my $cert = read_cert_text($data);

    print "Certificate Subject: '$cert->{'subject'}'\n" if $VERBOSE;
    
    ## Check trust
    #system("./is_certificate_trusted.pl $file ./ca-certs-txt 1>&2");
    #$trusted = ( $? >> 8 ) ? 0 : 1;

    # Speed hack!
    my $fn = $file;
    $fn =~ s/^.*\///g;
    if ( exists $VALID{$fn} ) {
        print STDERR "VALID $fn\n" if $VERBOSE;
        $trusted++;
    }

    # Check expiration
    my $nowtime = time();
    my $notaftertime = Date::Parse::str2time( $cert->{'not_after'} );
    if ( $notaftertime <= $nowtime ) {
        $expired = 1;
    }

    my $cn = $cert->{'subject'};
    if ( $cn =~ /^.*CN=([a-z0-9. \\*-]+)/i ) {
        $cn = $1;
    }

    # Exclude non-domains
    if ( $cn =~ /\s/ ) {
        return;
    }

    # Divine IP address from file name
    my $ip = $file;
    $ip =~ s/^.*\///g;
    $ip =~ s/\.[a-z]+$//ig;

    # Get 'O=' entry. May have commas.
    my %orgs;
    for ( qw(subject issuer) ) {
        $orgs{$_} = $cert->{$_};
        if ( $orgs{$_} =~ s/^.*O=// ) {
            if ( $orgs{$_} =~ /^(.+?), \w+=/ ) {
                $orgs{$_} = $1;
            }
        } else {
            $orgs{$_} = "N/A";
        }
    }

    #print "\"$cn\",\"$cert->{'subj_alt_name'}\",\"$cert->{'not_after'}\",$expired\n";
    #return ($cn, $cert->{'subj_alt_name'}, $cert->{'not_after'}, $trusted, $expired);
    #return ($cn, $cert->{'subj_alt_name'}, $notaftertime, $trusted, $expired);

    return ($ip, $cn, $trusted ? "Yes" : "No", $trusted ? "No" : "Yes", $orgs{'subject'}, $orgs{'issuer'}, $notaftertime, $expired ? "Yes" : "No");
}


sub load_data {
    my $file = shift;
    open(my $fd, "<$file")||die"Error: cannot open $file: $!";
    #my @data = map { s/(\r|\n)//g; $_ } <$fd>;
    #my $r = read($fd, my $buf, -s $file);
    #my @data = split(/\n/, $buf);
    my @data = <$fd>;
    close($fd);

#    print "read $r data\n";
#    print "have " . length(join("",@data)) . " data\n";

    return \@data;
}


# Takes a file and reads it,
# or takes an array ref of read data.
# Converts it to text if it's in PEM or DAR format.
sub load_certificate {
    my $file = shift;
    my ($inform, $data);
    
    if ( ref($file) ne "ARRAY" and -f $file ) {
        $data = load_data($file);
    } elsif ( ref($file) eq "ARRAY" ) {
        $data = $file;
    }

    if ( $data->[0] =~ /^Certificate:/ ) {
        # If it's already been converted to text
        undef $inform;
    } elsif ( grep(/BEGIN CERTIFICATE/, @$data) ) {
        # PEM format
        $inform = "PEM";
    } else {
        # There's one more format out there but I haven't seen it so i'm ignoring it
        $inform = "DER";
    }

    if ( defined $inform and length $inform ) {
        # Convert cert data to text

        print "Decoding $inform certificate data\n" if $VERBOSE;

        my $pid = open2(my $readfd, my $writefd, "openssl x509 -noout -text -inform $inform") || die "Error: cannot open openssl: $!";

        print $writefd join("", @$data);
        close($writefd);

        $data = [ map { s/(\r|\n)//g; $_ } <$readfd> ];
        close($readfd);

        # Remember to reap open2() orocess
        waitpid($pid, 0);
    }

    if ( ! @$data ) {
        die "Error: could not load certificate data for $file\n";
    }

    return $data;
}


sub read_cert_text {
    my $data = shift;
    my %h;
    my @caissuers;

    for ( my $i=0; $i<@$data; $i++ ) {
        $_ = $data->[$i];

        if ( /CA Issuers - URI:(.+)/ ) {
            push(@caissuers, $1);

        } elsif ( /X509v3 Subject Key Identifier:/ ) {
            $_ = $data->[++$i];
            if ( /^\s+(\w\w:\w\w:\w\w:\w\w:.+)$/ ) {
                # subject key identifier has no 'keyid'
                $h{'subj_key_ident'} = $1;
                chomp $h{'subj_key_ident'};
            }

        } elsif ( /X509v3 Authority Key Identifier:/ ) {
            $_ = $data->[++$i];
            if ( /^\s+keyid:(.+)$/ ) {
                $h{'auth_key_ident'} = $1;
                chomp $h{'auth_key_ident'};
            }

        } elsif ( /X509v3 Subject Alternative Name:/ ) {
            $_ = $data->[++$i];
            s/^\s+//g;
            my @names = split(/,\s+/, $_);
            # Remove item names
            @names = map { s/^[\w ]+://; $_ } @names;
            $h{'subj_alt_name'} = join(",", @names);
            chomp $h{'subj_alt_name'};

        } elsif ( /^\s+Issuer: (.+)$/ ) {
            $h{'issuer'} = $1;
            chomp $h{'issuer'};

        } elsif ( /^\s+Subject: (.+)$/ ) {
            $h{'subject'} = $1;
            chomp $h{'subject'};

        } elsif ( /^\s+Not After\s*: (.+)$/ ) {
            $h{'not_after'} = $1;
            chomp $h{'not_after'};

        }
    }

    $h{'ca_issuers'} = \@caissuers;

    return \%h;
}

