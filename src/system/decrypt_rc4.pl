#!/usr/bin/perl

use strict;

#my $string = "4869d36ab0d48ce349b735d39833fb578f10098bc1e08656be77d527cfcfed74456c5a4dcaf5f6f56b4d616bbcc1639bf9bc15480f46fe70250aa46d5457b3";
my $string = $ARGV[0] || die "Usage: $0 encrypted_url\n";
my $key = "sdf883jsdf22";
my $text = pack("H*", $string);

print decrypt_rc4($key, $text), "\n";

sub decrypt_rc4 {
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

