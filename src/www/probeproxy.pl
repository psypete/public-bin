#!/usr/bin/perl
#

$|=1;
use strict;
use IO::Socket::INET;
use Carp qw(carp);
use Data::Dumper;

if ( ! @ARGV ) {
    die "Usage: $0 HOST [..]\n";
}

main();
exit;


sub main {
    my @request_options = (
        { "crlf" => [ "\r\n", "\n" ] },
        { "peerhost" => [ @ARGV ] },
        { "peerport" => [ "80", "443" ] },
        { "http_ver" => [ "1.0", "1.1" ] },
        { "method" => [ "GET", "POST", "PUT", "HEAD", "OPTIONS", "TRACE" ] },
        { "uri" => [ "/", "http://www.google.com/" ] },
        { "pass_host" => [ undef, @ARGV ] }
    );

    foreach my $host ( @ARGV ) {
        my $iterobj1 = { };

        my $itercode1 = sub {
            my ($self1, $k1, $v1) = @_;
            my $iterobj2 = { "parent_i" => $self1->{"i"} };

            my $itercode2 = sub {
                my ($self2, $k2, $v2) = @_;

                if ( $self2->{"parent_i"} == $self2->{"i"} ) {
                    #print "code2: parent_i == i ($self2->{i})\n";
                    return;
                }
                
                foreach my $entry ( @$v2 ) {
                    #print "child_i $self2->{i}: setting $k2 = \"$entry\"\n";
                    $self2->{"session"}->request( $k2 => $entry );
                    print "request: \"" . $self2->{"session"}->request . "\"\n";
                }
            };

            foreach my $entry ( @$v1 ) {

                #print "parent_i: setting $k1 = \"$entry\"\n";
                my $sess = ProbeProxy->new( "peerhost" => $host );
                $sess->request( $k1 => $entry );

                $iterobj2->{"session"} = $sess;
                iterate_array_of_hashes($iterobj2, $itercode2, \@request_options);
            }
    
        };

        iterate_array_of_hashes($iterobj1, $itercode1, \@request_options);
    }

    #my $stuff = $sess->request;
    #print "request: \"$stuff\"\n";
    #$sess->do_http;
    #my $content = $sess->response;
    #print "result: \"$content\"\n";
}

sub iterate_array_of_hashes {
    my $self = shift;
    my $code = shift;
    my $list = shift;

    for ( my $_i=0; $_i < @$list; $_i++ ) {
        my $hash_arg = $list->[$_i];
        $self->{'i'} = $_i;

        foreach my $k ( keys %$hash_arg ) {
            my $v = $hash_arg->{$k};
            &$code($self, $k, $v);
        
        }
    }
}


##############################################################################################
package ProbeProxy;

sub new {
    my $self = shift;
    my %h = @_;
    my %defs = ( "peerhost" => undef, "peerport" => 80, "proto" => "tcp" );
    $self->put_defaults(\%h, \%defs);
    return bless \%h, $self;

}

sub do_http {
    my $self = shift;
    my $conn = IO::Socket::INET->new(PeerAddr => $self->{"peerhost"}, PeerPort => $self->{"peerport"}, Proto => 'tcp');
    if ( ! $conn ) {
        carp("Could not connect to $self->{peerhost}:$self->{peerport}: $!\n");
        return undef;
    }
    print $conn $self->request;
    while ( <$conn> ) {
        push( @{ $self->{"_response_buffer"} }, $_ );
    }
    close($conn);
}

sub request {
    my $self = shift;
    my %args = @_;
    if ( @_ ) {
        $self->craft_request(%args);
    }
    return $self->{"_request_data"};
}

sub response {
    my $self = shift;
    return join( "", @{ $self->{"_response_buffer"} } );
}

sub craft_request {
    my $self = shift;
    my %args = @_;
    my %defs = ( "method" => "GET", "http_ver" => "1.0", "uri" => "/", "crlf" => "\r\n" );
    $self->put_defaults(\%args, $self); # global defaults override internal defaults
    $self->put_defaults(\%args, \%defs); # internal defaults
    #print "craft args: " . Data::Dumper::Dumper(\%args) . "\n";

    $self->{"_request_data"} = sprintf("%s %s HTTP/%s%s", $args{method}, $args{uri}, $args{http_ver}, $args{crlf});

    $self->{"_request_data"} .= sprintf("Host: %s%s", $args{pass_host}, $args{crlf}) if (defined $args{"pass_host"});

    $self->{"_request_data"} .= sprintf("%s", $args{crlf});
}

sub put_defaults {
    my $self = shift;
    my ($dst, $src) = @_;
    while ( my ($k,$v) = each %$src ) {
        if ( !exists $dst->{$k} ) {
            $dst->{$k} = $v;
        }
    }
}

