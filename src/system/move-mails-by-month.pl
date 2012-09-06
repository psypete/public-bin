#!/usr/bin/perl
# move-mails-by-month.pl - Guess.
# Copyright (C) 2008-2010 Peter Willis <peterwwillis@yahoo.com>
# 
# this may be faster as a shell script but whatever. internal grep
# clearly wins out here as the external grep runs take ~4x as long.

use strict;
use Date::Manip;
use File::Copy;
use File::Find;

my $homedir = (getpwuid($<))[7];
my $ROOTDIR = "$homedir/Maildir";
my $OLDDIR = "$ROOTDIR/cur";
my $MONTH;

die "Usage: $0 MONTH [..]\nMoves e-mails dated in MONTH to a folder INBOX-YEAR.MONTH in $ROOTDIR\n" if @ARGV != 1;

main();
exit(0);


sub main {

    foreach $MONTH (@ARGV) {

        if ( ! -d $OLDDIR ) {
            die "Error $OLDDIR does not exist (invalid Maildir?)\n";
        }

        find( { wanted => \&native_perl_grep, no_chdir => 1 }, $OLDDIR );

    }
}

#open(PIPE, "grep \"^Date:\" -m 1 -r \"$OLDDIR\" |") or die "Cannot open pipe: $!\n";
#while (<PIPE>) {


sub external_grep {
    my $file = $_;
    return if (! -f $file);
    # Make sure you specify "-i", because Dell sents 'date: ' in its mails (fail!)
    my $output = `grep -h -m 1 -i -e "^Date: .*" "$file"`;
    if ( ($?>>8) != 0 ) {
        #print STDERR "Error: grep returned non-zero status (\"$output\"); skipping file $file\n";
        return;
    }
    chomp $output;
    $output =~ s/^Date:\s+//g;

    if ( $output !~ /^\s*$/ ) {
        movemail($file, $output);
    }
}

sub native_perl_grep {
    my $file = $_;
    my $fd;
    if ( ! open($fd, "<$_") ) {
        print STDERR "Error: Could not open $_: $!; skipping\n";
        return;
    }
    while ( <$fd> ) {
        s/(\015\012|\n)$//g;
        last if $_ eq "";

        # Ignore case because Dell sends 'date:'
        if ( /^Date:\s+(.+)$/i ) {
            close($fd); # we don't need it anymore
            undef $fd; # just incase?
            movemail($file, $1);
            last;
        }
    }
    close($fd) if (defined $fd);
}



sub movemail {
    my ($file, $date) = @_;

    my $ndate = ParseDate($date);
    my $abbrev_month = UnixDate($ndate,'%b');
    my $full_month = UnixDate($ndate,'%B');
    my $NEWDIR = UnixDate($ndate, "INBOX-%Y.%b");

    if ( lc $abbrev_month eq $MONTH or lc $full_month eq $MONTH ) {
        print STDERR "Moving $file to $NEWDIR\n";

        # Make the new folder if it doesn't exist
        if ( ! -d "$ROOTDIR/.$NEWDIR" ) {
            print STDERR "Info: Creating new maildir folder \"$ROOTDIR/.$NEWDIR\"\n";
            system("maildirmake", "-f", $NEWDIR, $ROOTDIR);
            if ( ( $? >> 8 ) != 0 ) {
                print STDERR "Error: maildirmake returned non-zero status; skipping message\n";
                return;
            }
        }

        if ( ! -d "$ROOTDIR/.$NEWDIR/cur" ) {
            print STDERR "Error: invalid maildir folder \"$ROOTDIR/.$NEWDIR\"\n";
            return;
        }

        if ( ! move($file, "$ROOTDIR/.$NEWDIR/cur") ) {
            die "Error: could not move $file to $ARGV[1] ($!)\n";
        }
    }
}

