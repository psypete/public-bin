#!/usr/bin/perl

use strict;
use Digest::MD5;
$|=1;

if ( @ARGV < 1 ) {
	die <<EOF
Usage: $0 [OPTIONS] [FILE ..] [DIR ..]

Based on files and directories passed, each file found will
be MD5 checksum'd and a list is generated. Based on options
used you can list unique files, duplicate files, etc.

Options:
  -u			List unique files
  -d			List duplicate files
EOF
}

my @arglist;
my $HASH;
my %OPTIONS;

for ( @ARGV ) {
	if ( /^-u$/ ) {
		$OPTIONS{u} = 1;
	} elsif ( /^-d$/ ) {
		$OPTIONS{d} = 1;
	} else {
		push @arglist, $_;
	}
}

for ( @arglist ) {
	print_dups($_);
}

sub print_dups {
	my $file = shift;
	my @LIST = $file;
	for ( @_ ) {
		my @FILES;
		my @_LIST = @LIST;
		@LIST = ();
	
		foreach my $file ( @_LIST ) {
			if ( -f $file ) {
				push @FILES, $file;
			} elsif ( -d $file ) {
				opendir(DIR, $file) || next;
				my @files = map { "$file/$_" } grep(!/^\.\.?$/,readdir(DIR));
				closedir(DIR);
	
				for (@files) {
					if ( -f $_ ) {
						push @FILES, $_;
					} elsif ( -d $_ ) {
						push @LIST, $_;
					}
				}
			}
		}
	
		foreach my $file (@FILES) {
			my $md5;
			if ( ! open(FILE, "<$file") ) {
				next;
			}
			binmode(FILE);
			$md5 = Digest::MD5->new->addfile(*FILE)->hexdigest;
			close(FILE);
	
			$HASH->{$md5}->{$file}++;
		}
	}
	
	my ($dupes, $dupes_s, $unique, $unique_s);
	
	while ( my ($k,$v) = each %{$HASH} ) {
		if ( $OPTIONS{d} ) {
			if ( int(%{$v}) > 1 ) {
				#$dupes++;
				for ( keys %{$v} ) {
					$dupes++;
					$dupes_s += -s $_;
				}
			}
		}
		if ( $OPTIONS{u} ) {
			if ( int(%{$v}) <= 1 ) {
				#$unique++;
				for ( keys %{$v} ) {
					$unique++;
					$unique_s += -s $_;
				}
			}
		}
	}
	
	if ( $OPTIONS{d} ) {
		print "$file:\n";
		print "  Duplicates:  $dupes\n";
		print "  Size of duplicate files: " . int($dupes_s/1024) . "k\n";
	}
	
	if ( $OPTIONS{u} ) {
		print "$file:\n";
		print "  Unique:      $unique\n";
		print "  Size of unique files:    " . int($unique_s/1024) . "k\n";
	}
}

