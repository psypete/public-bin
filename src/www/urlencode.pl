#!/usr/bin/perl
$|=1;
for (@ARGV) {
    s/(.)/printf("%%%x",ord($1))/eg
}
print "\n";
