#!/usr/bin/perl
use strict;
use POSIX;
use Time::Local;
use Data::Dumper;
use Getopt::Std;

my (%table, @rrds, %opts);
my $chart_type = "lc";
my $chart_size = "1000x300";
my $url = "http://chart.apis.google.com/chart?cht=$chart_type&chs=$chart_size";
my @months = map { POSIX::strftime("%B", 0, 0, 0, 1, $_, 1980) } 0..11;
my %monthsnum = map { $months[$_] => $_ } 0..11;

getopts('s:e:r:C:', \%opts);

# By default, start at the beginning of unix time (lolz)
my $start = exists $opts{'s'} ? "-s $opts{s}" : "-s 19800101";
# And end right now (the time at start of this script)
my $end = exists $opts{'e'} ? "-e $opts{e}" : "-e " . time();
# Default CF is 'MAX"
my $CF = exists $opts{'C'} ? $opts{'C'} : "MAX";

if ( ! @ARGV ) {

    die <<EOUSAGE;
Usage: $0 [OPTIONS] RRD ..|-

Takes one or more RRD files and summarizes their data.
By default will show averages of the entire dataset available with each
consolidated function separate.

Options:
    -s, -e, -r          Same as with rrdtool [19800101, now, '']
    -C                  Consolidated function (AVERAGE,MIN,MAX,LAST) [MAX]
EOUSAGE

} elsif ( $ARGV[0] eq "-" ) {
    @rrds = <STDIN>;
} else {
    @rrds = @ARGV;
}


foreach my $fn ( @rrds ) {
    chomp $fn;
    my @output = `rrdtool fetch "$fn" $CF $start $end $opts{r}`;

    for ( @output ) {
        chomp;
        if ( /^(\d+):\s+(\S+)$/ ) {
            my ($time, $count) = ( $1, abs($2) );

            next if ( !defined $count or $count < 1 or $count !~ /^[\d\.]+$/ );
            update_times(\%table, [ localtime($time) ], $count);
        }
    }
}

averages(\%table);

exit(0);


###################################################################################################

sub averages {
    my $h = shift;

    foreach my $year ( sort { $a <=> $b } keys %$h ) {
        my ($tot, $cou, @poi);
        my $y = $h->{$year};
        print "Year of $year:\n";

        foreach my $month ( sort { $monthsnum{$a} <=> $monthsnum{$b} } keys %$y ) {
            my ($count, $total, @points);
            my $m = $y->{$month};
            print "  Month of $month:\n";
    
            foreach my $day ( sort { $a <=> $b } keys %$m ) {
                my $d = $m->{$day};
    
                # We only show the average MAX for each day here, so pick
                # the time with the biggest total
                my $biggest = 0;
                my $biggest_time;
                foreach my $time ( keys %$d ) {
                    if ( $d->{$time}->{'total'} > $biggest ) {
                        $biggest_time = $time;
                    }
                }
    
                my $avg = ( $d->{$biggest_time}->{'total'} / $d->{$biggest_time}->{'counter'} );
                
                print "    Day of " . scalar(localtime($day)) . ":  average of " . int($avg) . " (for $d->{$biggest_time}->{counter} hosts)\n";
    
                $count++;
                $total += $avg;
                push @points, $avg;
            }
    
            # Yearly stuff
            push @poi, ($total/$count);
            $cou++;
            $tot += $poi[-1];

            print "  Total average for month: " . int($total/$count) . " (for $count days)\n";
            my $min = 0;
            my $max = int( (sort { $a <=> $b } @points)[-1] );
            print "  $url&chd=t:" . join(",", map { int } @points) . "&chds=$min,$max\n";
            print "\n";
    
        }

        print "Total average for year: " . int($tot/$cou) . " (for $cou months)\n";
        my $min = 0;
        my $max = int( (sort { $a <=> $b } @poi)[-1] );
        print "$url&chd=t:" . join(",", map { int } @poi) . "&chds=$min,$max\n";
        print "\n";

    }
}


sub update_times {
    my ($h, $t, $c) = @_;

    update_year( $h, $t, $c );
}

sub update_year {
    my ($h, $t, $c) = @_;

    $h->{ $t->[5]+1900 } = {} if (!exists $h->{$t->[5]+1900});
    update_month( $h->{$t->[5]+1900}, $t, $c );
}

sub update_month {
    my ($h, $t, $c) = @_;

    $h->{ $months[$t->[4]] } = {} if (!exists $h->{ $months[$t->[4]] });
    update_day( $h->{ $months[$t->[4]] }, $t, $c );
}


sub update_day {
    my ( $h, $t, $c) = @_;

    # NOTE: Here we set the time as a day and not a day:hour:minute:second
    my $day = timelocal( 0, 0, 0, $t->[3], $t->[4], $t->[5] );
    $h->{$day} = {} if (!exists $h->{$day});
    update_time( $h->{$day}, $t, $c );
}

sub update_time {
    my ($h, $t, $c) = @_;

    my $time = timelocal( @$t );
    $h->{$time} = { 'counter' => 0, 'total' => 0 } if (!exists $h->{$time});

    # Update the counter of the total number of times we've added to the total
    $h->{$time}->{'counter'}++;

    # Update the total
    $h->{$time}->{'total'} += $c;
}


