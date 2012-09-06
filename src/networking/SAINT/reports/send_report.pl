#!/usr/bin/perl
$|=1;
use strict;
use Socket;
use MIME::Lite;
use Text::CSV_XS;
use Getopt::Long;
use Data::Dumper;

my ($GROUP, $REPORT, $SESSION, $TEST, $SMBASE, $HIGHPRIO, $ADD_CC);
GetOptions("group=s" => \$GROUP, "report=s" => \$REPORT, "session=s" => \$SESSION, "test" => \$TEST, "base=s" => \$SMBASE, "high-priority" => \$HIGHPRIO, "cc=s" => \$ADD_CC);


if ( !defined $GROUP or $GROUP =~ /^\s*?$/ ) {
    die "Usage: $0 [OPTIONS] --group GROUP\n\nOptions:\n   -r,--report REPORT\t\tName of custom report template [high-priority]\n   -s,--session SESSION\t\tSession name [GROUP_group]\n   -b,--base PATH\t\tPath to SAINT directory\n   -c,--cc EMAIL\t\tAdd an e-mail address to the Cc: field\n   --high-priority\t\tOnly send reports to admins for hosts with high priority vulnerabilities\n   -t,--test\t\t\tTest mode (does not send mail)\n\nGroup is the name of the group, which shall also be used for the session name.\n\nReport is the custom report name to use (default: 'high-priority')\n\nSession name is by default the group name plus '_group'.\n\nExample:\n   $0 -t -r configs/trimmed-high-prio-1.cf -b /usr/local/saintnode -g network\n";
}

if ( !defined $SESSION or length($SESSION) < 1 ) {
    $SESSION = $GROUP."_group";
}

# Configure these variables

my $TEST_EMAIL_ADDRESS = 'pwillis@umm.edu';

my ($DEFAULT_REPORT, $SAINTWRITER_CONF);
my $TESTING_ONLY = defined $TEST ? 1 : 0;
my $ONLY_HIGH_PRIORITY = defined $HIGHPRIO ? 1 : 0;
my $UMMS_SAINT_DIR = "/home/pwillis/git/SAINT";
#my $MAIL_RELAY = "10.30.25.81";
# '/usr/local/sm' for saint manager, '/usr/local/saintnode' for a node directory
my $SM_BASE = defined $SMBASE ? $SMBASE : "/usr/local/sm";
my $PDF_FILE="$SM_BASE/html/reporting/saintwriter/report.pdf";
my $DEFAULT_REPORT = "high-priority";
#my $SAINTWRITER_CONF = "$DEFAULT_REPORT.cf";
my $FROM_EMAIL = '"IST Risk Management" <infosec@umm.edu>';
my $REPORT_EMAIL_TEMPLATE = "$UMMS_SAINT_DIR/reports/report-email.template";
my $GROUP_MANAGERS = "$UMMS_SAINT_DIR/reports/report-managers.csv";
my $GROUP_SYSADMINS = "$UMMS_SAINT_DIR/reports/report-sysadmins.csv";
$ENV{PATH} .= ":/home/pwillis/git/scripts";


my $SENDMAIL = 'sendmail';
#my $SENDMAIL_OPTS = "-t";
my $SENDMAIL_OPTS = '-t -oi -oem';


# Configure the report name and config file
if ( defined $REPORT and -e $REPORT ) {
    $SAINTWRITER_CONF = $REPORT;
    $REPORT =~ s/\.cf$//ig;
    $REPORT =~ s/^.*\/([^\/]+)$/$1/g;
} elsif ( defined $REPORT ) {
    $SAINTWRITER_CONF = "$REPORT.cf";
} else {
    $REPORT = $DEFAULT_REPORT;
    $SAINTWRITER_CONF = "$REPORT.cf";
}


my $fn = $SAINTWRITER_CONF;
$fn =~ s/^.*\/([^\/]+)$/$1/g;

# Make sure the saintwriter config directory exists
if ( ! -d "$SM_BASE/config/saintwriter/configs" ) {
    system("mkdir", "-v", "-p", "$SM_BASE/config/saintwriter/configs");
    if ( ($? >> 8) != 0 ) {
        die "$0: Error: could not make directory '$SM_BASE/config/saintwriter/configs'\n";
    }
}

# Always copy the file, so ours is always the most current version
system("cp", "-v", $SAINTWRITER_CONF, "$SM_BASE/config/saintwriter/configs/$fn");
if ( ($? >> 8) != 0 ) {
    print STDERR "$0: Error: could not copy '$SAINTWRITER_CONF' to '$SM_BASE/config/saintwriter/configs/$fn'\n";

    if ( ! -e "$SM_BASE/config/saintwriter/configs/$fn" ) {
        die;
    } else {
        print STDERR "$0: Info: Continuing because old copy of config still exists\n";
    }
}


main();
exit(0);


sub open_csv {
    my $fn = shift;
    my $csv = Text::CSV_XS->new({binary=>1});
    open my $fh, $fn || die "open: $!";
    $csv->column_names( @{ $csv->getline($fh) } );
    $csv->eol("\n");
    return ($csv,$fh);
}


sub my_getlinehr {
    my ($csv,$io) = @_;
    my %h;
    my $line = <$io>;
    if ( $csv->parse($line) ) {
        my @f = $csv->fields();
        @h{ @{ $csv->{'_COLUMN_NAMES'} } } = @f;
        return \%h;
    }
    return;
}


sub send_email {
    my ($FROM, $TO, $CC, $SUBJECT, $cc_addrs) = @_;
    my $io;

    MIME::Lite->send('sendmail', "$SENDMAIL $SENDMAIL_OPTS");

    #open(my $pipe, "| $SENDMAIL $SENDMAIL_OPTS") || die "Error: could not open sendmail: $!";
    my $pipe = *STDOUT;
    my @msg;

    # Make a map of emails to IPs
    my $map_of_ips;
    foreach my $key ( keys %$cc_addrs ) {
        $map_of_ips .= "    Email $key -> " . join(", ", sort { $a <=> $b } keys %{$cc_addrs->{$key}}) . "\n";
    }

    open($io, "<$REPORT_EMAIL_TEMPLATE") || die "$0: Error: could not open email template: $!";
    while ( <$io> ) {
        s/__TO__/$TO/g;
        s/__FROM__/$FROM/g;
        s/__CC__/$CC/g;
        s/__SUBJECT__/$SUBJECT/g;
        s/__LIST_OF_IPS__/$map_of_ips/g;
        push(@msg, $_);
    }
    #push(@msg, "\n.\n");
    close($io);

    my $msg = MIME::Lite->new( From => $FROM, To => $TO, Cc => $CC, Subject => $SUBJECT, Type => 'multipart/mixed', Data => \@msg);
    $msg->attach( Type => 'text/plain', Data => \@msg );

    my $stamp = (stat($PDF_FILE))[9];
    $msg->attach( Type => 'application/pdf', Filename => "report-$stamp.pdf", Path => $PDF_FILE, Disposition => 'attachment' );

    $msg->send;

    #close($pipe);
}


sub main {

    # Get manager email

    my ($csv,$io) = open_csv($GROUP_MANAGERS);
    my $manager_email;

    while ( $_ = my_getlinehr($csv, $io) ) {
        if ( lc $_->{'Group'} eq $GROUP ) {
            $manager_email = $_->{'Email'};
            last;
        }
    }

    close $io;
    undef $csv;

    if ( !defined $manager_email or length $manager_email < 1 ) {
        print STDERR "$0: Error: no manager e-mail address found.\n";
        return;
    }

    print STDERR "$0: Info: manager_email $manager_email\n";

    # Get scan result IP list from SAINT facts file
    # (should work on both node-specific and global facts files)

    
    print STDERR "$0: Info: opening $SM_BASE/results/$SESSION/facts\n";
    open($io, "<$SM_BASE/results/$SESSION/facts") || die "open: $!";

    print STDERR "$0: Info: resolving IP addresses to names and vice versa\n";

    my %IPs = map { $_ => 1 } map {
        chomp;
        my @a = split(/\|/,$_);
        my $ip;
    
        # Remove MAC address, if SAINTmanager node tacked it on the summary group's facts
        $a[0] =~ s/^\w+:\w+:\w+:\w+:\w+:\w+\.//;

        if ( $a[0] =~ /^(\d+\.\d+\.\d+\.\d+)$/ ) {
            $ip = $1;
        } elsif ( $a[0] =~ /([^\|]+)/ ) {
            my $tmp = gethostbyname($1);
            if ( defined $tmp and length $tmp ) {
                $ip = inet_ntoa($tmp);
                #print "resolved ip $ip from $1\n";
            } else {
                print STDERR "$0: Error: could not resolve name $1\n";
            }
        }

        if ( defined $ip ) {
            my $ip = $1;
            if ( $ONLY_HIGH_PRIORITY ) {
                $a[3] =~ /^(?:rs|us|ns|ur|uw|nr|nw|ht|bo|nfs|dos)$/ ? $ip : ()
            } else {
                $ip
            }
        }
    } <$io>;
    my @IPs = map { /^.+$/ ? $_ : () } keys %IPs;

    close $io;

    # Build list of email addresses for admins of each IP

    ($csv,$io) = open_csv($GROUP_SYSADMINS);

    my %cc_addrs;
    while ( my $h = my_getlinehr($csv, $io) ) {

        foreach my $ip ( @IPs ) {
            if ( grep(/\Q$ip\E;/, $h->{'IPAddresses'}) ) {
                #$cc_addrs{ $h->{'Email'} }++;
                $cc_addrs{ $h->{'Email'} }->{$ip}++;
            }
        }
    }

    close $io;

    if ( ! @IPs ) {
        print STDERR "$0: Error: no IP addresses found in facts file (or no high-priority ones).\n";
        return;
    }

    # Generate the report

    if ( -e $PDF_FILE ) {
        unlink($PDF_FILE) || die "$0: Error: could not delete existing pdf file: $!";
    }
    system("cd $SM_BASE ; ./bin/saintwriter -c $SAINTWRITER_CONF -f 6 -d $GROUP"."_group");

    if ( ! -e $PDF_FILE ) {
        die "$0: Error: failed to generate report pdf\n";
    }

    # Send the e-mail

    my ($FROM, $TO, $SUBJECT) = ($FROM_EMAIL, $manager_email, ucfirst($GROUP)." group SAINT Vulnerability Scan Report");
    my $CC = join(", ", keys %cc_addrs);
    $CC .= ", $ADD_CC" if (defined $ADD_CC);

    print STDERR "\n$0: Info: Sending mail: TO $TO, CC $CC\n\n";

    if ( $TESTING_ONLY ) {
        $TO = $TEST_EMAIL_ADDRESS;
        $CC = $TEST_EMAIL_ADDRESS;
    }

    send_email($FROM, $TO, $CC, $SUBJECT, \%cc_addrs);

}

