#!/usr/bin/perl

$|=1;
use strict;
use Date::Parse;

my $NOWSEC = time();

for my $file ( glob("certs/*.txt") ) {

    my $p=0;
    my (@data, $data);
    my ($subject, $issuer, $notafter);

    open(F,"<$file")||die "Error: cannot open $file: $!";
    @data = <F>;
    close(F);
    $data = join('', @data);

    if ( $data =~ /Subject: (.+?)(\r|\n)/ ) {
        $subject = $1;
    }

    if ( $data =~ /Issuer: (.+?)(\r|\n)/ ) {
        $issuer = $1;
    }

    if ( $data =~ /Not After : (.+?)(\r|\n)/ ) {
        $notafter = Date::Parse::str2time($1);
    }

    if ( $subject eq $issuer ) {
        my $cn = "";
        if ( /CN=([a-z0-9-\.]+)/i ) {
            $cn = $1;
        }
        print "CERT $file is self-signed (subject=issuer)\n";
        $p++;
    } else {

        my ($o, $r);
        if ( $subject =~ /CN=([a-z0-9-\.]+)/i ) {
            $_ = $1;
            s/\.$//g;
            if ( /^.*[a-z].*$/i ) {
                $o = $_;
                $r = s/\.//g;
                print "CERT $file might not be self-signed ($o)\n" if $r >= 2;
                $p++;
            }
        }
        print "CERT $file is self-signed ($o)\n" unless $p;
    }

    if ( $notafter <= $NOWSEC ) {
        print "CERT $file has expired\n";
    }

}
