#!/usr/bin/perl -w
# pop3download.pl - downloads/deletes POP3 and IMAP email from a remote server
# Copyright (C) 2004-2009  Peter Willis
# Version 0.8
# 
# Parts of this program were taken from
# http://iis1.cps.unizar.es/Oreilly/perl/advprog/ch12_06.htm, apparently
# a web resource for the book Advanced Perl Programming,
# written by Sriram Srinivasan.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Library General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

# CHANGELOG

# Since 0.07:
#   * Fix unexpected behavior where temp files went to /tmp/ instead of $HOME/.pop3download/
#   * Error on writing to bad temp filehandle. Fixes issue where a full /tmp/ could cause messages to be erroneously deleted.
#   * Fix possible bug where writing to MDA or tcp socket could cause messages to be erroneously deleted.
#
# Since 0.06:
#   * Added hack to support REFERRAL for mailboxes in Net::IMAP::Simple.
#   * Support IMAPS with Net::IMAP::Simple::SSL.
#   * Support 'service' fetchmail keyword
#   * New 'mailbox' keyword for specifying IMAP mailbox to select for polling
#   * Some code clean-up
#
# Since 0.05:
#   * Work around a bug in IMAP message listing
#
# Since 0.04:
#   * Added IMAP support, for mirroring/pulling an IMAP mailbox, for example
#     to keep the size of the mailbox small
#
# Since 0.03:
#   * Fixed opening of UIDL id file; before it was using the same database
#     for all users of a pop3 server, reusing the same UIDLs for each user.


# TODO:
# * split up deliver_message into smaller functions
#   - add maildir functions as a delivery option


use strict;
use Fcntl;
use POSIX qw(setsid);
#use Email::Simple;
#use Net::IMAP::Simple;
#use Net::POP3;
use IO::Socket;
use DB_File;
use Time::HiRes;
use Sys::Hostname;
use Cwd;
use Carp qw(cluck);

$|=1;
my $VERSION = "0.07";
my $HOME = (getpwuid($>))[7];
my $programdir = "$HOME/.pop3download";
if ( ! -d $programdir ) {
    mkdir($programdir, 0700) || die "Couldn't mkdir \"$programdir\": $!\n";
}

my $daemon = 0;

if ( defined $ARGV[0] and ($ARGV[0] eq "-h" or $ARGV[0] eq "--help") ) {
    usage();
}

emulate_fetchmail();

sub emulate_fetchmail {
    my @polls = parse_fetchmail_config();
    unless ( @polls ) {
        usage();
    }
    if ( $daemon ) {
        # daemonize
        open(STDIN,"/dev/null");
        open(STDOUT,">/dev/null");
        #open(STDERR,">/dev/null");
        #open(STDOUT,">>$HOME/$programdir/pop3download.log");
        open(STDERR,">>$programdir/pop3download.log");
        setsid();
        fork && exit;
        for (;;) {
            sleep($daemon);
            emulate_fetchmail_polls(\@polls);
        }
    } else {
        emulate_fetchmail_polls(\@polls);
    }
    return();
}

sub emulate_fetchmail_polls {

    my $polls = shift;

    foreach my $poll (@$polls) {

        # Check for password
        unless ( $poll->{pass} ) {
            $poll->{pass} = askforpass($poll);
        }
        die "Password not specified?\n" unless $poll->{pass};

        print "Polling user \"$poll->{user}\" @ server \"$poll->{server}\"\n";
        my @ret = poll_server($poll);

        if ( ! @ret ) {
            print STDERR "[".localtime()."] Warning: poll_server($poll->{server}:$poll->{port}) did not return successfully\n";
        }

    }

}

sub poll_server {

    my $poll = shift;
    my ($h_msgs, $num_msgs, $login_state, $uidl_X, $uidl_list);

    if ( ! ($poll->{socket} = connect_to_server($poll)) ) {
        print STDERR "[".localtime()."] Sorry, could not connect to $poll->{server}: $!\n";
        return();
    }

    # Log in
    $login_state = login_to_server($poll);
    if ( ! $login_state ) {
        # login failed. :(
        return();
    }

    # Get number of messages
    $num_msgs = 0;
    if ( $poll->{proto} =~ /^(pop3|apop)$/i ) {
        $num_msgs = $login_state;
    } elsif ( $poll->{proto} =~ /^imap/i ) {
        $num_msgs = $poll->{socket}->select($poll->{mailbox});
    }
    # For some reason server didn't return number of messages. Error?
    if ( !defined $num_msgs or length($num_msgs) < 1 ) {
        if ( ! exists $poll->{socket}->{_errstr} ) {
            print STDERR "[".localtime()."] Error: could not select mailbox $poll->{mailbox}: $! ($@)\n";
            return();
        }
        my $origerr = $poll->{socket}->{_errstr};
        $origerr =~ s/(\r|\n)//g;
        print STDERR "[".localtime()."] Error: could not select mailbox $poll->{mailbox} ($origerr)\n";

        # Here we handle mailbox referrals.
        # This is basically a hack since I think Net::IMAP::Simple should handle this directly.
        # NOTE: This modifies the state of the poll until the program terminates.
        # It will not try to retrieve the old host/port/mailbox!
        # [REFERRAL imap://peter;AUTH=*@hostname/INBOX] There is no replica for that mailbox on this server.
        if ( $origerr =~ /\[REFERRAL (\w+):\/\/(.*@)(.+?):?(\d+)?\/(.+)\]/ ) {
            my ($proto, $args, $host, $port, $path) = ($1, $2, $3, $4, $5);
            $args =~ s/\@$//;
            $poll->{proto} = $proto;
            $poll->{server} = $host;
            # Deduce the port number or reset it to the protocol default.
            # But make sure to override whatever may have been the previous setting
            # so that a previous setting does not become the default and
            # screw up where we were supposed to be redirected to.
            if ( defined $port and length($port) > 0 ) {
                $poll->{port} = $port;
            } else {
                $poll->{port} = (getservbyname($proto,"tcp"))[2];
            }
            $poll->{mailbox} = $path if (defined $path);
            print STDERR "[".localtime()."] Warning: reconnecting to $poll->{server}:$poll->{port}\n";

            # Very possible this could become an 'infinite' loop, which perl
            # will of course kill before about 100 iterations, but still...
            return poll_server($poll);
        }

        # put any additional code here to handle errors when selecting mailbox
        return();
    }

    # Create an anonymous hash of MESSAGEID => SIZE
    if ( $poll->{proto} =~ /^(pop3|apop)$/i ) {

        $h_msgs = $poll->{socket}->list;

    } elsif ( $poll->{proto} =~ /^imap/i ) {

        # This part is weird. Normally $poll->{socket}->list() works on Net::IMAP::Simple,
        # but for some reason it's failing on my imap server now, so this is a workaround.
        # TODO: Fix this because it slows the server down with hundreds of single operations.

        for ( my $i = 1; $i <= $num_msgs; $i++ ) {
            $h_msgs->{$i} = $poll->{socket}->list($i);
        }
    }

    print "Number of msgs in the mailbox: $num_msgs\n";

    ($uidl_X, $uidl_list) = load_uidl($poll);

    # Start downloading messages
    while ( my ($id, $size) = each( %{$h_msgs} ) ) {
        my $ret = 0;
        my $uidl;

        if ( $poll->{proto} =~ /^(pop3|apop)$/i ) {
            $uidl = $poll->{socket}->uidl($id);
            if ( ! defined $uidl or length($uidl) < 1 ) {
                print STDERR "[".localtime()."] Error: UIDL for message \"$id\" not found; skipping.\n";
                return();
            }
        }

        # skip or download the message

        if ( $poll->{proto} =~ /^(pop3|apop)$/i &&
            ( !exists $poll->{options}->{'fetchall'} and exists $$uidl_list{$uidl} )
        ) {

            # message has been seen; skip it.
            print "Skipping seen message \"$uidl\"\n";

        } elsif ( $poll->{proto} =~ /^imap/i &&
            ( !exists $poll->{options}->{"fetchall"} and $poll->{socket}->seen($id) )
        ) {

            # message has been seen; skip it
            print "Skipping seen message \"$id\"\n";

        } else {

            if ( !defined $size or $size < 1 ) {

                print STDERR "[".localtime()."] Error: message $id has no size or size is zero; skipping.\n";
                $ret = 1;

            } else {

                if ( $poll->{proto} =~ /^(pop3|apop)$/i ) {
                    $$uidl_list{$uidl} = 1;
                }
                print "Downloading message $id (".$size."B)\n";
                $ret = deliver_message( $poll, $id, $size );

            }

        }

        $poll->{uidl_list} = $uidl_list;
        cleanup_message($poll, $id, $ret, $uidl);
    }

    $poll->{socket}->quit();

    # should rename this 'close_uidl' really
    save_uidl($uidl_X, $uidl_list);

    print "\n\n";

    return(1);

}

sub load_uidl {
    my $poll = shift;
    my $X = tie my %h, 'DB_File', "$programdir/$poll->{user}\@$poll->{server}.ids", O_RDWR|O_CREAT, 0600, $DB_HASH;
    return(\$X, \%h);
}

sub save_uidl {
    my ($X, $h) = shift;
    undef($$X);
    untie(%$h);
    return(0);
}

sub cleanup_message {

    my ($poll, $id, $ret, $uidl) = @_;

    # default is 'nokeep'
    if ( (!exists $poll->{options}->{'keep'}) and ($ret == 0) ) {

        print "Marking message $id for deletion\n";
        $poll->{socket}->delete($id);

        if ( $poll->{proto} =~ /^(pop3|apop)$/i ) {
            delete $poll->{uidl_list}->{$uidl};
        }

    } elsif ( $ret != 0 ) {

        print STDERR "[".localtime()."] Delivery of message $id seems to have failed; not deleting from server.\n";
        return(1);

    }

    return(0);

}

sub parse_fetchmail_config {

    my @polls = ();
    return() unless (-e "$HOME/.fetchmailrc");

    if ( ! open(CONFIG, "$HOME/.fetchmailrc") ) {
        print STDERR "[".localtime()."] Could not open \"$HOME/.fetchmailrc\": $!\n";
        return();
    }

    my $ret = read(CONFIG, my $buffer, -s "$HOME/.fetchmailrc");

    return() unless $ret;

    close(CONFIG);

    $buffer =~ s/^\s*#.*$//mg; # remove comments
    $buffer =~ s/(\r|\n)/ /g; # remove newlines
    $buffer =~ s/\s+/ /g; # make multiple spaces into a single space
    $buffer =~ s/poll/\n\npoll/g; # make each word "poll" be on its own new line

    foreach my $line (split(/\n/,$buffer)) {

        my ($server, $port, $proto, $user, $password, $is, $mda, $options, $mailbox);
        if ( $line =~ /^poll ([a-zA-Z0-9.-]+)/ ) {

            $server = $1;
            $proto = $2 if ( $line =~ /proto(col)? (\S+)/g );
            $user = $2 if ( $line =~ /user(name)? (\S+)/g );
            $password = $1 if ( $line =~ /password (\S+)/g );
            $is = $1 if ( $line =~ /is (\S+)/g );
            $port = $1 if ( $line =~ /port (\d+)/g );
            $port = defined $port ? $port : $line =~ /service (\d+)/g ? $1 : $line =~ /service (\S+)/g ? (getservbyname($1,"tcp"))[2] : undef;
            $mailbox = $1 if ( $line =~ /mailbox (\S+)/g );

            if ( $line =~ /mda ('|")/ ) {

                my $quot = $1;
                $mda = $1 if ( $line =~ /mda $quot(.+)$quot/ );

            } else {

                $mda = $1 if ( $line =~ /mda (\S+)/ );

            }

            $options .= " fetchall" if ( $line =~ /\Wfetchall\W/ );
            $options .= " keep" if ( $line =~ /\Wkeep\W/ );
            $options .= " forcecr" if ( $line =~ /\Wforcecr\W/ );
            #print "line $line\n\t$server, $proto, $user, $password\n";

            my $hr = {
                    server => $server, proto => $proto, user => $user,
                    pass => $password, is => ( $is ? $is : "" ), mda => ($mda ? $mda : ""),
                    port => ( $port ? $port : (getservbyname($proto,"tcp"))[2] ),
                    mailbox => ( $mailbox ? $mailbox : "INBOX" ),
                    options => {}
                };

            if ( $options ) {
                foreach my $option ( split(/\s+/, $options) ) {
                    $hr->{options}->{$option} = 1;
                }
            }

            push( @polls, $hr );

        } else {

            if ( $line =~ /set daemon (\d+)/ ) {
                $daemon = $1;
            }

        }

    }

    return(@polls);

}

sub deliver_message {

    my ($poll, $id, $size) = @_;

    # we create a temp file and transfer the email to it, then open it back
    # up and scan for %F (the From: field) to be used in the mda if needed.
    # 
    # also, this could be useful in a home-grown implementation of Maildir
    # support; in cases where the user didn't have an MDA or MTA and just
    # wanted to store their email into a Maildir for browsing with their
    # IMAP client and their IMAP server, we could simply link this temp
    # file into the Maildir and delete the temp file. mbox support might
    # also be possible; i'll have to look up any relevant RFC's and whatnot,
    # but i believe new messages are simply written to the end of the mail
    # spool file.

    # create temp file variable
    my $messagefd = my_new_tmpfile();

    # open temp file for writing
    if ( !defined $messagefd ) {
        print STDERR "[".localtime()."] Error opening tmpfile read-write: $!\n";
        return(1);
    }

    # "get" the message, sending it to $messagefd
    my $msgfh = $poll->{socket}->getfh($id);
    my $bytes_read = 0;
    while ( my $read = read($msgfh, my $buffer, 4096) ) {
        # incase $messagefd is actually a bad file descriptor or some crap
        if ( ! print $messagefd $buffer ) {
            print STDERR "[".localtime()."] Error writing to tmpfile: $!\n";
            return(1);
        }
        $bytes_read += $read;
    }
    if ( $poll->{proto} =~ /^(pop3|apop)/i ) {
        # do not close $msgfh; we will get an EOF, then just don't use that fh again (apparently)
        1;
    } elsif ( $poll->{proto} =~ /imap/i ) {
        # this should also unlink the tmpfile associated with $msgfh
        close($msgfh);
    }

    if ( $bytes_read < 1 ) {
        print STDERR "[".localtime()."] Error reading from file handle: 0 bytes read\n";
        return(1);
    }

    # It seems like it's normal to have our bytes_read not equal $size... Don't know why.
    #if ( $bytes_read < $size ) {
    #    print STDERR "[".localtime()."] Warning: msg $id bytes_read $bytes_read, msg size $size\n";
    #}

    # go to the beginning
    seek($messagefd, 0, 0);

    my $writingfd;

    if ( defined $poll->{mda} and length $poll->{mda} > 0 ) {
        # if $mda contains %F ...
        if ( $poll->{mda} =~ /\%F/ ) {            
            my $from;

            # parse out the From line for passing to the mda
            while ( <$messagefd> ) {
                chomp;
                
                if ( $_ eq "" ) {
                    # if the line is empty, means we finished parsing the headers.
                    last;
                } elsif ( $_ =~ /^From: .+$/ ) {
                    # find the From: line and replace %F in $mda with it.
                    # NOTE: THIS DOES NOT PARSE OUT THE EMAIL ADDRESS CORRECTLY!
                    # BUYER BEWARE!
                    if ( $_ =~ /<?\[?([\@a-zA-Z0-9\-_.\t ]+)\]?>?\s*$/ ) {
                        $poll->{mda} =~ s/\%F/\"$1\"/g;
                    }
                }
            }
        }

        # replace %T with "is USERNAME here" value
        $poll->{mda} =~ s/\%T/\"$poll->{is}\"/g if ( defined $poll->{is} );

        # open the $mda pipe
        if ( ! open($writingfd, "| $poll->{mda}") ) {
            print STDERR "[".localtime()."] Couldn't open pipe to mda \"$poll->{mda}\": $!\n";
            return(1);
        }
    } else {
        # If no MDA specified, connect to localhost port 25 (sendmail anyone?)
        $writingfd = IO::Socket::INET->new(PeerAddr => "127.0.0.1", PeerPort => 25, Proto => "tcp");
        if ( ! $writingfd ) {
            print STDERR "[".localtime()."] Couldn't open socket to 127.0.0.1:25: $!\n";
            return(1);
        }
    }

    seek($messagefd, 0, 0);

    while ( read($messagefd, my $buffer, 4096,) ) {
        # forcecr option; turns bare CR or LF into CRLF.
        # hard-coded values to conform to internet standards
        # and move away from operating system porting issues.
        if ( exists $poll->{options}->{forcecr} ) {
            $buffer =~ s/\013[^\010]/\013\010/g;
            $buffer =~ s/[^\013]\010/\013\010/g;
        }
        if ( ! syswrite($writingfd, $buffer) and length($buffer) > 0 ) {
            print STDERR "[".localtime()."] Error writing to mda: $!\n";
            return(1);
        }
    }

    close($messagefd);

    close($writingfd);

    # wrap it up
    if ( defined $poll->{mda} ) {
        if ( $! == 0 ) {
            return($?);
        }
    }

    return(0);

}

## sample filename:
## 1096702001.M816693P3286V0000000000000306I0009DB28_0.meatwad
sub open_maildir_file {
    my $maildir = shift;
    my @time;
    my @stat;
    my $filename;
    my $hostname;
    my $fh;
    my $inctime = 0;
    my $cwd = getcwd();
    CREATEMAILDIRFILE:
    chdir($cwd); # put us back to the original dir
    if ( ! chdir($maildir) ) {
        print STDERR "[".localtime()."] Error: could not chdir($maildir): $!; mail not delivered.\n";
        return();
    }
    @time = Time::HiRes::gettimeofday();
    @stat = stat(".");
    if ( ! @stat ) {
        print STDERR "[".localtime()."] Error: stat . didn't work??\n";
        return();
    }
    # The Makings Of A Unique File Name, Sort Of.
    # filename = time(), mtime(), process,
    $filename = "$time[0].M$time[1]P$$";
    # device name in hex with up to 17 leading zero's,
    $filename .= "V" . sprintf("%017lx", $stat[0]);
    $filename .= "I" . sprintf("%08lx", $stat[1]);
    $hostname = hostname();
    if ( !defined $hostname or length($hostname) < 1 ) {
        # no hostname for some weird reason, so use random data instead.
        # hostname will be random data in hex-digits.
        my $rndhostlen = 10; # arbitrary
        if ( -e "/dev/urandom" ) {
            my $buffer;
            if ( ! open(RND, "/dev/urandom") ) {
                goto CRAPRNDREAD;
            }
            if ( ! read(RND, $buffer, $rndhostlen) ) {
                goto CRAPRNDREAD;
            }
            $hostname = map { sprintf "%02lx", ord($_) } split //, $buffer;
            close(RND);
        } else {
            # last ditch effort incase this isn't a Linux box
            CRAPRNDREAD:
            srand();
            for (my $i=0;$i<$rndhostlen;$i++) {
                $hostname .= sprintf "%02lx", (int(rand(26))+97);
            }
        }
    }

    $filename .= ".$hostname";

    # filename is ready; now try and open it.
    if ( -e "tmp/$filename" ) {
        if ( $inctime > ((60*60)*24) ) {
            print STDERR "[".localtime()."] Error: i've been trying to create this temp file for 24 hours! ENOUGH IS ENOUGH!\n";
            return();
        }
        sleep 2;
        $inctime += 2;
        goto CREATEMAILDIRFILE;
    }

    if ( ! open($fh, ">tmp/$filename") ) {
        print STDERR "[".localtime()."] Error: could not create temp file \"tmp/$filename\": $!\n";
        return();
    }

    return($fh, $filename);
}

sub close_maildir_file {

    my $maildir = shift;
    my $maildirfh = shift;
    my $mailfile = shift;

    if ( ! close($maildirfh) ) {
        print STDERR "[".localtime()."] Error: closing an already closed fh for mail file \"$mailfile\"\n";
        return 1;
    }

    if ( ! chdir($maildir) ) {
        print STDERR "[".localtime()."] Error: chdir($maildir) failed: $!; mail stuck in tmp?\n";
        return 1;
    }

    if ( ! -d "new" or ! -d "tmp" ) {
        print STDERR "[".localtime()."] Error: \"new\" or \"tmp\" directory not found; is \"$maildir\" a valid maildir?\n";
        return 1;
    }

    if ( ! -e "tmp/$mailfile" ) {
        print STDERR "[".localtime()."] Error: trying to close inexistant mail file \"tmp/$mailfile\"\n";
        return 1;
    }

    if ( ! rename("tmp/$mailfile", "new/$mailfile") ) {
        print STDERR "[".localtime()."] Error: renaming \"tmp/$mailfile\" to \"new/$mailfile\" failed: $!\n";
        return 1;
    }

    return 0;

}

sub connect_to_server {

    my $poll = shift;
    my $m;

    if ( $poll->{proto} =~ /^(pop3|apop)$/i ) {
        use Net::POP3;
        $m = Net::POP3->new( "$poll->{server}:$poll->{port}" ); # Name of POP server
    } elsif ( lc $poll->{proto} eq "imap" ) {
        use Net::IMAP::Simple;
        $m = Net::IMAP::Simple->new( "$poll->{server}:$poll->{port}" );
        # Hack to force writing a tmpfile where we want it
        no warnings 'redefine';
        *IO::File::new_tmpfile = \&my_new_tmpfile;
    } elsif ( lc $poll->{proto} eq "imaps" ) {
        use Net::IMAP::Simple::SSL;
        $m = Net::IMAP::Simple::SSL->new( "$poll->{server}:$poll->{port}" , SSL_use_cert => 0, SSL_verify_mode => 0x00 );
        # Hack to force writing a tmpfile where we want it
        no warnings 'redefine';
        *IO::File::new_tmpfile = \&my_new_tmpfile;
    }

    return($m);

}

sub login_to_server {

    my $poll = shift;
    my $n;

    if ( $poll->{proto} =~ /^(pop3|imap)/i ) {
        $n = $poll->{socket}->login($poll->{user}, $poll->{pass});
    } elsif ( lc $poll->{proto} eq "apop" ) {
        $n = $poll->{socket}->apop($poll->{user}, $poll->{pass});
    }

    if ( ! $n ) {
        print STDERR "[".localtime()."] Login for \"$poll->{user}\@$poll->{server}\" not correct\n";
    }

    return($n);

}

sub askforpass {

    my $poll = shift;

    print $poll->{user}.'@'.$poll->{server}."'s password please: ";
    system("stty -echo");
    my $pass = <STDIN>;
    system("stty echo");
    print "\n";
    chomp $pass;

    return($pass);

}

sub usage {

    $0 =~ s/^.+[\/]([^\/]+)$/$1/g;
    print <<EOF;
$0 Version $VERSION
Usage: $0
  $0 parses \$HOME/.fetchmailrc and fetches mail from each section
  starting with "poll".
  
  Check the fetchmail(1) man page for details on configuration.
EOF
    exit(1);

}

# This is a hack to work around Net::IMAP::Simple using new_tmpfile without letting me specify where the tmpfile goes.
# Opens a writeable tmpfile.
# File is anonymous (unlinked after creation).
sub my_new_tmpfile {
    my $file;
    do {
        my ($time, $utime) = Time::HiRes::gettimeofday();
        $file = "$programdir/$$-$time.$utime";
        if ( -e $file ) {
            sleep 1;
        }
    } while ( -e $file );
    if ( open(my $fh, "+>$file") ) {
        # unlink after open makes it gone from the filesystem (effectively) but the OS keeps it open and can perform operations as if it still existed
        unlink($file);
        return $fh;
    } else {
        cluck "Error: could not create new_tmpfile ($!)";
        return undef;
    }
}


