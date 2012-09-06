#!/usr/bin/perl -wT
# auth_login.pl - user/pass authentication script for openvpn
# Copyright (C) 2010 Peter Willis <peterwwillis@yahoo.com>
# 
# This script will create a locally-modified database of usernames and SHA-256
# encrypted passwords. Keep in mind that this is run by openvpn and thus the
# database of passwords is not separate from openvpn, so any security hole in
# openvpn potentially opens up this database for reading. In the future this
# access should be separated from openvpn for security purposes.
# 
# The proper way to invoke this script is with the openvpn options
# "--auth-user-pass-verify auth_login.pl via-env".
#
# To create a username and password in the database run:
#   auth_login.pl passwd USER PASS
# To list the users in the database, run:
#   auth_login.pl list
# To delete a user in the database, run:
#   auth_login.pl delete USER
#
# It is recommended you make the database and other files read-only for openvpn's
# user and read-write for your own user. To do this, first create the database
# and other files with your user, then change the permissions to group-readable
# and change the group to one which includes the openvpn user.
#

use strict;
use DB_File;
use IO::Socket::UNIX;

my $AUTH_DIR = "/home/psypete/backup/uno.syw4e.info/etc/openvpn/auth";
my $DBASE = "$AUTH_DIR/auth_login.db";
my $LOCKDIR = $AUTH_DIR;

# 
# Should not need to modify anything below this line
# 


$ENV{PATH} = "/bin:/usr/bin";
umask(0077);

my ($USERNAME, $PASSWORD) = ($ENV{"username"}, $ENV{"password"});
# Feed one of these with your salt to determine the hash cipher
my ($MD5_SALT, $BLOWFISH_SALT, $SHA256_SALT, $SHA512_SALT) = ("1", "2a", "5", "6");

my ($X, %h);

# good, not using the 'file' method for passing auth
if ( @ARGV and ! -f $ARGV[0] ) {
    parse_command(@ARGV);
} elsif ( @ARGV and -f $ARGV[0] ) {
    die "Error: this script does not yet handle file-based auth\n";
}

if ( !defined $USERNAME or !defined $PASSWORD or ! length $USERNAME or ! length $PASSWORD ) {
    die "Error: need a username and password\n";
}

# Connect to server
my $cli = IO::Socket::UNIX->new(Type => SOCK_STREAM, Peer => $CLI_SOCKFILE) || die "Error: could not connect to socket $CLI_SOCKFILE: $! ($@)\n";

if ( login_ok($USERNAME, $PASSWORD) ) {
    exit(0);
} else {
    exit(1);
}

# TODO: make this connect to something else to perform the auth so openvpn can't
# expose the local password database
sub login_ok {
    my ($u, $p) = @_;

    $u = clean_uname($u);

    my $ok = 0;
    my $lock = _lock("login");
    opendb(O_RDONLY);

    print "keys: ", keys %h, "\n";

    if ( exists $h{"user:$u"} ) {
        my $c = crypt($p, $h{"user:$u"});
        print "u $u p $p c $c h\{user:$u\} $h{'user:$u'}\n";
        if ( $c eq $h{"user:$u"} ) {
            print "Password authentication successful\n";
            $ok = 1;
        }
    } else {
        print "User \"$u\" does not exist\n";
    }

    if ( ! $ok ) {
        print "Password authentication failed\n";
    }

    closedb();
    _unlock($lock);

    return $ok;
}

sub parse_command {
    my ($cmd, @options) = @_;

    my $lock = _lock("auth");
    opendb(O_RDWR);

    if ( $cmd eq "passwd" ) {

        if ( @options < 2 ) {
            die "Usage: $0 $cmd USER PASS\nSets user=pass in auth database\n";
        }
        my ($user,$pass) = ( clean_uname($options[0]), $options[1]);
        my $salt = new_salt();
        
        # NOTE: Change the variable between the two '$' characters to
        # a salt cypher that your system supports ('$MD5_SALT' on most systems,
        # '$BLOWFISH_SALT' on Linux distros that support it and OpenBSD,
        # '$SHA512_SALT' on Glibc 2.7 or later. The most time-consuming hash
        # to crack is '$BLOWFISH_SALT'.
        my $crypted = crypt($pass, "\$$SHA512_SALT\$$salt\$");

        $h{"user:$user"} = $crypted;
        print "Set passwd for $user to $crypted successfully\n";

    } elsif ( $cmd eq "list" ) {

        my @users;
        foreach my $user ( keys %h ) {
            push @users, $1 if ($user =~ /^user:(.+)$/);
        }
        print "Users: " , join(", ",@users) , "\n";

    } elsif ( $cmd eq "delete" ) {

        if ( @options < 1 ) {
            die "Usage: $0 $cmd USER\nDeletes USER from auth database\n";
        }
        my $user = clean_uname($options[0]);
        delete $h{"user:$user"};

    }

    closedb();
    _unlock($lock);

    exit(1);

}

sub opendb {
    my $flags = shift; # O_RDONLY or O_RDWR
    if ( ! -f $DBASE ) {
        $flags = O_CREAT|$flags;
    }
    $X = tie %h, 'DB_File', $DBASE, $flags, 0600, $DB_HASH;
    if ( !defined $X ) {
        print "Error: could not tie database: $! ($@)\n";
    } else {
        use Data::Dumper;
        print "Tied database\nX = " . Dumper($X) . "\nh = " . Dumper(\%h) . "\n";
    }
}

sub closedb {
    undef $X;
    untie %h;
}

# by default does an exclusive blocking flock on "subsys.lck"
sub _lock {
    my $file = "$LOCK_DIR/auth_login-" . shift(@_) . ".lck";
    my $fd;
    if ( ! -e $file ) {
        sysopen($fd, $file, O_RDWR|O_CREAT|O_EXCL, 0600) || die "Error: could not open lock file $file: $!\n";
    } else {
        sysopen($fd, $file, O_RDWR, 0600) || die "Error: could not open lock file $file: $!\n";
    }
    flock($fd, 2); # exclusive lock
    return $fd;
}

sub _unlock {
    my $fd = shift(@_);
    flock($fd, 8); # unlock
    close($fd);
}

sub clean_uname {
    my $s = $_[0];
    $s =~ s/[^a-zA-Z0-9_.\@-]/_/g;
    return $s
}

# return a 16 character salt for crypt()
sub new_salt {
    my $salt = '';
    # 'a-zA-Z0-9/.'
    my @chars = ( (map { chr } 46..57), (map { chr } 65..90) , (map { chr } 97..122) );
    for ( 1..16 ) {
        $salt .= $chars[rand(@chars)];
    }
    return $salt;
}

