#!/usr/bin/perl -w
# encsh.pl - encrypt a shell, perl or python script
# Copyright (C) 2009 Peter Willis <peterwwillis@yahoo.com>
#
# This script has a single basic aim: secure a script so that a malicious user
# cannot determine its source if found on a disk. It does nothing to protect
# the memory used to later execute the script or prevent someone from
# eavesdropping on the execution. However it does make it less likely someone
# will find the decrypted form on a disk as the decrypted form only exists in
# a pipe and in the memory of the interpreter.
#
# The use is pretty simple: pass encsh.pl a script and it will be encrypted and
# placed in a wrapper.
# 
# Depends on perl on the target system until I get bored enough to make a
# compiled wrapper. If you complete that functionality please e-mail me a patch.
#
# This is merely proof of concept code. It's shit. But it works.
#

use strict;
use MIME::Base64;
$|=1;

die "Usage: $0 SCRIPT\nEncrypts SCRIPT for later use.\nPossible scripts: shell, perl, python\n" unless defined $ARGV[0];

my($p1,$p2,$fh1,$fh2,$script,$interp);
my $rc4me=q|sub rc4{my($t,$k,@k,@s,$y,$s,$x,$c);$t='';$k=substr($_[0],0,16);@k=unpack'C*',$k;@s=(0..255);$y=(0);for$x(0..255){$y=($k[$x%@k]+$s[$x]+$y)%256;@s[$x,$y]=@s[$y,$x]}$s=\@s;$x=0;$y=0;for$c(unpack'C*',$_[1]){$x=($x+1)%256;$y=($s->[$x]+$y)%256;@$s[$x,$y]=@$s[$y,$x];$b.=(pack('C',$c^=$s->[($s->[$x]+$s->[$y])%256]));};$b};|;
my $payload = qq/\$|=1;use MIME::Base64;\@ARGS=map{"\\"\$_\\""}\@ARGV;system('stty -echo');print STDERR 'Enter decryption key: ';\$p=<STDIN>;chomp \$p;system('stty echo');print STDERR chr(10);open(\$fh1,\$0);open(\$fh2,"| \$INTERP \@ARGS");<\$fh1>;<\$fh1>;<\$fh1>;<\$fh1>;\$raw=decode_base64(join('',<\$fh1>));print \$fh2 rc4(\$p,\$raw);close \$fh1;close \$fh2;wait();/;

system('stty -echo');
print STDERR "Enter a password to encrypt with: ";
$p1=<STDIN>;
chomp$p1;
print STDERR "\nEnter the password again: ";
$p2=<STDIN>;
chomp$p2;
system('stty echo');
print STDERR "\n";
die "Error: password did not match\n" unless $p1 eq $p2;

open($fh1,"<$ARGV[0]")||die "Couldn't open script $ARGV[0]: $!\n";
$script = join('', <$fh1>);
close($fh1);

if ( $script =~ /^#!(\S+sh\s)/i ) {
    # Try to append '-s' onto the end of shell scripts to preserve the arguments
    $interp = $+;
    $interp =~ s/\s$//g;
    $interp .= " -s";
} elsif ( $script =~ /^#!(\S+)/ ) {
    $interp = $+;
} else {
    die "Error: script $ARGV[0] does not have a shebang\n";
}

open($fh2,">$ARGV[0].crypt")||die "Couldn't open output $ARGV[0].crypt: $!\n";
print $fh2 qq|#!/usr/bin/perl\n$rc4me\n\$INTERP="$interp";$payload\n__END__\n|;

eval $rc4me;
print $fh2 encode_base64( rc4($p1,$script), '');

close($fh2);

chmod(0755, "$ARGV[0].crypt");

