#!/bin/sh
# extract_audio.sh - extract audio stream from a video file
# Copyright (C) 2009 Peter Willis <peterwwillis@yahoo.com>
#

if [ $# -lt 1 ] ; then
    echo "Usage: $0 VIDEO [..]"
    exit 1
fi

for vid in "$@" ; do
    DIR=`dirname "$vid"`
    BN=`basename "$vid" | sed -e's/\.[a-zA-Z0-9]\+$//'`

    mplayer -quiet -dumpaudio -dumpfile "$DIR/$BN.audio" "$vid"
done

