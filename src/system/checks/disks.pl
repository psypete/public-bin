#!/usr/bin/perl -w
use strict;
use Getopt::Std;

my %opts;
getopts('b:i:h', \%opts);

my $block_threshold_percent = exists $opts{'b'} ? $opts{'b'} : "95";
my $inode_threshold_percent = exists $opts{'i'} ? $opts{'i'} : "95";
chomp(my $hostname = `hostname`);

if ( exists $opts{'h'} ) {
    die "Usage: $0 OPTIONS [FILESYSTEM|MOUNT ..]\n\nOptions:\n\t-b NUM\t\tPercentage of block threshold (default: $block_threshold_percent)\n\t-i NUM\t\tPercentage of inode threshold (default: $inode_threshold_percent)\n";
}

main();
exit(0);

sub main {
    my $df = run_df();
    my @report;

    foreach my $fs ( @$df ) {
        if ( @ARGV and !grep(/^$fs->{filesystem}$/,@ARGV) and !grep(/^$fs->{'mounted on'}$/,@ARGV) ) {
            next;
        }

        if ( $fs->{'blocks'}->{'capacity'} >= $block_threshold_percent ) {
            push( @report, disk_report("WARNING: filesystem ".$fs->{'filesystem'}." is at ".$fs->{'blocks'}->{'capacity'}."% block capacity (".read_block($fs).")") );
        }

        if ( $fs->{'inodes'}->{'iuse%'} >= $inode_threshold_percent ) {
            push( @report, disk_report("WARNING: filesystem ".$fs->{'filesystem'}." is at ".$fs->{'inodes'}->{'iuse%'}."% inode capacity (".$fs->{'inodes'}->{'iused'}."/".$fs->{'inodes'}->{'inodes'}.")") );
        }
    }

    if ( @report ) {
        print STDERR "$0 found the following errors on $hostname:\n\n";
        display_report(@report);
        exit(1);
    }
}

sub run_df {
    my @df;
    my @posix_df = map { chomp; $_ } `df -P 2>/dev/null`;
    my @posix_df_i = map { chomp; $_ } `df -i 2>/dev/null`;
    my @headers = split(/\s+/, shift @posix_df, 6);
    my @inode_headers = split(/\s+/, shift @posix_df_i, 6);

    for ( my $i=0; $i<@posix_df; $i++ ) {
        my @line = map { s/\%//g; $_ } split(/\s+/, $posix_df[$i], 6);
        my @inode_line = map { s/\%//g; $_ } split(/\s+/, $posix_df_i[$i], 6);

        push( @df, { 'filesystem' => $line[0], 'mounted on' => $line[5], 
                'blocks' => {
                    map { lc $headers[$_] => lc $line[$_] } 1..4
                }, 'inodes' => {
                    map { lc $inode_headers[$_] => lc $inode_line[$_] } 1..4
                }
            } );
    }

    return \@df;
}

sub read_block {
    my $self = shift;
    my $blocksiz = 1024;
    my @ext = qw(k m g t p);
    my @blocks = grep( /blocks/i, keys %{$self->{'blocks'}} );
    my $string = "unknown";
    my $ext;

    for ( @blocks ) {
        if ( /^(.+)-blocks/i ) {
            my $blk = $1;
            if ( $blk =~ /1k/i ) {
                $blocksiz = 1024;
            } elsif ( $blk =~ /1m/i ) {
                $blocksiz = 1048576;
            } elsif ( $blk =~ /1g/i ) {
                $blocksiz = 1073741824;
            } else {
                $blocksiz = $blk;
            }
        }

        my $free = $self->{'blocks'}->{'available'};

        $string = ($free*$blocksiz);

        my $i=0;
        do {
            $string = ($string / 1024);
            $ext = $ext[$i++];
        } until ( $string < 1000 );
            
    }

    return sprintf("%0.1f%s free", $string, uc $ext);
}

sub disk_report {
    return $_[0]
}

sub display_report {
    for ( @_ ) {
        print STDERR "\t$_\n";
    }
}

