#!/usr/bin/perl
# tag-audio-files.pl - tag audio files based on their directory structure

$|=1;
use strict;
use AudioFile::Info;

if ( ! @ARGV ) {
	die "Usage: $0 DIRECTORYROOT ...\n  Pass it a directory root and it will attempt to tag the underlying files\n  according to their directory structure. The directories must be\n  assembled such as:\n    ARTIST/ALBUM/TITLE.EXT\n    ARTIST/TITLE.EXT\n\n  For your safety the program will exit if it finds 3-or-more-deep files.\n";
}

foreach my $dir (@ARGV) {
	if ( ! -d $dir ) {
		die "Error: please specify a directory root.\n";
	}
	tag_files($dir);
}

sub tag_files {
	my $dir = shift;
	my @DIRS;
	my @_DIRS;
	my @_FILES;
	
	while ( @DIRS ) {
		@_DIRS = @DIRS;
		@DIRS = ( );

		foreach my $dir ( @_DIRS ) {
			my $fh;
			opendir($fh, $dir);
			my @FILES = grep(!/^\.\.?$/,readdir($fh));
			closedir($fh);

			foreach my $file (@FILES) {
				if ( -d $file ) {
					push @DIRS, "$dir/$file";
				} elsif ( -f $file ) {
					push @_FILES, "$dir/$file";
				}
			}
		}
	}

	foreach my $file (@_FILES) {
		tag_file($file);
	}

}

sub tag_file {
	my $file = shift;
	my $audio = AudioFile::Info->new($file);


