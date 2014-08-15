#!/usr/bin/perl
package PortableTime;
# PortableTime.pm - Time and date functions for portability
# Copyright (C) 2014 Peter Willis <peterwwillis@yahoo.com>
#
# I created this module because I wanted to calculate long
# dates on 32bit systems without having to upgrade Perl.
# It's probably horribly inefficient, but it gets the job
# done.
#
# Given an arbitrary unix timestamp it'll figure out the
# date and time. This is basically a pure perl implementation
# of the system calls that usually convert unix timestamps
# to strings and vice versa.
#
# The system's localtime() call is still used to determine
# the timezone, but that's it.

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
our $YEAR = 31536000;
our $MONTH = 2678400;
our $DAY = 86400;
our $HOUR = 3600;
our $MINUTE = 60;
our $SECOND = 1;

our $Y = $YEAR;

sub timegm {
    if ( @_ < 6 ) {
        print STDERR "Error: timegm() missing arguments\n";
        return;
    }
    #print "timegm(".join(",",@_).")\n";
    my ($sec, $min, $hour, $day, $mon, $year) = @_;
    my $y = $year > 1000 ? ($year-1970) : $year;
    my $leap = find_leaps_2($year);

    my $t = ($y*$YEAR) + ($DAY*$leap) + _month_seconds_range(0,$mon) + (($day-1)*$DAY) + ($hour*$HOUR) + ($min*$MINUTE) + $sec;
    #print "calced t $t\n";
    return $t;
}

sub time_loc {
    my $t = defined $_[0] ? $_[0] : time;
    my ($mod,$h,$m) = unpack("A1A2A2", strftime("%z",localtime()));
    my $tz = int ( (($h*$HOUR) + ($m*$MINUTE)) * int($mod."1") );
    $t += $tz;
    return $t;
}

sub timelocal {
    if ( @_ < 6 ) {
        print STDERR "Error: timelocal() missing arguments\n";
        return;
    }
    return ( PortableTime::timegm( @_ ) );
}

sub localtime {
    return ( PortableTime::gmtime( time_loc(@_) ) );
}

sub gmtime {
    my $t = defined $_[0] ? $_[0] : time;
    #print "gmtime($t)\n";

    #my ($sec, $min, $hour, $mday, $mon, $year) = find_date( $t, $Y, $MONTH, $DAY, $HOUR, $MINUTE, $SECOND );
    my ($sec, $min, $hour, $mday, $mon, $year) = find_date_2( $t );
    #print "t $t = sec $sec min $min hour $hour mday $mday mon $mon year $year\n";

    my $wday = dow($year+1970, $mon+1, $mday);
    fmt_lt( $wday, $mon, $mday, $hour, $min, $sec, $year );
}

#   _month_seconds_range( start_month, end_month )
#
#   Returns the number of seconds for the months from January
#   to end_month. Month_number is an index (0..11)
#
sub _month_seconds_range {
    my $start = shift;
    my $end = shift;
    my $s = 0;
    return $s if ! $end;

    map {
        $s += _month_seconds($_)
    } $start..($end-1);

    return $s;
}

#   _count_months( start_time, end_time )
#
#   Returns the number of months between start_time
#   and end_time. To account for leap years add the
#   leap time to $start.
#
sub _count_months_secs {
    my $start = shift;
    my $end = shift;
    my $leap = shift;
    my $s = 0;
    return $s if ! $end;

    my $c = $start;
    my $mt = 0;
    for ( my $i = 0; $i < 12; $i++ ) {
        my $ms = _month_seconds($i, $leap);
        if ( ($c+$ms) > $end ) {
            last;
        }
        $s++;
        $mt += $ms;
        $c += $ms;
    }
    return ($s,$mt);
}

# _month_seconds(month)
# _month_seconds(month, is_leap(year))
#
# Returns the number of seconds in the month.
# Pass an additional true argument if it's a leap year.
sub _month_seconds {
    my $month = shift;
    my @months = qw<31 28 31 30 31 30 31 31 30 31 30 31>;
    # Increment february if it's a leap year
    $months[1]++ if $_[0];
    return ($DAY * $months[$month]);
}


sub find_date_2 {
    my $t = shift;
    #print "find_date_2( $t )\n";

    my $y_n = int ($t / $YEAR);
    my $year = $y_n + 1970;
    my $leaps = find_leaps_2($year);

    # Remove a day if this is a leap year.
    # This is so we can calculate 'January 2, 2004' correctly.
    # (If not, we would skip to 'Jan 2' in the below year
    # calculation and not be able to count the 1-day increment
    # that is between January 1 and January 2, leaving us a day
    # off)
    $leaps-- if is_leap($year);

    my $y_t = ($y_n * $YEAR) + ($leaps * $DAY);
    # We might skip past the date even though we found the correct year
    if ( $t < $y_t ) {
        #print "skipped over year! t $t y_n $y_n year $year leaps $leaps y_t $y_t\n";
        $y_n--;
        $year = $y_n + 1970;
        $leaps = find_leaps_2($year);
        $leaps-- if is_leap($year);
        $y_t = ($y_n * $YEAR) + ($leaps * $DAY);
    }
    #$y_t -= ($YEAR
    my $left = $t - $y_t;

    #print "year $year year_time $y_t\n";

    # This division is flawed because a $MONTH is not a static unit of time.
    # A month's time varies (Feb is always 28 or 29, other months are 30 or 31).
    my ( $M_n, $M_s ) = _count_months_secs($y_t, $t, is_leap($year));
    my $M_t = $y_t + $M_s;
    $left = $t - $M_t;

    #print "month $M_n month_time $M_t\n";

    my $d_n = int($left / $DAY);
    my $d_t = $M_t + ($d_n * $DAY);
    $left = $t - $d_t;

    #print "day $d_n day_time $d_t\n";

    my $h_n = int($left / $HOUR);
    my $h_t = $d_t + ($h_n * $HOUR);
    $left = $t - $h_t;

    #print "hour $h_n hour_time $h_t\n";

    my $m_n = int($left / $MINUTE);
    my $m_t = $h_t + ($m_n * $MINUTE);
    $left = $t - $m_t;

    #print "minute $m_n minute_time $m_t\n";

    my $s_n = int($left / $SECOND);
    my $s_t = $m_t + ($s_n * $SECOND);

    #print "second $s_n second_time $s_t\n";

    return( $s_n, $m_n, $h_n, $d_n+1, $M_n, $y_n );
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

sub find_leaps_2 {
    my $year = shift;
    my $lyrs = 0;
    # Round up to the nearest multiple of 4
    #my $start = ($start + ($start % 4) - 4);
    my $start = 1972;
    while ( $start <= $year ) {
        if ( $start % 100 != 0 || $start % 400 == 0 ) {
            $lyrs++;
        }
        $start += 4;
    }
    return $lyrs;
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

sub is_leap {
    $_ = shift;
    return ( ($_ % 4) == 0 && ( ($_ % 100) != 0 || ($_ % 400) == 0 ) );
}


# fmt_lt( $wday, $mon, $mday, $hour, $min, $sec, $year );
sub fmt_lt {
    my @t = @_;
    if ( @t < 7 ) {
        print STDERR "Error: fmt_lt missing arguments\n";
        return;
    }
    #print "fmt_lt(".join(",",@t).")\n";
    my %days = ( 0 => 'Sun', 1 => 'Mon', 2 => 'Tue', 3 => 'Wed', 4 => 'Thu', 5 => 'Fri', 6 => 'Sat' );
    my %months = ( 0 => 'Jan', 1 => 'Feb', 2 => 'Mar', 3 => 'Apr', 4 => 'May', 5 => 'Jun', 6 => 'Jul', 7 => 'Aug', 8 => 'Sep', 9 => 'Oct', 10 => 'Nov', 11 => 'Dec' );
    $t[0] = $days{ $t[0] };
    #print "t[1] days $months{$t[1]} from $t[1]\n";
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

