#!/usr/bin/perl
# rc4me.pl - rc4 encryption, stolen from Net::SSH::Perl::Crypt::RC4
# Copyright (C) 2009 Peter Willis <peterwwillis@yahoo.com>
#
use strict;

if ( @ARGV != 1 ) {
    die "Usage: $0 KEY\n";
}

print rc4($ARGV[0], join('',<STDIN>));

sub rc4 {
        my ($key, $text) = @_;

        my $blocksize = 8;
        my $keysize = 16;
        my $trans = '';
        my ($x,$y,$s);

        $key = substr($key, 0, $keysize);
        my @k = unpack 'C*', $key;
        my @s = (0..255);
        $y = (0);
        for my $x (0..255) {
                $y = ($k[$x % @k] + $s[$x] + $y) % 256;
                @s[$x, $y] = @s[$y, $x];
        }
        $s = \@s;
        $x = 0;
        $y = 0;

        for my $c (unpack 'C*', $text) {
                $x = ($x + 1) % 256;
                $y = ( $s->[$x] + $y ) % 256;
                @$s[$x, $y] = @$s[$y, $x];
                $trans .= pack('C', $c ^= $s->[( $s->[$x] + $s->[$y] ) % 256]);
        }

        return($trans);
}

