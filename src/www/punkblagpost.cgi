#!/usr/bin/perl
use strict;
use warnings;
use CGI qw(:standard);
use DB_File;
use Time::Local;
use LWP::UserAgent;

our $DBASE_FILE = "work/punkblagpost.db";
our $TEMPLATE = "punkblagpost.template";
our @ERRORS;
our @FOOTER;
our ($X, $DBASE, $LOCK);

our $cgi = new CGI;
# Just assume feb has 29 days. fuck it.
# Might not need these "last days of month" values, actually.
my %month_days = ( "01" => "31", "02" => "29", "03" => "31", "04" => "30", "05" => "31", "06" => "30", "07" => "31", "08" => "31", "09" => "30", "10" => "31", "11" => "30", "12" => "31" );
my @daysofweek = qw(Sunday Monday Tuesday Wednesday Thursday Friday Saturday);
my @months = qw(January February March April May June July August September October November December);

# Change to "work" directory (owned by apache)
#chdir("work");

# Process any param() shit first
process_input();

# Basic beginning of page
print header;
print start_html("Punk Blag Creator");

# Print the body
body_page();

# Print the footer
footer_page();

# End it
print end_html;

exit 0;


############################## SUBROUTINES ###################################

# basic body to print
sub body_page {
    my (undef, undef, undef, $mday, $mon, $year) = localtime();
    $year += 1900;
    $mon += 1;
    opendb();

    print h1("Add an Event");
    print start_form( -method => "POST" );
    print table( { -border => 1 },
        #caption("Add an Event"), 
        Tr( { -align => "CENTER", -valign => "TOP" },
            [
                td( [
                    em("Image URL:") ,
                    textfield("link")
                ] ) ,
                td( [
                    em("Day of Month:"),
                    popup_menu( -name => "month", -values => [ sort { $a cmp $b } keys %month_days ], -default => sprintf("%0.2d", $mon) )
                    . " / "
                    . popup_menu( -name => "day", -values => [ 1..31 ], -default => $mday )
                    . " / "
                    . popup_menu( -name => "year", -values => [ 2000..2099 ], -default => $year )
                ] ) ,
                td( [
                    em("Venue:<br>(fill in text box if missing)"),
                    popup_menu( -name => "venue", -values => [ sort { $a cmp $b } split(/\0/, $DBASE->{"venues"}) ] )
                    . br
                    . textfield("myvenue")
                ] ) ,
                td( [
                    em("Band List:<br>(add new bands separated by commas)"),
                    scrolling_list( -name => "bands", -values => [ sort { $a cmp $b } split(/\0/, $DBASE->{"bands"}) ], -size => 5, -multiple => "true" )
                    . br
                    . textfield("mybands")
                ] ) ,
                td( [ em("Time:"), 
                    popup_menu( -name => "hour", -values => [ 1..24 ], -default => 20 )
                    . " / "
                    . popup_menu( -name => "minute", -values => [ 0, 15, 30, 45 ] )
                ] ) ,
                td( [
                    em("Cost:"),
                    textfield("cost")
                ] ) ,
                td( [
                    em("Ages:"),
                    popup_menu( -name => "ages", -values => [ "?", "21+", "18+", "all ages" ] )
                ] )
            ]
        )
    );

    print br, submit("action","post-event"), "&nbsp;", reset, end_form;

    closedb();
}


sub footer_page {
    if ( @ERRORS ) {
        print header;
        print h1("Error");
        foreach my $error (@ERRORS) {
            print h2($error);
        }
    }

    if ( @FOOTER ) {
        print @FOOTER;
    }
}

# process form input here. runs before anything is printed out.
sub process_input {
    # Only process if there is an 'action'
    my $action = param("action");
    if ( !defined $action or length($action) < 1 or $action =~ /^\s*$/ ) {
        return;
    }

    if ( $action eq "post-event" ) {
        my %tmp;
        # Verify the default values have been passed
        foreach my $var ( qw(link month day year venue hour minute cost ages) ) {
            my $val = param($var);
            if ( !defined $val or length($val) < 1 or $val =~ /^\s*?$/ ) {
                push(@ERRORS, "You need to specify '$var'.");
                next;
            }
            $tmp{$var} = $val;
            # Strip whitespace, do whatever generic cleanup may be good
            $tmp{$var} =~ s/^\s+//g;
            $tmp{$var} =~ s/\s+$//g;
        }

        my $tmpvenue = param("myvenue");
        if ( defined $tmpvenue and length($tmpvenue) > 1 and $tmpvenue !~ /^\s*$/ ) {
            $tmp{"venue"} = param("myvenue");
        }
        $tmp{"venue"} =~ s/(\w+)/length($1) > 1 ? ucfirst($1) : $1/eg;

        # Assume 'bands' is a multivalue, so ask for an array
        my @bands = param("bands");

        # If 'mybands' was also passed, put that on top of any multi-selected bands
        my $tmpbands = param("mybands");
        if ( defined $tmpbands and length($tmpbands) > 1 and $tmpbands !~ /^\s*$/ ) {
            push(@bands, split(/,\s+/, param("mybands") ) );
        }

        if ( ! @bands ) {
            push @ERRORS, "You need to select a band or specify one in the text box.";
        }

        # ucfirst each word in each band in @bands
        map { s/(\w+)/length($1) > 1 ? ucfirst($1) : $1/eg; $_ } @bands;
        $tmp{"bands"} = join(";", @bands);

        # Clean up some more useful values

        # Set the "9:45pm" format time
        $tmp{"time"} = ($tmp{"hour"} > 12 ? $tmp{"hour"}-12 : $tmp{"hour"}) . ":" . sprintf("%0.2d",$tmp{"minute"}) . ($tmp{"hour"} > 11 ? $tmp{"hour"} < 24 ? "pm" : "am" : "am");

        # Set the unix time since epoch for this event
        $tmp{"unixtime"} = timelocal(0, $tmp{"minute"}, $tmp{"hour"}, $tmp{"day"}, int($tmp{"month"})-1, $tmp{"year"}-1900);
        my @lc = localtime($tmp{"unixtime"});

        # Set the date ("Dayofweek, Month day Year")
        $tmp{"date"} = $daysofweek[$lc[6]] . ", " . $months[$lc[4]] . " $lc[3] $tmp{year}";

        # Name of the event (mostly for internal record keeping)
        $tmp{"event_name"} = "$tmp{month}/$tmp{day}/$tmp{year} $tmp{hour}:$tmp{minute} \@ $tmp{venue}";

        # A shortened URL to the flyer or other link
        $tmp{"shortlink"} = shorten_url($tmp{"link"});

        # Ok. Stick all that back in the database
        store_event(\%tmp);

        # And go ahead and 'post' the event info
        post_event(\%tmp);

    }
}

sub store_event {
    my $data = shift;
    opendb();
    my @venues = split(/\0/, $DBASE->{"venues"});
    my @bands = split(/\0/, $DBASE->{"bands"});

    # Let's start by making sure the data is clean; remove all nulls from $data's keys and values
    map { s/\0//g } %$data;

    # Push new venues to database
    if ( ! grep(/^\Q$data->{venue}\E$/i, @venues) ) {
        print STDERR "apparently $data->{venue} is not in \"@venues\"\n";
        push(@venues, $data->{"venue"});
    }
    $DBASE->{"venues"} = join("\0", sort { $a cmp $b } @venues);

    # Push new bands to database
    foreach my $band ( split(/;/, $data->{"bands"}) ) {
        if ( ! grep(/^\Q$band\E$/i, @bands) ) {
            push(@bands, $band);
        }
    }
    $DBASE->{"bands"} = join("\0", sort { $a cmp $b } @bands);

    my @events = split(/\0/, $DBASE->{"event_list"});
    #my $event_identifier = "$data->{month}/$data->{day}/$data->{year} $data->{hour}:$data->{minute} \@ $data->{venue}";
    my $event_identifier = $data->{"event_name"};
    push(@events, $event_identifier);
    $DBASE->{$event_identifier} = join("\0", %$data);
    $DBASE->{"event_list"} = join("\0", @events);

    closedb();

}

# This is eventually supposed to post it to blogger and google calendar.
# For now just print it out.
sub post_event {
    my $data = shift;

    push @FOOTER, hr;
    push @FOOTER, h2("HTML code for blog post:");
    push @FOOTER, "<pre>";
    open(TEMPLATE, "<$TEMPLATE") || die "Error: could not open template $TEMPLATE: $!\n";
    while ( my $line = <TEMPLATE> ) {
        foreach my $key (keys %$data) {
            my $uckey = uc($key);
            $line =~ s/__$uckey\__/myprettyprint($data->{$key})/eg;
        }
        $line =~ s/</&lt;/g;
        $line =~ s/>/&gt;/g;
        push @FOOTER, $line;
    }
    close(TEMPLATE);
    push @FOOTER, "</pre>";
}

sub myprettyprint {
    my $stuff = $_[0];
    $stuff =~ s/\0/, /g; # assume nulls are just separators for lists
    $stuff =~ s/;/, /g;
    return $stuff;
}

# flock, O_EXLOCK and other methods are non-portable.
# lock the database so we don't fuck it over.
# get close to atomic lock as possible by creating a temp file and creating a
# hard link to it.
sub get_dbase_lock {
    my $start = time();
    my $tmpfn = "$DBASE_FILE.$start.$$.".rand();
    my ($fh);

    die "Error: lock $tmpfn already exists\n" if ( -e $tmpfn);
    die "Error: unable to create tmp lockfile\n" unless ( sysopen($fh, $tmpfn, O_CREAT|O_WRONLY, 0600) );

    # Try for 120 seconds (0.01 * 12000 = 120 seconds)
    for ( my $i=0; $i < 12000; $i++ ) {
        if ( link($tmpfn, "$DBASE_FILE.lock") ) {
            return $tmpfn;
        } else {
            select(undef, undef, undef, 0.01);
        }
    }

    # Did not get a lock. Bummer.
    unlink($tmpfn);
    print STDERR "Error: did not get a lock on $DBASE_FILE\n";
    return undef;
}

sub release_dbase_lock {
    my $file = shift; # the temp file we created earlier
    unlink("$DBASE_FILE.lock");
    unlink($file);
}

sub opendb {
    $LOCK = get_dbase_lock();
    my $flags = ( defined $LOCK ? O_CREAT|O_RDWR : O_RDONLY ); # open db read-only if could not establish a lock
    $X = tie my %DBASE, 'DB_File', $DBASE_FILE, O_CREAT, 0600, $DB_HASH;
    $DBASE = \%DBASE
}
        
sub closedb {
    return unless (defined $X and defined $DBASE);
    if ( defined $LOCK ) {
        release_dbase_lock($LOCK);
    }
    undef $X;
    untie %$DBASE;
    undef $DBASE;
    undef $LOCK;
}

# shorten a url and return the shortened form
# apparently several shortening sites have open APIs which don't require registration.
# i never liked screen scraping anyway...
# hmm. apparently there's a WWW::Shorten package which does all this. oh well, i don't
# like adding dependencies.
sub shorten_url {
    my $url = shift;
    return undef unless defined $url;
    my $ua = LWP::UserAgent->new;
    my $short;
    my @api_sites = ('http://is.gd/api.php?longurl=', 'http://tinyurl.com/api-create.php?url=', 'http://kl.am/api/shorten/?format=text&url=', 'http://metamark.net/api/rest/simple?long_url=');

    foreach my $api (@api_sites ) {
        #print STDERR "Trying $api$url\n";
        my $res = $ua->get("$api$url");
        if ( $res->is_success ) {
            my $content = $res->content;
            #print STDERR "Got content $content\n";
            if ( $content =~ /(http:\/\/.+)/ ) {
                $short = $1;
                last
            }
        }
    }

    return $short;
}

# Make sure we try to close the dabase, and most importantly, unlock it.
END {
    closedb();
}

