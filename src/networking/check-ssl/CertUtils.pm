#!/usr/bin/perl
package CertUtils;

use strict;
use warnings;

use IPC::Open2;

push(@INC, ".");
use PortableTime qw(timelocal timegm localtime gmtime);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(download_issuer certs_linked);

our $VERSION = "1.1";
our $VERBOSE = 0;


sub new {
    my $class = shift;
    my $self = { 'text' => undef, 'data' => undef, 'verbose' => $VERBOSE, 'file' => undef };
    my %args;

    bless($self, $class);

    if ( @_ == 1 ) {
        $self->file( shift );
    }
    elsif ( @_ > 1 ) {
        %args = @_;
        map { $self->{$_} = $args{$_} if defined $args{$_} } keys %$self;
    }

    $self->verbose($VERBOSE);

    if ( $self->file and ! $self->load_certificate ) {
        print STDERR "$0: ERROR: Could not load certificate! Object creation failure\n";
        return undef;
    }

    return $self;
}


sub download_issuer {
    my $self = shift;

    my $uri = shift;
    my $digest = Digest::MD5::md5_hex($uri);
    my ($fd, $raw);

    print STDERR "$0: download_issuer($uri)\n" if $self->verbose;

    if ( -e "ca-issuer-$digest.cer" ) {

        print STDERR "$0: Using cached issuer ca-issuer-$digest.cer\n" if $self->verbose >= 2;
        $self->read_file("ca-issuer-$digest.cer");

    } else {

        print STDERR "$0: Downloading CA Issuer $uri\n";

        open(PIPE, "lwp-request \"$uri\" |") || die "Error: cannot open pipe: $!";
        #$raw = [ map { s/(\r|\n)//g; $_ } <PIPE> ];
        # DO NOT REMOVE \r or \n! This may be binary DER certificate data
        $raw = [ <PIPE> ];
        close(PIPE);

        $self->raw( $raw );

        # Cache the issuer cert
        open($fd, ">ca-issuer-$digest.cer") || die "Error: cannot write issuer to disk: $!";
        # DO NOT ADD \n! This may be binary DER certificate data
        print $fd @$raw;
        close($fd);

    }

    if ( $self->load_certificate($uri) ) {
        return $self;
    }

    return undef;
}


sub read_file {
    my $self = shift;
    my $file = shift;
    $self->file($file) if (defined $file and !defined $self->file);
    $file ||= $self->file;

    open(my $fd, "<$file")||die"Error: cannot open file '$file': $!";
    my @data = <$fd>;
    close($fd);

    $self->raw( \@data );
}


# Takes a file and reads it,
# or takes an array ref of read data.
# Converts it to text if it's in PEM or DAR format.
sub load_certificate {
    my $self = shift;
    my $uri = shift;

    my ($inform, $fmt);
    
    $self->read_file unless $self->raw;
    my $raw = $self->raw;

    if ( defined $uri and length $uri ) {
        if ( $uri =~ /\.p7[bc]$/i ) {
            $fmt = "pkcs7";
        } elsif ( $uri =~ /\.(p12|pfx)$/i ) {
            $fmt = "pkcs12";
        } else {
            $fmt = "x509";
        }
    }

    # If it's already been converted to openssl text output
    if ( $raw->[0] =~ /^Certificate:/ ) {
        undef $inform;
        $self->text( $raw );
    }
    elsif ( grep(/BEGIN PKCS(7|12)/, @$raw) ) {
        $inform = "PEM";
        if ( $1 eq "7" ) {
            $fmt = "pkcs7";
        } elsif ( $1 eq "12" ) {
            $fmt = "pkcs12";
        }
    }
    elsif ( grep(/BEGIN CERTIFICATE/, @$raw) ) {
        # PEM format
        $inform = "PEM";
    }
    else {
        # There's one more format out there but I haven't seen it so i'm ignoring it
        $inform = "DER";
    }

    if ( defined $inform and length $inform ) {
        # Convert cert data to text

        print STDERR "$0: Decoding $inform certificate data\n" if $self->verbose >= 2;

        my $readcmd;
        
        if ( !defined $fmt or $fmt eq "x509" ) {
            $readcmd = "openssl x509 -noout -text -inform $inform";
        } elsif ( $fmt eq "pkcs12" ) {
            $readcmd = "openssl pkcs12 -cacerts -nokeys -inform $inform | openssl x509 -noout -text";
        } elsif ( $fmt eq "pkcs7" ) {
            $readcmd = "openssl pkcs7 -inform $inform -noout -text -print_certs";
        }

        print STDERR "$0: cmd: $readcmd\n" if $self->verbose >= 2;
        my $pid = open2(my $readfd, my $writefd, "$readcmd") || die "Error: cannot open cmd '$readcmd': $! ($@)";

        print $writefd join("", @$raw);
        close($writefd);

        # Set the data array
        $self->text( [ map { s/(\r|\n)//g; $_ } <$readfd> ] );

        close($readfd);

        # Remember to reap open2() process
        waitpid($pid, 0);
    }

    if ( ! $self->text ) {
        print STDERR "$0: Error: could not load certificate data for file '" . $self->file . "'\n";
        return 0;
    }

    my @res = $self->process_text;
    $self->certificates( @res );

    return @res ? 1 : 0;
}


sub process_text {
    my $self = shift;

    my $text = $self->text;
    my %h;
    my @hashes;

    for ( my $i = 0; $i < @$text; $i++ ) {
        $_ = $text->[$i];

        if ( /^Certificate:\s*$/ ) {
            if ( @hashes > 0 ) {
                push( @hashes, \%h );
                %h = ();
            }
        
        } elsif ( /CA Issuers - URI:(.+)/ ) {
            $h{'ca_issuers'} = [] if (!exists $h{'ca_issuers'});
            push( @{$h{'ca_issuers'}}, $1);

        } elsif ( /X509v3 Subject Key Identifier:/ ) {
            $_ = $text->[++$i];
            if ( /^\s+(\w\w:\w\w:\w\w:\w\w:.+)$/ ) {
                # subject key identifier has no 'keyid'
                $h{'subj_key_ident'} = $1;
            }

        } elsif ( /X509v3 Authority Key Identifier:/ ) {
            $_ = $text->[++$i];
            if ( /^\s+keyid:(.+)$/ ) {
                $h{'auth_key_ident'} = $1;
            }

        } elsif ( /^\s+Issuer: (.+)$/ ) {
            $h{'issuer'} = $1;

        } elsif ( /^\s+Subject: (.+)$/ ) {
            $h{'subject'} = $1;

        } elsif ( /^\s+Validity\s*$/ ) {

            for ( my $j=0; $j<3; $j++ ) {
                $_ = $text->[$i+$j];

                if ( /^\s+Not (Before|After)\s*: (.+)$/ ) {
                    my ($when, $time) = ($1, $2);
                    #print STDERR "Time: $when - $time\n";

                    my $epoch = extract_time($time);
                    if ( $when eq "Before" ) {
                        $h{'created'} = $epoch;
                    } 
                    elsif ( $when eq "After" ) {
                        $h{'expires'} = $epoch;
                    }
                    #} else {
                    #print STDERR "$0: Warning: Not valid time: '$_'\n" if $self->verbose >= 2;
                }

            }

        }
    }

    push( @hashes, \%h );

    return @hashes;
}


sub check_exp {
    my $o = shift;
    my $cert = shift;

    print "Certificate Subject: '$cert->{'subject'}'\n" if $o->verbose;

    my ($c,$e) = ( scalar gmtime($cert->{'created'}) , scalar gmtime($cert->{'expires'}) );
    print "Created: $c\n" if $o->verbose >= 2;
    print "Expires: $e\n" if $o->verbose >= 2;

    my $time = time();
    my $timeleft = ($cert->{'expires'} - $time) || 1;

    my $dleft = sprintf("%.2f",( ( ($timeleft / 60) / 60 ) / 24 ) );


    if ( !defined $cert->{'expires'} or length $cert->{'expires'} < 1 or $cert->{'expires'} < 1 or $timeleft <= 1 ) {
        print "ERROR: Certificate ".$o->file." has expired! timeleft $timeleft dleft $dleft\n";
        return 0;
    }
    else {
        print "Certificate ".$o->file." is still valid ($dleft days until it expires)\n" if $o->verbose;
        return 1;
    }
}


### end of methods
### start of functions


sub extract_time {
    my $datetime = shift;
    chomp $datetime;

    my %mon = qw(Jan 0 Feb 1 Mar 2 Apr 3 May 4 Jun 5 Jul 6 Aug 7 Sep 8 Oct 9 Nov 10 Dec 11);

    # Jun 23 12:14:45 2019 GMT
    if ( $datetime =~ /^(\w+)\s+(\d+)\s+(\d+):(\d+):(\d+)\s+(\d+)\s+(\w+)$/ ) {
        my ($month, $day, $hour, $min, $sec, $year, $loc) = ($1, $2, $3, $4, $5, $6, $7);
        print STDERR "$0: Time found (mon $month d $day h $hour m $min s $sec y $year l $loc)\n" if $VERBOSE >= 3;

        #my $t = timelocal( $sec, $min, $hour, $day, $mon{$month}, $year );
        my $t = timegm( $sec, $min, $hour, $day, $mon{$month}, $year );
        #print STDERR "$0: Found t $t (".scalar gmtime($t).")\n";

        return $t;
    } else {
        print STDERR "$0: Warning: could not match on date-time '$datetime'\n";
    }

    return undef;
}


# Compares $_[0] subject to $_[1] auth/issuer.
# if $_[1] not passed, uses $_[0] (returns true if root CA)
sub certs_linked {
    my $cert = shift;
    my $cert2 = shift;
    my @pair1 = ('subj_key_ident', 'auth_key_ident');
    my @pair2 = ('subject', 'issuer');

    if  (!defined $cert2) {
        $cert2 = $cert;
    }

    for ( (\@pair1, \@pair2) ) {
        if (
            (exists $cert->{$_->[0]} and length($cert->{$_->[0]}) > 0) 
            and (exists $cert2->{$_->[1]} and length($cert2->{$_->[1]}) > 0)
        ) {

            if ( $cert->{$_->[0]} eq $cert2->{$_->[1]} ) {
                print STDERR "$0: Cert1 $_->[0] '$cert->{$_->[0]}' equals Cert2 $_->[1] '$cert2->{$_->[1]}'\n" if $VERBOSE;
                return 1;

            } else {
                print STDERR "$0: Cert1 $_->[0] '$cert->{$_->[0]}' NOT equals Cert2 $_->[1] '$cert2->{$_->[1]}'\n" if ($VERBOSE >= 2);
            }

        }
    }

    return 0;
}


sub AUTOLOAD {
    my @accessors = qw(raw text file verbose certificates);
    our $AUTOLOAD;
    if ($AUTOLOAD =~ /::(\w+)$/ and grep $1 eq $_, @accessors) {
        my $field = $1;
        {
            no strict 'refs';
            *{$AUTOLOAD} = sub { $_[0]->{$field} = $_[1] if defined $_[1]; $_[0]->{$field} };
        }
        goto &{$AUTOLOAD};
        #} else {
        #    die "Error: $AUTOLOAD does not understand $_[0]";
    }
}


1;

