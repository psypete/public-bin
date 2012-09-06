#!/usr/bin/perl

# TODO:
#   * add color

use strict;
use Time::Local;
use Data::Dumper;

my ($TODO, $h, %o);

if ( $ARGV[0] eq "-h" or $ARGV[0] eq "--help" ) {
	die "Usage: $0 OPTION\nValid options:\n  --html\t\tHTML output\n  --text\t\tText output [default]\n";
}

$TODO = "$ENV{HOME}/public_html/TODO";
$h = read_todo($TODO);

# Set default options
for ( qw(displaycomplete displaynormal displaypriority) ) {
	if ( !exists $o{$_} ) {
		$o{$_}++;
	}
}

$o{displaycomplete} = 0;

if ( $ARGV[0] eq "--html" ) {
	display_html($h, \%o);
} else {
	display_text($h, \%o);
}


# read TODO file
sub read_todo {
	my $todo = shift;
	my @F;
	my %H;
	my $CATEGORY;
	my $TIMESTAMP;

	open(TODO, "<$todo");
	@F = map { chomp $_; $_ } grep(!/^\s*#/, <TODO>); # Skip comments
	close(TODO);

	for ( @F ) {
		if ( /^([^+].+):$/ ) { # doesn't start with +, ends with :
			$CATEGORY = $1;
			$H{$CATEGORY} = { };
		} elsif ( /^(\w+)\s+(\w+)\s+(\d+)\s+(\d+):(\d+):(\d+)\s+(\w+)\s+(\d+)$/ ) { # DAY MONTH DATE HOUR:MINUTE:SECOND TIMEZONE YEAR
			my %MONTHS = ( "Jan" => 0, "Feb" => 1, "Mar" => 2, "Apr" => 3, "May" => 4, "Jun" => 5, "Jul" => 6, "Aug" => 7, "Sep" => 8, "Oct" => 9, "Nov" => 10, "Dec" => 11 );
			my ($DAY, $MONTH, $DATE, $HOUR, $MINUTE, $SECOND, $TIMEZONE, $YEAR) = ($1, $2, $3, $4, $5, $6, $7, $8);
			my $MONTH_N = $MONTHS{$MONTH};
			$TIMESTAMP = timelocal($SECOND, $MINUTE, $HOUR, $DATE, $MONTH_N, $YEAR);
			$H{$CATEGORY}->{$TIMESTAMP} = [ ];
		} elsif ( /^([+\!.]+?.+)$/ ) { # starts with +
			my ($attr, $text) = split(/\s+/, $1, 2);
			my ($complete, $highpriority) = (0, 0);
			if ( $attr =~ s/\.$//g ) {
				$complete++;
			} elsif ( $attr =~ s/\!$//g ) {
				$highpriority++;
			}
			my $threadnum = length($attr);
			push( @{ $H{$CATEGORY}->{$TIMESTAMP} }, { "thread" => $threadnum, "priority" => $highpriority, "complete" => $complete, "text" => $text } );
		}
	}

	# Return a sorted list where under each category is an array consisting of pairs of dates and anonymous arrays
	my @sorted_aref;
	my @times = sort { $b <=> $a } keys %{ $H{$CATEGORY} };
	for ( @times ) {
		push @sorted_aref, ( $_, $H{$CATEGORY}->{$_} );
	}
	$H{$CATEGORY} = \@sorted_aref;

	return(\%H);
}

# display_text($h, displaycomplete => 0)
# Options:
#    displaycomplete
#    displaynormal
#    displaypriority
sub display_text {
	my $h = shift;
	my $o = shift;
	my $buffer;

	while ( my ($CATEGORY,$aref) = each %$h ) {
		if ( ref($aref) ne "ARRAY" ) {
			next;
		}
		for ( my $i=0; $i<@$aref; $i+=2 ) {
			my $DATE = $aref->[$i];
			my @items = @{ $aref->[$i+1] };
			my $tmpbuffer;

			foreach my $hashref ( @items ) {
				# Should we display the item?
				if ( ! check_display($hashref, $o) ) {
					next;
				}
				$tmpbuffer .= "    " .
				    ("-" x $hashref->{thread}) . " " .
				    ($hashref->{complete} ? "(done) " : "") .
				    ($hashref->{priority} ? "!!! " : "") .
				    $hashref->{text} .
				    ($hashref->{priority} ? " !!!" : "") .
				    "\n";
			}

			if ( length($tmpbuffer) > 0 ) {
				$tmpbuffer = "  Date: " . scalar(localtime($DATE)) . "\n" . $tmpbuffer;
			}

			if ( length($tmpbuffer) > 0 ) {
				$buffer .= $tmpbuffer . "\n";
			}
		}
	}

	print $buffer;
}

# display_html($h, displaycomplete => 0)
# Options:
#    displaycomplete
#    displaynormal
#    displaypriority
sub display_html {
	my $h = shift;
	my $o = shift;
	my $buffer;

	print "<html>\n<body>\n";

	while ( my ($CATEGORY,$aref) = each %$h ) {
		if ( ref($aref) ne "ARRAY" ) {
			next;
		}
		for ( my $i=0; $i<@$aref; $i+=2 ) {
			my $DATE = $aref->[$i];
			my @items = @{ $aref->[$i+1] };
			my $tmpbuffer;
			my $oldthread = 1;

			for ( my $i=0; $i<@items; $i++ ) {
				my $hashref = $items[$i];

				# Should we display the item?
				if ( ! check_display($hashref, $o) ) {
					next;
				}

				if ( $hashref->{thread} > $oldthread ) { # old was 2, new is 3: new sub-item
					$tmpbuffer .= "<ol>\n";
				} elsif ( $hashref->{thread} < $oldthread ) { # old was 3, new is 2
					$tmpbuffer .= "</ol>\n";
				}

				$tmpbuffer .= "<li><font size=1>" .
					($hashref->{priority} ? "<font color='red'>" : "") .
					($hashref->{complete} ? "<s>" : "") .
					$hashref->{text} .
					($hashref->{complete} ? "</s>" : "") .
					($hashref->{priority} ? "</font>" : "") .
					"</font></li>\n";

				$oldthread = $hashref->{thread};

				if ( ($i+1) == @items and $oldthread != 1 ) {
					$tmpbuffer .= "</ol>\n";
				}

			}

			# Add the date to the beginning of the items
			if ( length($tmpbuffer) > 0 ) {
				$tmpbuffer = "<br>\n<b>Date: " . scalar(localtime($DATE)) . "</b><br>\n" .
				"<ol>" . $tmpbuffer . "</ol>" . "<br>\n";
			}

			if ( length($tmpbuffer) > 0 ) {
				$buffer .= $tmpbuffer . "<hr>\n";
			}
		}
	}

	print $buffer;

	print "</body>\n</html>\n";
}

sub check_display {
	my $item = shift;
	my $o = shift;

	if ( $o->{displaycompete} & (!$item->{complete}) ) {
		return(0);
	} elsif ( (!$o->{displaycomplete}) & $item->{complete} ) {
		return(0);
	}

	if ( $item->{priority} & (!$o->{displaypriority}) ) {
		print STDERR "Priority error\n";
		return(0);
	}

	#if ( $o->{displaypriority} & (!$item->{priority}) ) {
	#	return(0);
	#}

	return(1);
}


