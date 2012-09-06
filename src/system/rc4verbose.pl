#!/usr/bin/perl
# rc4me.pl - rc4 encryption, stolen from Net::SSH::Perl::Crypt::RC4
# Copyright (C) 2009 Peter Willis <peterwwillis@yahoo.com>
#
use strict;

if ( @ARGV != 1 ) {
    die "Usage: $0 KEY\n";
}

print rc4($ARGV[0], <STDIN>);

sub rc4 {
        my ($key, $text) = @_;

        my $blocksize = 8;
        my $keysize = 16;
        my $trans = '';
        my ($x,$y,$seed,$tmp);

        $key = substr($key, 0, $keysize);
        my @k = unpack 'C*', $key;
        my @seed = (0..255);
        $y = (0);
        my $actual_keysize = @k;
        print STDERR "Initializing the seed. (actual_keysize $actual_keysize)\n";
        for my $current_byte (0..255) {
                print STDERR " current_byte ($current_byte)\n";
                my $key_position = $current_byte % $actual_keysize;
                print STDERR "   key_position ($key_position) = current_byte ($current_byte) % actual_keysize ($actual_keysize)\n";
                my $mod1 = $k[$key_position] + $seed[$current_byte] + $y;
                print STDERR "   mod1 ($mod1) = key[key_position $key_position] ($k[$key_position]) + seed[current_byte $current_byte] ($seed[$current_byte]) + y ($y)\n";
                $y = $mod1 % 256;
                print STDERR "   y ($y) = mod1 ($mod1) % 256\n";
                $tmp = $seed[$current_byte];
                $seed[$current_byte] = $seed[$y];
                print STDERR "   seed[current_byte $current_byte] ($tmp) = seed[y $y] ($seed[$y])\n";
                $seed[$y] = $tmp;
                print STDERR "   seed[y $y] ($seed[$current_byte]) = seed[current_byte $current_byte] ($tmp)\n";
        }
        print STDERR "Seed initialized.\n\n";
        $seed = \@seed;
        $x = 0;
        $y = 0;
        my @unpacked_text = unpack 'C*', $text;

        print STDERR "Encrypting text.\n";
        for ( my $uc_i = 0; $uc_i < @unpacked_text; $uc_i++ ) {
                my $c = $unpacked_text[$uc_i];
                print STDERR " c ($c) = unpacked_text[uc_i $uc_i] ($c)\n";
                my $oldx = $x;
                $x = ($x + 1) % 256;
                print STDERR "   x ($x) = (x $oldx + 1) % 256\n";
                my $sxy = $seed->[$x] + $y;
                print STDERR "   sxy = seed[x $x] ($seed->[$x]) + y $y\n";
                $y = $sxy % 256;
                print STDERR "   y ($y) = sxy ($sxy) % 256\n";
                $tmp = $seed->[$x];
                $seed->[$x] = $seed->[$y];
                print STDERR "   seed[x $x] ($tmp) = seed[y $y] ($seed->[$x])\n";
                $seed->[$y] = $tmp;
                print STDERR "   seed[y $y] ($seed->[$x]) = seed[x $x] ($tmp)\n";
                my $sxsy = $seed->[$x] + $seed->[$y];
                print STDERR "   sxsy ($sxsy) = seed[x $x] ($seed->[$x]) + seed[y $y] ($seed->[$y]\n";
                my $newseed = $sxsy % 256;
                print STDERR "   newseed ($newseed) = sxsy ($sxsy) % 256\n";
                my $ec = $c ^ $seed->[ $newseed ];
                print STDERR "   ec ($ec) = c ($c) ^ seed[newseed $newseed] $seed->[$newseed]\n";
                $trans .= pack('C', $ec);
                $c = $ec;
        }
        print STDERR "Text encrypted.\n\n";

        return($trans);
}

