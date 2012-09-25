#!/usr/bin/perl
# is_certificate_trusted.pl - checks if a certificate is trusted by a root CA
# Copyright (C) 2012 Peter Willis <peterwwillis@yahoo.com>

$|=1;
use strict;
use Digest::MD5;
use IPC::Open2;

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

die "Usage: $0 certificate ca-certificate-text-dir\n" if @ARGV != 2;

my $CERT = shift @ARGV;
my $CACERTDIR = shift @ARGV;


if (! main() ) {
    die "Error: Could not find Certificate Authority for this certificate.\n";
    exit(1);
}

exit(0);


sub main {

    my @cacerts = map {
            my $data = load_certificate($_);
            read_cert_text($data);
        } glob("$CACERTDIR/*");

    my $data = load_certificate($CERT);
    my $cert = read_cert_text($data);

    print "Certificate Subject: '$cert->{'subject'}'\n" if $VERBOSE;

    die "Error: this is a CA certificate or a self-signed certificate!\n" if cert_is_root_ca($cert);
        
    my @issuers;
    my $counter = 0;

    # Loop over any CA Issuers recursively, resolving the chain of trust

    my @uris = @{ $cert->{'ca_issuers'} };
    my $old = $cert;
    while ( @uris ) {

        my $tmpissuer;
        my @tmpuris = @uris;
        @uris = ();

        for my $cai ( @tmpuris ) {
            if ( $cai =~ /^http/i ) {
                my $tmpcert = download_issuer($cai);
                if ( defined $tmpcert ) {
                    $tmpissuer = $tmpcert;
                    print "Issuer Subject: '$tmpissuer->{'subject'}'\n" if $VERBOSE;
                    last;
                }
            }
        }

        # Check if the previous cert is chained to the new one
        if ( 
               ( $old->{'auth_key_ident'} eq $tmpissuer->{'subj_key_ident'} )
            or ( $old->{'issuer'} eq $tmpissuer->{'subject'} )
        ) {
            # Now find out if new cert is a CA, or has more links in the chain
            if ( cert_is_root_ca($tmpissuer) ) {
                #die "Error: Found the root CA ($tmpissuer->{'subject'}) but it isn't in our list of trusted CAs!";
                print STDERR "Found root CA $tmpissuer->{'subject'}\n" if $VERBOSE;
            }
        } else {
            # The previous cert wasn't chained to this one? Hacker!!
            die "Error: the cert isn't chained to the next one found!";
        }

        @uris = @{$tmpissuer->{'ca_issuers'}};

        if ( ! @uris ) {

            my $match_ca = 0;

            # We have no more links in the chain, so check the CA root files
            # to see if one of them matches the current one's auth key or issuer
            foreach my $ca ( @cacerts ) {

                if (
                    defined $tmpissuer->{'auth_key_ident'} and length $tmpissuer->{'auth_key_ident'}
                    and defined $ca->{'subj_key_ident'} and length $ca->{'subj_key_ident'}
                    and $tmpissuer->{'auth_key_ident'} eq $ca->{'subj_key_ident'}
                ) {
                    $match_ca = 1;
                    print STDERR "Issuer auth key matches CA subj key: $tmpissuer->{'auth_key_ident'}\n" if $VERBOSE;
                }

                if (
                    defined $tmpissuer->{'issuer'} and length $tmpissuer->{'issuer'}
                    and defined $ca->{'subject'} and length $ca->{'subject'}
                    and $tmpissuer->{'issuer'} eq $ca->{'subject'}
                ) {
                    $match_ca += 2;
                    print STDERR "Issuer text matches CA text: $tmpissuer->{'issuer'}\n" if $VERBOSE;
                }

                if ( $match_ca ) {
                    print "Root CA subject: '$ca->{'subject'}'\n" if $VERBOSE;

                    if ( cert_is_root_ca($ca) ) {
                        print "Found root CA for $CERT: $ca->{'subject'}\n";
                        return 1;
                    } else {
                        die "Root CA isn't a root CA!";
                    }
                }

            }

            die "Error: new cert '$tmpissuer->{'subject'}' does not match old cert '$old->{'issuer'}', and there's no more chain to go up!\n";
        }

        $old = $tmpissuer;
        $counter++;
    }

    return 0;
}


sub download_issuer {
    my $uri = shift;
    my $digest = Digest::MD5::md5_hex($uri);
    my ($fd, $data);

    if ( -e "ca-issuer-$digest.cer" ) {

        print STDERR "Using cached issuer ca-issuer-$digest.cer\n";
        $data = load_data("ca-issuer-$digest.cer");

    } else {

        print STDERR "Downloading CA Issuer $uri\n";

        open(PIPE, "lwp-request \"$uri\" |") || die "Error: cannot open pipe: $!";
        #$data = [ map { s/(\r|\n)//g; $_ } <PIPE> ];
        # DO NOT REMOVE \r or \n! This may be binary DER certificate data
        $data = [ <PIPE> ];
        close(PIPE);

        # Cache the issuer cert
        open($fd, ">ca-issuer-$digest.cer") || die "Error: cannot write issuer to disk: $!";
        # DO NOT ADD \n! This may be binary DER certificate data
        print $fd @$data;
        close($fd);

    }

    $data = load_certificate($data, $uri);

    return read_cert_text($data);
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
    my $uri = shift;
    my ($inform, $data, $fmt);
    
    if ( ref($file) ne "ARRAY" and -f $file ) {
        $data = load_data($file);
    } elsif ( ref($file) eq "ARRAY" ) {
        $data = $file;
    }

    if ( defined $uri and length $uri ) {
        if ( $uri =~ /\.p7[bc]$/i ) {
            $fmt = "pkcs7";
        } elsif ( $uri =~ /\.(p12|pfx)$/i ) {
            $fmt = "pkcs12";
        } else {
            $fmt = "x509";
        }
    }

    if ( $data->[0] =~ /^Certificate:/ ) {
        # If it's already been converted to text
        undef $inform;
    } elsif ( grep(/BEGIN PKCS(7|12)/, @$data) ) {
        $inform = "PEM";
        if ( $1 eq "7" ) {
            $fmt = "pkcs7";
        } elsif ( $1 eq "12" ) {
            $fmt = "pkcs12";
        }
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

        my $readcmd;
        
        if ( !defined $fmt or $fmt eq "x509" ) {
            $readcmd = "openssl x509 -noout -text -inform $inform";
        } elsif ( $fmt eq "pkcs12" ) {
            $readcmd = "openssl pkcs12 -cacerts -nokeys -inform $inform | openssl x509 -noout -text";
        } elsif ( $fmt eq "pkcs7" ) {
            $readcmd = "openssl pkcs7 -inform $inform -noout -text -print_certs";
        }

        my $pid = open2(my $readfd, my $writefd, "$readcmd") || die "Error: cannot open openssl: $!";

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
            }

        } elsif ( /X509v3 Authority Key Identifier:/ ) {
            $_ = $data->[++$i];
            if ( /^\s+keyid:(.+)$/ ) {
                $h{'auth_key_ident'} = $1;
            }

        } elsif ( /^\s+Issuer: (.+)$/ ) {
            $h{'issuer'} = $1;

        } elsif ( /^\s+Subject: (.+)$/ ) {
            $h{'subject'} = $1;

        }
    }

    $h{'ca_issuers'} = \@caissuers;

    return \%h;
}


# Returns true if either the key idents or subject/issuer are the same
sub cert_is_root_ca {
    my $cert = shift;
    my @pair1 = ('subj_key_ident', 'auth_key_ident');
    my @pair2 = ('subject', 'issuer');

    for ( (\@pair1, \@pair2) ) {
        if ( 
            defined $cert->{$_->[0]} and length $cert->{$_->[0]} and
            defined $cert->{$_->[1]} and length $cert->{$_->[1]} and
            $cert->{$_->[0]} eq $cert->{$_->[1]} 
        ) {
            print STDERR "CA data $cert->{$_->[0]} equals $cert->{$_->[1]}\n" if $VERBOSE;
            return 1;
        }
    }

    return 0;
}

