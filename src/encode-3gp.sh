#!/bin/sh
#set -x

function mencoder_it() {
        INPUT="$1"
        OUTPUT="$2"
        shift
        shift
        rm -f "$OUTPUT"
        mencoder -quiet "$INPUT" \
            -oac pcm \
            -ovc lavc \
            -lavcopts vcodec=mjpeg \
            -sws 2 \
            -vf scale=$RESCALE \
            -af volume=10 \
            -o "$OUTPUT" \
            $*
}


# -ar = 8000
# -ac = 1
# -r = 12
# -b = 60
# -ab = 12

function ffmpeg_it() {
        INPUT="$1"
        OUTPUT="$2"
        shift
        shift
        rm -f "$OUTPUT"
        ffmpeg \
            -i "$INPUT" \
            -ar 8000 \
            -ac 1 \
            -acodec amr_nb \
            -vcodec h263 \
            -s $RESCALE \
            -r 15 \
            -b $BITRATE \
            -ab 12 \
            "$OUTPUT" \
                $*
}

function get_id() {
	mplayer -quiet -ao null -vo null -frames 0 -identify "$1" 2>/dev/null | grep -e "^ID_"
}


if [ $# -lt 2 ] ; then
  echo "Usage: INFILE OUTFILE"
  echo "(OUTFILE must end in .3gp)"
  exit 1
fi

FILE=$1
NEWFILE=$2
TMPFILE=`dirname "$2"`/.$RANDOM-$$-$USER.media

[ -n "$RESCALE" ] || RESCALE=176:144
[ -n "$BITRATE" ] || BITRATE=90

shift
shift

mencoder_it "$FILE" "$TMPFILE"
ffmpeg_it "$TMPFILE" "$NEWFILE"
rm -f "$TMPFILE"
