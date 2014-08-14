#!/usr/bin/perl
# is_certificate_expired.pl - checks if a certificate is expired
# Copyright (C) 2012 Peter Willis <peterwwillis@yahoo.com>

$|=1;
use strict;
use Digest::MD5;
use IPC::Open2;

push(@INC, ".");
use CertUtils;

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

die "Usage: $0 certificate [..]\n\nSet env variable VERBOSE greater than 1 for debugging\n" if @ARGV < 1;


foreach my $file ( @ARGV ) {
    main( $file );
}

exit(0);


sub main {
    my $CERT = shift;

    my $c = CertUtils->new($CERT);

    for ( $c->certificates ) {
        check_exp($c, $_);
    }
}

sub check_exp {
    my $o = shift;
    my $cert = shift;

    print "Certificate Subject: '$cert->{'subject'}'\n" if $VERBOSE;

    my ($c,$e) = ( scalar localtime($cert->{'created'}) , scalar localtime($cert->{'expires'}) );
    print "Created: $c\n" if $VERBOSE;
    print "Expires: $e\n" if $VERBOSE;

    my $time = time();
    my $timeleft = ($cert->{'expires'} - $time) || 1;

    my $dleft = sprintf("%.2f",( ( ($timeleft / 60) / 60 ) / 24 ) );


    if ( !defined $cert->{'expires'} or length $cert->{'expires'} < 1 or $cert->{'expires'} < 1 or $timeleft <= 1 ) {
        print "ERROR: Certificate ".$o->file." has expired! timeleft $timeleft dleft $dleft\n";
    } else {
        print "Certificate ".$o->file." is still valid ($dleft days until it expires)\n";
    }

    return 1;
}

