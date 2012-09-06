#!/usr/bin/perl
use strict;
use Getopt::Std;
my $TODO = "$ENV{HOME}/public_html/TODO";
my ($COMPLETED, $INCOMPLETED, $URGENT, $HTML) = (0, 0, 0, 0);
my %opts;

getopts('ciuaH', \%opts);

if ( exists $opts{h} or @ARGV and $ARGV[0] eq "--help" ) {
	print "Usage: $0 [OPTIONS]\nPrints TODO items.\n\nOptions:\n    -c\t\tPrint completed items.\n    -i\t\tPrint incomplete items\n    -u\t\tPrint urgent items\n    -a\t\tPrint all items (default)\n    -H\t\tOutput the results in HTML\n";
	exit(0);
}

# if no args whatsoever, set everything
if ( scalar(keys(%opts)) < 1 ) {
	$COMPLETED = 1;
	$INCOMPLETED = 1;
	$URGENT = 1;
} else {
	# if there were _any_ args, just set them as we see them
	if ( exists $opts{c} ) {
		$COMPLETED = 1;
	}
	if ( exists $opts{i} ) {
		$INCOMPLETED = 1;
	}
	if ( exists $opts{u} ) {
		$URGENT = 1;
	}
	if ( exists $opts{a} ) {
		$COMPLETED = 1;
		$INCOMPLETED = 1;
		$URGENT = 1;
	}
	if ( exists $opts{H} ) {
		$HTML = 1;
	}
}

my $todo = read_todo();
use Data::Dumper; print Dumper($todo);

# Read the todo, return a hash data structure with the parsed contents
sub read_todo {
	my ($fh, $current_category, $current_section, $last_item);
	my %hash;

	if ( ! open($fh, $TODO) ) {
		die "Error: couldn't open 'TODO': $!\n";
	}

	while(<$fh>){

		chomp;
		next if /^\s*?#/;

		# Category
		if ( /^(\S.+?):$/ ) {

			$hash{$1} = [ ];
			$current_category = $hash{$1};
			print STDERR "read_todo(): Found category $1\n" if (exists $ENV{VERBOSE});

		# Date/Section (start of set of entries in a category)
		} elsif ( /^([^+].+?)$/ ) {

			# $hash{"Category:$1"} = [ "TASKS", { } ];
			push( @{ $current_category }, [ $1, { } ] );
			my $cur_count = int(@{ $current_category })-1; # "1"-1 == array index 0
			$current_section = $current_category->[$cur_count];
			$last_item = undef;
			print STDERR "read_todo(): Found section $1\n" if (exists $ENV{VERBOSE});

		# Task/Item
		} elsif ( /^([+]+)([!.])?\s+(.+)$/ ) {

			my $thread_idx = length($1);
			my $state = $2;
			my $item = $3;

			if ( $state eq "." ) {
				$state = "completed";
			} elsif ( $state eq "!" ) {
				$state = "urgent";
			} else {
				$state = "default";
			}

			# Example layout:
			#   TASKS
			#   Mon Mar 17 11:21:52 EDT 2008
			#   + send e-mail to client about product
			# ... Becomes:
			# $hash{"Category:TASKS"}->{"Section:Mon Mar 17 11:21:52 EDT 2008"}->{1}->[0]->{"item"} = "send e-mail to client about product";

			# FIXME: Fix this so it stores sub-items in order under each item it's a sub of
			push ( @{ @{$current_section}->[1]->{$thread_idx} } , { "state" => $state, "item" => $item } );
			$last_item = $item;
			print STDERR "read_todo(): Thread $thread_idx: Found item $item (state $state)\n" if (exists $ENV{VERBOSE});

		}
	}

	close($fh);

	return(\%hash);
}

