#!/usr/bin/perl
# getytmp3.pl - get mp3's (and optionally videos) from YouTube
# Copyright (C) 2009 Peter Willis <peterwwillis@yahoo.com>
#
# This script downloads MP3's (and optionally videos) from YouTube videos.
# It also traverses playlists and may eventually work with RSS feeds.
# 
#             DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
#                     Version 2, December 2004
# 
#  Copyright (C) 2004 Sam Hocevar
#   14 rue de Plaisance, 75014 Paris, France
#  Everyone is permitted to copy and distribute verbatim or modified
#  copies of this license document, and changing it is allowed as long
#  as the name is changed.
# 
#             DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
#    TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION
# 
#   0. You just DO WHAT THE FUCK YOU WANT TO.
#

# how to get video data
# example: http://gdata.youtube.com/feeds/api/videos/tJQGM3MfqmI
# example: http://gdata.youtube.com/feeds/api/playlists/A74D4706D24A4475?v=2

# http://www.youtube.com/watch?v=t7qZYRHfFQs&feature=PlayList&p=960051D00C4D6D18&playnext_from=PL&index=0&playnext=1

$|=1;
use strict;
use File::Temp;
use MP3::Tag;
use XML::Simple;
use LWP::UserAgent;
use LWP::ConnCache;

my $WGET = "wget";
my $UA;

main();

sub main {
    $UA = LWP::UserAgent->new( env_proxy => 1);
    $UA->env_proxy();
    $UA->conn_cache( LWP::ConnCache->new() );

    for (@ARGV) {
        if ( /^http:\/\/.+?p=([\w-]+)/ ) {
            download_playlist($1);
        } else {
            download_video($_, "$_.yt");
            sleep(1);
        }
    }
}


sub download_playlist {
    my $plid = shift;
    my ($content);
    
    print STDERR "Attempting to download playlist $plid\n";

    print STDERR "Grabbing XML data...\n";
    $content = $UA->get("http://gdata.youtube.com/feeds/api/playlists/$plid")->content;
    if ( defined $content and length $content ) {
        my $xml = XMLin($content);

        if ( exists $xml->{entry} ) {
            my @items = keys %{ $xml->{"entry"} };
            foreach my $item (@items) {
                my $url = $xml->{"entry"}->{$item}->{"media:group"}->{"media:player"}->{"url"};
                if ( $url =~ /^http:\/\// ) {
                    print STDERR "Downloading video $url\n";
                    download_video($url);
                    sleep(1);
                }
            }
        }
    }
}

sub download_video {
    my ($url, $outfile) = @_;
    my ($id, $content, $t, $title, $outfile);

    if ( $url =~ /^http:\/\/.+?v=([\w-]+)/ ) {
        $id = $1;
    } else {
        print STDERR "Error: URL \"$url\" not valid for download\n";
        return;
    }

    if ( !defined $outfile ) {
        $outfile = "$id.yt";
    }

    print STDERR "Attempting to download id $id\n";

    # First try the XML way
    print STDERR "Grabbing XML data...\n";
    $content = $UA->get("http://gdata.youtube.com/feeds/api/videos/$id")->content;
    if ( defined $content and length $content ) {
        my $xml = XMLin($content);

        if ( exists $xml->{title} and exists $xml->{title}->{content} ) {
            $title = $xml->{title}->{content};
        }

    }

    print STDERR "Grabbing HTML data...\n";
    $content = $UA->get("http://www.youtube.com/watch?v=$id")->content;

    if ( $content =~ /watch_fullscreen\?\S+&t=([\w%]+)/ ) {
        $t = $1;
    } elsif ( $content =~ /&t=([\w%]+)/ ) {
        $t = $1;
    } else {
        print STDERR "Error: no 't' in source.\n";
    }

    if ( defined $t ) {
        print STDERR "Downloading id $id (t $t) -> $outfile\n";
        download($id, $t, $outfile);
    }
}

sub download {
    my $id = shift;
    my $t = shift;
    my $outfile = shift;
    my $ret;

    # try in HD first (720p)
    $ret = download_attempt($outfile, "http://www.youtube.com/get_video?hl=en&video_id=$id&t=$t&fmt=22");
    if ( ! $ret ) {
        # try in HD first (480p)
        $ret = download_attempt($outfile, "http://www.youtube.com/get_video?hl=en&video_id=$id&t=$t&fmt=35");
        # if that fails, try HQ
        if ( ! $ret ) {
            download_attempt($outfile, "http://www.youtube.com/get_video?hl=en&video_id=$id&t=$t&fmt=18");
            # if that fails, try normal
            if ( ! $ret ) {
                $ret = download_attempt($outfile, "http://www.youtube.com/get_video?hl=en&video_id=$id&t=$t");
            }
        }
    }

    if ( $ret ) {
        if ( process_video($id, $outfile) ) {
            #unlink($outfile);
            1;
        }
    }
}

sub process_video {
    my $id = shift;
    my $file = shift;
    my $tmp = File::Temp->new( DIR => ".", UNLINK => 0 );
    my $tmpfn = $tmp->filename;
    my $type = `file "$file"`;
    my $path;
    my $r = 1;

    chomp $type;
    # MPEG v4 w/AAC audio. FAAD is pretty much the only way to convert this to wav
    # aside from re-encoding the whole thing with mencoder -nobps -ni -forceidx -mc 0
    if ( $type =~ /MPEG v4/ ) {
        if ( $path = `which mplayer 2>/dev/null` and chomp $path and length $path > 0 ) {
            system("$path -really-quiet -ao pcm:fast:file=\"$tmpfn\" -vo null -vc null -hardframedrop -nocorrect-pts \"$file\" 2>/dev/null");
            $r = ($? >> 8);
        } elsif ( $path = `which faad 2>/dev/null` and chomp $path and length $path > 0 ) {
            system("$path -q -o \"$tmpfn\" \"$file\" 2>/dev/null");
            $r = ($? >> 8);
        }
    }

    if ( $r != 0 ) {
        print STDERR "Error processing video: mplayer returned nonzero\n";
        return(0);
    }

    my $newfn = $file;
    $newfn =~ s/\.[^.]+$/.wav/;

    if ( !rename($tmpfn, $newfn) ) {
        print STDERR "Error: could not rename $tmpfn to $newfn: $!\n";
        return(0);
    }

    return(1);
}


# TODO: re-do this with curl so we can do ranges of 1MB at a time to speed up downloads
sub download_attempt {
    my ($file, $url) = @_;

    # Might need to check at what version wget supported this behavior
    my $r = system($WGET, "-t", "1", "-O", $file, "-c", $url);
    my $ret = ( $? >> 8 );
    if ( $ret == 130 or $r == 2 ) {
        print STDERR "INFO: It looks like wget was killed by the user.\n";
        print STDERR "Do you want to continue? ";
        my $input = <STDIN>;
        chomp $input;
        if ( $input !~ /^y(es)?$/i ) {
            print STDERR "You got it; exiting...\n";
            exit(1);
        }
    } elsif ( $ret == 0 and $r == 0 ) {
        return(1);
    }
    return(0);
}

sub download_attempt_curl {
    my ($file, $url) = @_;
    my $i = 0;
    my $length = `curl -I "$url" | grep Content-Length | awk '{print \$2}'`;
    my $readlen = 1000000;
    my $skipchunk = 1500;

    chomp $length;

    for ( ;; ) {
        my $cursiz = -s $file;
        my $start = $cursiz - $skipchunk + 1;
        my $end = $start += $readlen;
        truncate($file, $cursiz - $skipchunk);
        system("curl", "-r", "$start-$end", $url);
        if ( ($? >> 8) != 0 ) {
            print STDERR "Non-zero status from curl; exiting\n";
            return();
        }
    }
}

