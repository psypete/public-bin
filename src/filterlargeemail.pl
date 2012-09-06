#!/usr/bin/perl
# filterlargeemail.pl - filter e-mails and compress large parts
# Copyright (C) 2009 Peter Willis <peterwwillis@yahoo.com>

use strict;
use Email::MIME;
use Email::MIME::Modifier;
use Clone qw(clone);
use IO::Compress::Gzip qw(gzip $GzipError :level);
use MIME::Base64;
use Data::Dumper;

my ( $VERBOSE, $MESSAGE, $MSG_SIZE, $MIN_MSG_SIZE, $MAX_MSG_SIZE );
$VERBOSE=0;
$MIN_MSG_SIZE = 102400; # 100k
$MAX_MSG_SIZE = 107374182400; # 1gb


while ( sysread(STDIN, my $buf, 8192) ) {
    $MSG_SIZE += length($buf);
    $MESSAGE .= $buf;
    if ( $MSG_SIZE > $MAX_MSG_SIZE ) {
        print STDERR "$0: Message is too big! ($MSG_SIZE > $MAX_MSG_SIZE)\n";
        exit 1;
    }
}

if ( $MSG_SIZE < $MIN_MSG_SIZE ) {
    print STDERR "$0: Message was too small. ($MSG_SIZE < $MIN_MSG_SIZE)\n" if ($VERBOSE);
    exit 0;
}

handle_message(\$MESSAGE);

sub loopart {
    my $e = shift;
    print "Total parts: " . scalar($e->parts) . "\n";
    for ( $e->parts ) {

sub handle_message {
    my $msg = shift;
    my $email = Email::MIME->new( $$msg );
    my $MIN_FIRSTPART_SIZE = 150;
    my $MAX_FIRSTPART_SIZE = 10240;
    my @parts = $email->parts;
    my (@original_parts, @compress_parts, $body, $si);

    loopart($email);
    exit(0);

    # Not multi-part, but the message is at least $MSG_SIZE, so compress it
    if ( @parts == 1 ) {
        print Dumper( $email );
        print STDERR "Only 1 part; running compress-message...\n";
        return compress_message($email);
    }

    # Skip the empty first parts, find the first real one, compress every other
    for ( $si=0; $si<@parts; $si++ ) {
        $body = $parts[$si]->body;

        # Skip non-text parts, we want a normal message to preview
        if ( $parts[$si]->content_type !~ /^text\// ) {
            push @original_parts, $parts[$si];
            
        # Also make sure the part is at least $MIN_FIRSTPART_SIZE
        } elsif ( length($body) < $MIN_FIRSTPART_SIZE ) {
            print STDERR "$0: Part $si's body is too small (".length($body)." < $MIN_FIRSTPART_SIZE)\n" if ($VERBOSE);
            push @original_parts, $parts[$si];
            next;
        }

        # end at the part we want to shorten
        last;
    }

    @compress_parts = @parts[$si..$#parts];

    # This part is big enough, so strip at most $MAX_FIRSTPART_SIZE from the
    # body and put that in a new part, and take this part and all the rest
    # and compress them in an additional part.
    my $short_part = clone($parts[$si]);

    print "parts[$si]: " . Dumper($parts[$si]) . "\n";
    print "short_part: " . Dumper($short_part) . "\n";

    $short_part->body_set( substr($body, 0, $MAX_FIRSTPART_SIZE) );

    compress_message($email, \@original_parts, $short_part, @compress_parts);

    print Dumper( $email );

}

sub compress_message {
    my ($email, $original, $short, $compress) = @_;

    my $compresspart = clone($short);
    print "short: " . Dumper($short) . "\ncompresspart: " . Dumper($compresspart) . "\n";
    $compresspart->encoding_set('base64');
    $compresspart->content_type_set('application/gzip');
    $compresspart->disposition_set('inline');
    $compresspart->filename_set('Email.eml.gz');

    my $out = '';
    my $gzip = new IO::Compress::Gzip(\$out, -Level => Z_BEST_COMPRESSION, "TextFlag" => 1) or die "Couldn't create gzip object: $! $GzipError\n";
    print $gzip $short->body;
    close($gzip);

    my $encoded = encode_base64( $out );
    $compresspart->body_set( $out );
    undef $out;
    undef $encoded;

    $email->parts_set( [ @$original, $short, $compresspart ] );
}

