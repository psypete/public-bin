#!/usr/bin/perl
# editdhcpleases.pl
# 
# This script will check out $DHCP_SVN_DIR and load, modify
# and commit $DHCP_SVN_FILE's static dhcp leases. It should
# be able to run under apache as user 'nobody'. Username
# and password are passed to svn via Expect and svn files
# are cleaned up each time the script runs.

use CGI qw/:standard/;
use Expect;
use strict;

srand();
my ($USER, $PASS);
my $CGISCRIPT = "editdhcpleases.pl";
my $DHCP_SVN_FILE = "dhcpadm.conf";
my $DHCP_SVN_DIR = "http://repo000/repos/cf/trunk/etc/dhcpd";
# Random temp directory for the current user to checkout svn
my $LEASEDIR = "/tmp/" . join('', map { $_=chr(rand(26)+97) } 0..26) . ".d";
my $LEASES = "$LEASEDIR/$DHCP_SVN_FILE";
my $METHOD = "POST";
my $q = new CGI;

mkdir($LEASEDIR);
my $endsub = sub { system("/bin/rm -rf $LEASEDIR") };
END {
    &$endsub();
    exit(0);
};
$SIG{INT} = sub { &$endsub(); exit(1) };
$SIG{TERM} = sub { &$endsub(); exit(1) };

print <<EOF;
Content-Type: text/html

<html><head>
<title>Edit DHCP Leases</title>
<link rel="stylesheet" type="text/css" href="http://mon000.be.sportsline.com/css/moncgi.css" />
</head><body>
EOF

#####################################################################
#         Handle CGI requests, print response, and exit.            #
# ###################################################################

# Collect username and password if it was passed
if ( $q->param("user") and $q->param("pass") ) {
    $USER = $q->param("user");
    $PASS = $q->param("pass");
}

if ( ! $q->param("user") or ! $q->param("pass") ) {

    print <<EOF;
<h1>Login</h1>
<form method="$METHOD" action="$CGISCRIPT">
Username: <input type="text" name="user"><br>
Password: <input type="password" name="pass"><br>
<input type="submit"> <input type="reset">
</form>
</body>
</html>
EOF

} elsif ( ! $q->param("addlease") and ! $q->param("dellease") ) {

    print "<h1>Edit DHCP Leases</h1>\n<p>\nTo add a new static lease, fill out all the fields below and press Submit.<br>\nOtherwise select an existing lease to delete.<br>\n<\/p>\n";
    print_index();
    print "</body></html>\n";

} elsif ( $q->param("addlease") ) {

    my $ret = add_lease();
    if ( defined $ret and length($ret) > 0 ) {
        print "<h2><font color=\"red\"><i>Add lease result: $ret</i></font></h2>\n";
    }
    print_index();
    print "</body></html>\n";

} elsif ( $q->param("dellease") ) {

    my $ret = del_lease();
    if ( defined $ret and length($ret) > 0 ) {
        print "<h2><font color=\"red\"><i>Delete lease result: $ret</i></font></h2>\n";
    }
    print_index();
    print "</body></html>\n";

}

exit(0);

####################################################################
#                          Subroutines                             #
####################################################################

sub svn_update {
    # Don't need but the most up-to-date copy. No local edits pls!
    unlink($LEASES);
    my $cmd = "svn checkout -q --username $USER --no-auth-cache $DHCP_SVN_DIR \"$LEASEDIR\"";
    my $ret = wrap_svn($cmd);
    if ( !defined $ret or $ret != 0 ) {
        return("Failure; 'svn update' returned non-zero status");
    }
}

sub add_lease {
    my ($host, $mac, $ip) = ( $q->param('host'), $q->param('mac'), $q->param('ip') );

    if ( !defined $host or !defined $mac or !defined $ip ) {
        return("Failure; Need to specify host, mac and ip.");
    }

    # host names are only a-z, A-Z, 0-9, . and -
    if ( $host =~ /[^a-zA-Z0-9.-]/ ) {
        return("Failure; Host can only have characters a-z, 0-9, \".\" and \"-\"");
    # mac should be 6 sets of [a-fA-F0-9] separated by colons
    } elsif ( $mac !~ /^[a-f0-9][a-f0-9]:[a-f0-9][a-f0-9]:[a-f0-9][a-f0-9]:[a-f0-9][a-f0-9]:[a-f0-9][a-f0-9]:[a-f0-9][a-f0-9]$/i ) {
        return("Failure; MAC address should be six pairs of two characters (valid characters: a-f, 0-9) separated by colons");
    # IP should be four octets no bigger than 255
    } elsif ( $ip !~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/ or $1 > 255 or $2 > 255 or $3 > 255 or $4 > 255 ) {
        return("Failure; IP address must be four sets of digits separated by periods, each set not larger than 255");
    }

    my $ret = svn_update();
    return($ret) if (defined $ret and length($ret) > 0);

    open(LEASEFILE, ">>$LEASES") || return("Failure; Could not add lease: Could not append to leases file $LEASES: $!");
    print LEASEFILE "host $host {\n\thardware ethernet $mac;\n\tfixed-address $ip;\n}\n";
    close(LEASEFILE);

    $ret = wrap_svn("svn commit -q --username $USER --no-auth-cache --message \"User $USER is adding new lease: host $host, mac $mac, ip $ip\" \"$LEASES\"");
    if ( !defined $ret or $ret != 0 ) {
        return("Failure; Could not add lease: 'svn commit' returned non-zero status");
    }
}

sub del_lease {
    my $leases = read_leases($LEASES);
    my @deleted_leases;

    while ( my ($mac, $obj) = each %$leases ) {
        if ( $q->param($mac) ) {
            if ( $leases->{LEASECONFIG} =~ s/host $obj->{host} {\s+hardware ethernet $mac;\s+fixed-address $obj->{ip};\s+}\s+//isg ) {
                push @deleted_leases, $mac;
            } else {
                return("Failure; could not delete lease for $mac: could not find accompanying lease (make sure nobody hand-edits the lease file!)");
            }
        }
    }

    my $ret = svn_update();
    return($ret) if (defined $ret and length($ret) > 0);

    open(LEASEFILE, ">$LEASES") || return("Failure; Could not delete lease: Could not write to leases file $LEASES: $!");
    print LEASEFILE $leases->{LEASECONFIG};
    close(LEASEFILE);

    $ret = wrap_svn("svn commit -q --username $USER --no-auth-cache --message \"User $USER is deleting these leases:\n" . join("\n", @deleted_leases) . "\" \"$LEASES\"");
    if ( !defined $ret or $ret != 0 ) {
        return("Failure; Could not delete lease: 'svn commit' returned non-zero status");
    }

}

sub print_index {
    print <<EOF;
<p><form method="$METHOD" action="$CGISCRIPT" name="addlease"><input type="hidden" name="user" value="$USER"><input type="hidden" name="pass" value="$PASS"><input type="hidden" name="addlease" value="1">
<h3>Add a new static lease</h3>
<table cellpadding=2 cellspacing=2 border=2>
<tr><td>Host name</td><td><input type="text" name="host"></td></tr>
<tr><td>MAC Address</td><td><input type="text" name="mac" size=17 maxlength=17></td></tr>
<tr><td>IP Address</td><td><input type="text" name="ip" size=15 maxlength=15></td></tr>
</table>
<input type="submit"> <input type="reset">
</form>
</p>
<p><form method="$METHOD" action="$CGISCRIPT" name="dellease"><input type="hidden" name="user" value="$USER"><input type="hidden" name="pass" value="$PASS"><input type="hidden" name="dellease" value="1">
<h3>Delete a static lease</h3>
<table cellpadding=2 cellspacing=2 border=2><tr><td>*</td><td>Mac Address</td><td>Host name</td><td>IP Address</td></tr>
EOF
    my $leases = read_leases($LEASES);
    for ( sort { $leases->{$a}->{ip} <=> $leases->{$b}->{ip} } grep(/^[a-f0-9][a-f0-9]:[a-f0-9][a-f0-9]:[a-f0-9][a-f0-9]:[a-f0-9][a-f0-9]:[a-f0-9][a-f0-9]:[a-f0-9][a-f0-9]$/i, keys %$leases) ) {
        my ( $mac, $host, $ip ) = ( $_, $leases->{$_}->{host}, $leases->{$_}->{ip} );
        #next unless $mac =~ /^[a-f0-9][a-f0-9]:[a-f0-9][a-f0-9]:[a-f0-9][a-f0-9]:[a-f0-9][a-f0-9]:[a-f0-9][a-f0-9]:[a-f0-9][a-f0-9]$/i;
        print "<tr><td><input type='checkbox' name='$mac'></td><td><b>$mac</b></td><td><b>$host</b></td><td><b>$ip</b></td></tr>\n";
    }
    print <<EOF;
</table>
<input type="submit"> <input type="reset">
</form>
</p>
EOF
}

sub read_leases {
    my $leasefile = shift;
    my %leases;

    my $ret = svn_update();
    return($ret) if (defined $ret and length($ret) > 0);

    open(LEASES, "<$leasefile") || error_out("Could not open lease file: $!");
    my $leases = join("", <LEASES>);
    close(LEASES);

    while ( $leases =~ /host (\S+?) {\s+hardware ethernet ([a-f0-9:]+);\s+fixed-address ([\d\.]+);\s+}/isg ) {
        #print "lease for host $1 at mac $2 is at ip $3\n";
        $leases{$2} = { "host" => $1, "ip" => $3 };
    }

    # Keep this for editing later
    $leases{LEASECONFIG} = $leases;

    return(\%leases);
}

sub error_out {
    my $error = shift;
    my $time = localtime();
    print "Content-Type: text/plain\n\n[$time] Error: $error\n";
    die "[$time] Error: $error\n";
}

# Wrap all svn commands in an Expect so the password is not put on the command line
sub wrap_svn {
    my $cmdline = shift;
    my $timeout = 30;
    my $return_ok = 0;
    my $exp = Expect->spawn($cmdline) || error_out("Cannot spawn svn: $!\n");
    my $password_block = [ "Password for '$USER': ", sub { $return_ok = 1; $_[0]->send("$PASS\n"); exp_continue; } ];
    my $username_block = [ qr'Username', sub { $return_ok = 0; $exp->hard_close() } ];
    my $timeout_block = [ timeout => sub { $return_ok = -1 } ];

    $exp->log_stdout(0);
    $exp->expect($timeout, $password_block, $username_block, $timeout_block);
    $exp->do_soft_close();

    my $ret = $exp->exitstatus();

    if ( $return_ok != 1 or $ret != 0 ) {
        return(1);
    } else {
        return(0);
    }
}

