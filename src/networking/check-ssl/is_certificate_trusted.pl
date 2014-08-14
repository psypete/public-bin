#!/usr/bin/perl
# is_certificate_trusted.pl - checks if a certificate is trusted by a root CA
# Copyright (C) 2012 Peter Willis <peterwwillis@yahoo.com>

$|=1;
use strict;
use Digest::MD5;
use IPC::Open2;

push(@INC, ".");
use CertUtils qw(certs_linked);

my $VERBOSE = exists $ENV{VERBOSE} ? $ENV{VERBOSE} : 0;
$CertUtils::VERBOSE = $VERBOSE;

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

die "Usage: $0 certificate ca-certificate-text-dir\n\nSet env variable VERBOSE greater than 1 for debugging\n" if @ARGV != 2;

my $CERT = shift @ARGV;
my $CACERTDIR = shift @ARGV;


my $r = main();
if ($r != 0) {
    die "Error: Could not find Certificate Authority or a certificate was expired\n";
    exit($r);
}

exit(0);


sub main {
    my $e = 0;

    my @cacerts = map {
        my $c = CertUtils->new($_);

        for ( $c->certificates ) {
            $c->check_exp($_) || $e++;
        }

        $c->certificates

    } glob("$CACERTDIR/*");

    my $c = CertUtils->new($CERT);
    my $cert = ($c->certificates)[0];

    print "Certificate Subject: '$cert->{'subject'}'\n" if $VERBOSE;

    $c->check_exp($cert) || $e++;

    die "Error: this is a CA certificate or a self-signed certificate!\n" if CertUtils::certs_linked($cert);
        
    my @issuers;
    my $counter = 0;

    # Loop over any CA Issuers recursively, resolving the chain of trust

    my @uris = exists $cert->{'ca_issuers'} ? @{ $cert->{'ca_issuers'} } : ();
    my @old = ( $cert );
    while ( @uris ) {

        my @tmpissuer;
        my @tmpuris = @uris;
        @uris = ();

        while ( @tmpuris ) {
            my $cai = shift @tmpuris;
            if ( $cai =~ /^http/i ) {
                my $tmpcert = CertUtils->new;
                my @tmpcerts = $tmpcert->download_issuer($cai)->certificates;

                for ( @tmpcerts ) {
                    $tmpcert->check_exp($_);

                    push(@tmpissuer, $_);
                    print "Found Issuer Subject: '$_->{'subject'}'\n" if $VERBOSE;
                    last;
                }
            }
        }

        foreach my $tmpissuer ( @tmpissuer ) {

            # Check if the previous cert is chained to the new one
            foreach my $old ( @old ) {

                if ( certs_linked( $tmpissuer, $old ) ) {
                    # Now find out if new cert is a CA, or has more links in the chain
                    if ( certs_linked($tmpissuer) ) {
                        print STDERR "Found root CA $tmpissuer->{'subject'}\n" if $VERBOSE;
                    }
                }

                # The previous cert wasn't chained to this one? Hacker!!
                else {
                    die "Error: the cert isn't chained to the next one found!";
                }
            }

        }

        push( @uris, map { exists $_->{'ca_issuers'} ? @{$_->{'ca_issuers'}} : () } @tmpissuer );

        @old = @tmpissuer;
        $counter++;
    }


    my $match_ca = 0;

    # We have no more links in the chain, so check the CA root files
    # to see if one of them matches the current one's auth key or issuer
    foreach my $old (@old) {       

        foreach my $ca ( @cacerts ) {

            if ( certs_linked( $ca, $old ) ) {
                $match_ca = 1;
            }

            if ( $match_ca ) {
                print "Root CA subject: '$ca->{'subject'}'\n" if $VERBOSE;
    
                if ( certs_linked($ca) ) {
                    print "Found root CA for $CERT: $ca->{'subject'}\n";
                    return 0;
                } else {
                    die "Root CA isn't a root CA!";
                }
            }

        }

        print STDERR "Error: new cert '$old->{'subject'}' does not match old cert '$old->{'issuer'}', and there's no more chain to go up!\n" if $VERBOSE;
        last;

    }

    return $e;
}


