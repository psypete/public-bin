#!/usr/bin/perl
# rename-mp3.pl - rename mp3s
# defaults to creating a directory structure of "/path-to-file/Artist/Album/Title.mp3"

$|=1;
use MP3::Tag;
use strict;

my $DEBUG = exists $ENV{DEBUG} ? $ENV{DEBUG} : 0;

if ( !@ARGV ) {
	die "Usage: $0 MP3 ..\n  Pass some mp3s on the command line and they will be renamed in an\n  ./Artist/Album/Title format.\n  Set DEBUG=1 in your environment for a dry-run with details.\n";
}

foreach my $mp3 (@ARGV) {
	if ( ! -f $mp3 ) {
		die "Error: only specify mp3 files on the command line.\n";
	}
	rename_mp3($mp3);
}

sub rename_mp3 {
	my $file = shift;
	my ($ext,$dir,$fname);
	my $mp3 = MP3::Tag->new($file);
	my ($title, $track, $artist, $album, $comment, $year, $genre) = $mp3->autoinfo();
	my @dirlist;

        if ( $file =~ /^(.+)\/([^\/]+)$/ ) {
                $dir = $1;
                $fname = $2;
        } else {
                $dir = ".";
                $fname = $file;
        }

        if ( $fname =~ /^(.+)\.([^\.]+)$/ ) {
                $ext = $2;
        } else {
                $ext = "mp3";
        }

	if ( !defined $artist or length($artist) < 1 ) {
		
		$artist = "Unknown";
	} else {
		$artist = join( " ", map { $_ = ucfirst($_) } split(/\s+/, $artist) );
		$artist =~ s/\//-/g;
	}

	if ( !defined $album or length($album) < 1 ) {
		$album = "Unknown";
	} else {
		$album = join( " ", map { $_ = ucfirst($_) } split(/\s+/, $album) );
		$album =~ s/\//-/g;
	}

	if ( !defined $title or length($title) < 1 ) {
		$title = $fname;
		$title =~ s/^\.$ext$//;
		$title = join( " ", map { $_ = ucfirst($_) } split(/\s+/, $title) );
		$title =~ s/\//-/g;
	}

	print STDERR "File: $fname\nArtist: $artist\nAlbum: $album\nTitle: $title\n" if ($DEBUG);
	#print "Renaming: $fname -> $artist/$album/$title.$ext\n";

	print STDERR "mkdir(\"$dir/$artist\")\n" if ($DEBUG);
	mkdir("$dir/$artist") unless ($DEBUG);
	print STDERR "mkdir(\"$dir/$artist/$album\")\n" if ($DEBUG);
	mkdir("$dir/$artist/$album") unless ($DEBUG);

	print STDERR "rename($file, \"$dir/$artist/$album/$title.$ext\")\n" if ($DEBUG);
	if ( ! $DEBUG ) {
		if ( -e "$dir/$artist/$album/$title.$ext" ) {
			print STDERR "Error: target file \"$dir/$artist/$album/$title.$ext\" exists\n";
			return(0);
		}
		if ( ! rename($file, "$dir/$artist/$album/$title.$ext") ) {
			print STDERR "Error: Could not rename \"$file\" -> \"$dir/$artist/$album/$title.$ext\": $!\n";
			return(0);
		}
	}

	print "\n" if ($DEBUG);
}


