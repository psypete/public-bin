#!/usr/bin/perl
package PortableTime;
# PortableTime.pm - Time and date functions for portability
# Copyright (C) 2014 Peter Willis <peterwwillis@yahoo.com>
#
# I created this module because I wanted to calculate longer
# dates on 32bit systems without having to upgrade Perl.
# And I might have been bored.
#
# This is basically a pure perl implementation of the
# localtime() and gmtime() system calls, as well as
# implementations of timelocal() and timegm() to handle the
# bigger time values correctly (the native versions complain
# about days being too big on my system).
#
# The system's localtime() call is used in conjunction with
# POSIX::strftime() to determine the timezone.
#
# Daylight savings time and leap seconds are not supported.
# If you want something that implements these, try the 
# DateTime module from CPAN.
#
# Some minimal caching and algorithm improvements were added.
# For the same time value, localtime() and gmtime() are about
# 3x faster than their native counterparts, but for new values
# they're about 98% slower. timelocal() and timegm() are only
# 50% slower and don't cache time values. Timezone changes
# are respected by the cache.


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

sub valid_vals {
    if ( @_ < 6 ) {
        print STDERR __PACKAGE__ . ": missing arguments to timegm()\n";
    } elsif ( $_[0] < 0 || $_[0] > 59 ) {
        print STDERR __PACKAGE__ . ": Second $_[0] out of range 0..59\n";
    } elsif ( $_[1] < 0 || $_[1] > 59 ) {
        print STDERR __PACKAGE__ . ": Minute $_[1] out of range 0..59\n";
    } elsif ( $_[2] < 0 || $_[2] > 23 ) {
        print STDERR __PACKAGE__ . ": Hour $_[2] out of range 0..23\n";
    } elsif ( $_[3] < 0 || $_[3] > 31 ) {
        print STDERR __PACKAGE__ . ": Day $_[3] out of range 1..31\n";
    } elsif ( $_[4] < 0 || $_[4] > 11 ) {
        print STDERR __PACKAGE__ . ": Month $_[4] out of range 0..11\n";
    } else {
        return 1;
    }
    return 0;
}


sub timegm {
    return unless valid_vals(@_);

    #print "timegm(".join(",",@_).")\n";
    my ($sec, $min, $hour, $day, $mon, $year) = @_;

    my $y = $year > 1000 ? ($year-1970) : $year;
    my $leap = find_leaps_2($year);

    my $msr = _month_seconds_range(0,$mon);
    my $t = ($y*$YEAR) + ($DAY*$leap) + $msr + (($day-1)*$DAY) + ($hour*$HOUR) + ($min*$MINUTE) + $sec;
    #print "calced t $t\n";
    return $t;
}


sub timelocal {
    return unless valid_vals(@_);

    my ($sec, $min, $hour, $mday, $mon, $year) = @_;
    my ($mod,$h,$m) = unpack("A1A2A2", strftime("%z",localtime()));

    # Here $mod becomes negative if the time difference is positive and
    # vice-versa. This is because timelocal() is the inverse of localtime().
    # See Time::Local behavior for an example.
    $mod = $mod eq "-" ? 1 : -1;

    my $tz = int ( (($h*$HOUR) + ($m*$MINUTE)) * $mod );
    $min += ($m * $mod) if (defined $min and defined $m);
    $hour += ($h * $mod) if (defined $hour and defined $h);

    return ( PortableTime::timegm( $sec, $min, $hour, $mday, $mon, $year ) );
}


# persistent variables with the following block around the sub
{
    my $LAST_LT='';
    my $LAST_TZ='';
    my @LAST_LT=();
    sub localtime {
        my $_tz = strftime("%z",localtime());

        # Set to current time if no time specified
        my $t = defined $_[0] ? $_[0] : time;

        # Speed hack: return last value IF the time value and timezone are the same
        return ( wantarray ? @LAST_LT : $LAST_LT[0] ) if ( $t eq $LAST_LT and $_tz eq $LAST_TZ );

        $LAST_LT = $t;
        $LAST_TZ = $_tz;

        my ($mod,$h,$m) = unpack("A1A2A2", $_tz);
        $mod = $mod eq "-" ? -1 : 1;

        # Add the timezone difference
        $t = ( $LAST_LT + (($h*$HOUR) + ($m*$MINUTE)) * $mod );

        if ( wantarray ) {
            @LAST_LT = PortableTime::gmtime( $t );
        } else {
            $LAST_LT[0] = PortableTime::gmtime( $t );
        }
    }
}


# persistent variables with the following block around the sub
{
    my $LAST_GMT = '';
    my @LAST_GMT = ();
    # Until we implement daylight savings time, always return a negative
    # number, which means the information is unavailable [ctime(3)].
    my $isdst = -1;
    sub gmtime {
        my $t = defined $_[0] ? $_[0] : time;

        # Speed hack: cache last result
        return ( wantarray ? @LAST_GMT : $LAST_GMT[0] ) if ( $t eq $LAST_GMT );

        $LAST_GMT = $t;

        my ($sec, $min, $hour, $mday, $mon, $year, $yday) = find_date_2( $LAST_GMT );
        #print "t $LAST_GMT = sec $sec min $min hour $hour mday $mday mon $mon year $year\n";

        my $wday = dow($year+1970, $mon+1, $mday);

        if ( wantarray ) {
            @LAST_GMT = ( $sec , $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst );
        } else {
            $LAST_GMT[0] = fmt_lt( $wday, $mon, $mday, $hour, $min, $sec, $year );
        }
    }
}


#   _month_seconds_range( start_month, end_month )
#
#   Returns the number of seconds for the months from January
#   to end_month. Month_number is an index (0..11)
#

# persistent variables with the following block around the sub
{
    # Cache the seconds in starttime-endtime
    my $LAST_MSR = '';
    my %LAST_MSR_V;
    sub _month_seconds_range {
        my $start = shift;
        my $end = shift;
        
        # Speed hack: cache value
        return $LAST_MSR_V{"$start-$end"} if exists $LAST_MSR_V{"$start-$end"};
        $LAST_MSR = "$start-$end";

        $LAST_MSR_V{$LAST_MSR} = 0;
        return 0 if ! $end;

        map {
            my $m = _month_seconds($_);
            $LAST_MSR_V{$LAST_MSR} += $m;
        } $start..($end-1);

        return $LAST_MSR_V{$LAST_MSR};
    }
}


#   _count_months_secs( start_time, end_time )
#
#   Returns the number of months and seconds between start_time
#   and end_time. To account for leap years, pass and additional
#   argument (1).

# persistent variables with the following block around the sub
{
    # Cache the start-end-leap values
    my $LAST_CMS='';
    my %LAST_CMS_V;
    sub _count_months_secs {
        my $start = shift;
        my $end = shift;
        my $leap = shift || 0;

        # Speed hack; return cached values
        return @{$LAST_CMS_V{"$start-$end-$leap"}} if exists $LAST_CMS_V{"$start-$end-$leap"};
        $LAST_CMS = "$start-$end-$leap";

        $LAST_CMS_V{$LAST_CMS} = [0, 0];
        return 0 if ! $end;

        my $c = $start;
        for ( my $i = 0; $i < 12; $i++ ) {
            my $ms = _month_seconds($i, $leap);
            if ( ($c+$ms) > $end ) {
                last;
            }
            $LAST_CMS_V{$LAST_CMS}->[0]++;
            $LAST_CMS_V{$LAST_CMS}->[1] += $ms;
            $c += $ms;
        }
        return @{ $LAST_CMS_V{$LAST_CMS} };
    }
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
    my $h_ = ($h_n * $HOUR);
    my $h_t = $d_t + $h_;
    $left = $t - $h_t;
    #print "hour $h_n hour_time $h_t\n";

    my $m_n = int($left / $MINUTE);
    my $m_ = ($m_n * $MINUTE);
    my $m_t = $h_t + $m_;
    $left = $t - $m_t;
    #print "minute $m_n minute_time $m_t\n";

    my $s_n = int($left / $SECOND);
    my $s_t = $m_t + $s_n;
    #print "second $s_n second_time $s_t\n";
    
    my $doy = ( ($t - $y_t) - $s_n - $m_ - $h_ ) / $DAY;
    #print "doy $doy\n";

    return( $s_n, $m_n, $h_n, $d_n+1, $M_n, $y_n, $doy );
}


# persistent variables with the following block around the sub
{
    # Cache the leap years found
    my %LEAPS;
    sub find_leaps_2 {
        my $year = $_[0];
        return $LEAPS{$year} if exists $LEAPS{$year};
        $LEAPS{$year} = 0;
        # Round up to the nearest multiple of 4
        #my $start = ($start + ($start % 4) - 4);
        my $start = 1972;
        while ( $start <= $year ) {
            if ( $start % 100 != 0 || $start % 400 == 0 ) {
                $LEAPS{$year}++;
            }
            $start += 4;
        }
        return $LEAPS{$year};
    }
}


# persistent variables with the following block around the sub
{
    # Cache which years are leap years
    my %ISLEAP;
    sub is_leap {
        return $ISLEAP{$_[0]} if exists $ISLEAP{$_[0]};
        $ISLEAP{$_[0]} = ( ($_[0] % 4) == 0 && ( ($_[0] % 100) != 0 || ($_[0] % 400) == 0 ) );
    }
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

__END__


# Obsolete; kept for posterity
#
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

# Obsolete; kept for posterity
sub find_leaps {
    my $year = shift;
    my $lyrs = 0;
    map {
        $lyrs++ if ( ($_ % 4) == 0 && ( ($_ % 100) != 0 || ($_ % 400) == 0 ) )  
    } 1970..$year;
    #print "found $lyrs leap days between 1970 and $year\n";
    return $lyrs
}

