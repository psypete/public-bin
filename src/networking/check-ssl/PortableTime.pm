#!/usr/bin/perl
package PortableTime;

$|=1;

use strict;
use warnings;

use POSIX qw(strftime);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(gmtime localtime);
our @EXPORT_OK = qw(gmtime localtime timegm timelocal);

#my $HIGHEST_32BIT_TIME = 2147483647;

## Leap year
#my $YEAR_LEAP = 31622400;
## Julian year
#my $YEAR_JY = 31557600;
#my $YEAR_LYS = 31558149.7676;
## standard SI year
#my $YEAR_SI = 31556925.9747;
# Calendar year
my $YEAR = 31536000;
my $MONTH = 2678400;
my $DAY = 86400;
my $HOUR = 3600;
my $MINUTE = 60;
my $SECOND = 1;

my $Y = $YEAR;

sub timegm {
    my ($sec, $min, $hour, $day, $mon, $year) = @_;
    my $y = $year > 1000 ? ($year-1970) : $year;
    my $leap = find_leaps($year);

    my $t = ($y*$YEAR) + ($DAY*$leap) + _month_seconds_range(0,$mon) + (($day-1)*$DAY) + ($hour*$HOUR) + ($min*$MINUTE) + $sec;

    return $t;
}

sub timelocal {
    my $t = timegm(@_);
    $t += strftime("%z", localtime());
    return $t
}

sub localtime {
    my @t = gmtime(@_);
    $t[2] += strftime("%z", localtime());
    return @t
}

sub gmtime {
    my $t = shift;

    my ($sec, $min, $hour, $mday, $mon, $year) = find_date( $t, $Y, $MONTH, $DAY, $HOUR, $MINUTE, $SECOND );
    #print "sec $sec min $min hour $hour mday $mday mon $mon year $year\n";

    my $wday = dow($year+1970, $mon+1, $mday);

    fmt_lt( $wday, $mon, $mday, $hour, $min, $sec, $year );
}

#   month_count(year, month_number)
#
#    - year should be the full year (+ century)
#    - month_number is an index (0..11)
#
#   Returns the number of seconds for the months from January $Year
#   to month_number $Year. Also returns if a leap day was added.
#   (calculates correct days per month + leap day)
#
sub _month_seconds_range {
    my $start = shift;
    my $end = shift;
    my $s;
    return 0 if ! $end;
    map {
        $s += _month_seconds($_)
    } $start..($end-1);
    return $s;
}

sub _month_seconds {
    my $month = shift;
    my @months = qw<31 28 31 30 31 30 31 31 30 31 30 31>;
    return ($DAY * $months[$month]);
}


#   find_date( timestamp [since epoch], year_in_seconds, 
#              month_in_seconds, day_in_seconds, hour_in_seconds,
#              minute_in_seconds, seconds_in_seconds )
#
#   Given a timestamp and a series of values (in seconds),
#   searches for the amount of each incrementation and
#   returns the number of each increment that leads to the
#   timestamp.
#
#   Returns the values in the same order as localtime()
#
sub find_date {
    my $t = shift;
    my $i_t = 0;
    my @c;

    # Note: we assume that @_ is year, month, day, hour, minute, second
    for ( my $pos=0; $pos < @_; $pos++ ) {
        my $incr = $_[$pos];
        my $c = 0;
        my $added_leap = 0;
        my $tincr;

        for ( ;; ) {

            $tincr = $incr;

            # End this $c calculation when we go over $t
            if ( $i_t > $t ) {
                if ( $added_leap ) {
                    $i_t -= $DAY;
                }
                last;
            }

            $added_leap = 0;

            # The year calculation
            if ( $pos == 0 ) {
                # $c is years since 1970
                # Assume $incr here is a year in seconds
                # without leap days.
                my $yr = $c + 1970;

                # Add the leap day to this year
                if ( !($yr % 4) && $yr % 100 || !($yr % 400) ) {
                    $tincr += $DAY;
                    $added_leap++;
                }
            }

            # Calculate the seconds for the month based
            # on the number of days in the month
            elsif ( $pos == 1 ) {
                # Assuming $incr passed was 31 days of seconds
                #my $tincr = $incr;

                # Actually, nevermind $incr, let's just pick the right
                # number of days based on the month, since they're
                # all over the place (feb==28, jul&aug==31,...)
                $tincr = _month_seconds($c);

                # February
                if ( $c == 1 ) {
                    # Add a leap day
                    if ( !(($c[0]+1970) % 4) && ($c[0]+1970) % 100 || !(($c[0]+1970) % 400) ) {
                        $tincr += $DAY;
                        $added_leap++;
                    }
                }
            }
            
            $i_t += $tincr;

            $c++;
        }

        $i_t -= $tincr;
        $c--;

        push(@c, $c);
    }

    # There's no "Day 0"... this needs to be incremented to return the expected day value
    $c[2]++;

    return reverse @c;
}

sub find_leaps {
    my $year = shift;
    my $lyrs = 0;
    map {
        $lyrs++ if ( ($_ % 4) == 0 && ( ($_ % 100) != 0 || ($_ % 400) == 0 ) )  
    } 1970..$year;
    #print "found $lyrs leap days between 1970 and $year\n";
    return $lyrs
}

# fmt_lt( $wday, $mon, $mday, $hour, $min, $sec, $year );
sub fmt_lt {
    my @t = @_;
    my %days = ( 0 => 'Sun', 1 => 'Mon', 2 => 'Tue', 3 => 'Wed', 4 => 'Thu', 5 => 'Fri', 6 => 'Sat' );
    my %months = ( 0 => 'Jan', 1 => 'Feb', 2 => 'Mar', 3 => 'Apr', 4 => 'May', 5 => 'Jun', 6 => 'Jul', 7 => 'Aug', 8 => 'Sep', 9 => 'Oct', 10 => 'Nov', 11 => 'Dec' );
    $t[0] = $days{ $t[0] };
    $t[1] = $months{ $t[1] };
    $t[6] += 1970;
    sprintf("%s %s %d %02d:%02d:%02d %d", @t);
}

# #  The source: Journal on Recreational Mathematics, Vol. 22(4), pages +280-282, 1990.
# #  The authors: Michael Keith and Tom Craver.
sub dow {
  my ($y, $m, $d) = @_;
  $y-- if $m < 3;
  $d += 11 if $y < 1752 || $y == 1752 && $m < 9;
  if ($y >= 1752) {
    return (int(23*$m/9)+$d+4+($m<3?$y+1:$y-2)+int($y/4)-int($y/100)+int($y/400))%7;
  } else {
    return (int(23*$m/9)+$d+5+($m<3?$y+1:$y-2)+int($y/4))%7;
  }
}

1;

