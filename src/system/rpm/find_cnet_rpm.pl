#!/usr/bin/perl
# find_cnet_rpm.pl - find an rpm on cnet's network
# Copyright (C) 2009 Peter Willis <pwillis@cbs.com>
# 
# Give it a package name and an optional architecture and 

use strict;
use XML::Parser;

my $MATCH_ANY_ARCH = 0;
my $MATCH_REGEX = 0;
my $SYSLIST = "$ENV{HOME}/syslist.xml";
my @ARGS;
for ( my $i=0; $i<@ARGV; $i++ ) {
    if ( $ARGV[$i] =~ /^--?a/ ) {
        $MATCH_ANY_ARCH = 1;
    } elsif ( $ARGV[$i] =~ /^--?v/ ) {
        $ENV{VERBOSE} = 1;
    } elsif ( $ARGV[$i] =~ /^--?(e|regex)$/ ) {
        $MATCH_REGEX = 1;
    } else {
        push @ARGS, $ARGV[$i];
    }
}

if ( ! @ARGS ) {
    die "Usage: $0 [OPTIONS] PACKAGE [ARCH]\nOptions:\n  -a,--any\t\t\tMatch any architecture\n  -v,--verbose\t\t\tVerbose output\n  -e,--regex\t\t\tMatch package based on regular expression\nExample: $0 -e \"glue2port.*cnet-ruby-libxml\" 64el5\n";
}

my $PKG = shift @ARGS;
my $ARCH = shift @ARGS;

if ( not $MATCH_REGEX ) {
    $PKG = "^$PKG\$";
}

# Find the OS

my $os = `cat /etc/redhat-release`;
chomp $os;

#my $arch = `rpm --eval '\%{_arch}'`;
my $arch = `uname -m`;
chomp $arch;

if ( ! defined $ARCH ) {
    if ( $os =~ /CentOS release 5/ or $os =~ /Red Hat.* release 5/ ) {
        $ARCH = "el5";
    } elsif ( $os =~ /CentOS release 4/ or $os =~ /Red Hat.* release 4/ ) {
        $ARCH = "el4";
    } elsif ( $os =~ /CentOS release 3/ or $os =~ /Red Hat.* release 3/ ) {
        $ARCH = "el3";
    }

    # Find 64-bit
    if ( $arch =~ /x86_64/ ) {
        $ARCH = "64" . $ARCH;
    }
}

print STDERR "INFO: Using architecture $ARCH (OS \"$os\", arch \"$arch\")\n" if $ENV{VERBOSE};

# Download syslist.xml if necessary

#if ( ! -r $SYSLIST ) {
#print STDERR "INFO: No syslist.xml found, grabbing svn url http://svn.cnet.com/network/metadata/metadata/trunk/syslist.xml\n" if $ENV{VERBOSE};
    open(SYSLIST, ">$SYSLIST") || die "Error: could not write $SYSLIST: $!\n";
    open(PIPE, "svn cat http://svn.cnet.com/network/metadata/metadata/trunk/syslist.xml |") || die "Error: could not open svn pipe: $!\n";
    while ( <PIPE> ) {
        print SYSLIST $_;
    }
    close(PIPE);
    close(SYSLIST);
#}

# Parse the XML for the 'path' of the basename/package

my ($x_syslist, $x_package, $x_rcs, $path);

my $xml = new XML::Parser(Style => "Tree")->parsefile($SYSLIST) || die "Error: could not parse xml: $!\n";

for ( my $i=0; $i < @$xml; $i++ ) {
    if ( $xml->[$i] eq "syslist" ) {
        $x_syslist = $xml->[$i+1];
        last;
    }
}

if ( !defined $x_syslist ) {
    die "Error: could not find 'syslist' in xml (bad XML data? try removing syslist.xml and running the command again)\n";
}

for ( my $i=0; $i < @$x_syslist; $i++ ) {
    if ( $x_syslist->[$i] eq "system" and $x_syslist->[$i+1]->[0]->{'basename'} =~ /$PKG/ ) {
        $x_package = $x_syslist->[$i+1];
        last;
    }
}

if ( !defined $x_package ) {
    die "Error: could not find package/basename in xml (bad XML data or package/basename does not exist)\n";
}

for ( my $i=0; $i < @$x_package; $i++ ) {
    if ( $x_package->[$i] eq "cvs" or $x_package->[$i] eq "svn" ) {
        $x_rcs = $x_package->[$i+1];
        last;
    }
}

if ( !defined $x_rcs ) {
    die "Error: found package/basename but no RCS found (bad XML data or possibly not in cvs or svn?)\n";
}

for ( my $i=0; $i < @$x_rcs; $i++ ) {
    if ( $x_rcs->[$i] eq "path" ) {
        $path = $x_rcs->[$i+1]->[2];
        last;
    }
}

if ( !defined $path ) {
    die "Error: could not find path.\n";
}

# Get the list of RPMs

print STDERR "INFO: Checking URL http://rpm.cnet.com/rpm/$path/?C=M;O=A\n" if $ENV{VERBOSE};
open(PIPE, "wget -q -O - http://rpm.cnet.com/rpm/$path/?C=M;O=A |") || die "Error: could not open pipe to wget: $!\n";
while ( <PIPE> ) {
    chomp;
    if ( /href="([^"]+)"/ ) {
        my $url = $1;
        my $opkg = $PKG;
        $opkg =~ s/^\^//g if not $MATCH_REGEX;
        $opkg =~ s/\$$//g if not $MATCH_REGEX;
        if ( $url =~ /^$opkg.+\..+\.rpm$/ ) {
            if ( $MATCH_ANY_ARCH or $url =~ /\_$ARCH\..+\.rpm$/ ) {
                print "http://rpm.cnet.com/rpm/$path/$url\n";
            }
        }
    }
}
close(PIPE);

