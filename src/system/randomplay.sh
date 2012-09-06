#!/bin/sh
if [ $# -lt 1 ] ; then
    echo "Usage: $0 [OPTIONS] PATH"
    echo "Options:"
    echo "  -audio          Only output audio"
    exit 1
fi
#for i in `seq 1 $#` ; do
#    if echo "$1" | grep -e "^-" ; then
#        OPTS="$OPTS $1"
#        shift
#    fi
#done

if [ "$1" = "-audio" ] ; then

    OPTS="-softvol-max 100"
    shift
    ( for path in "$@" ; do if ! echo "$path" | grep -q -e "^/" ; then path="`pwd`/$path" ; fi ; find "$path" -type f -follow ; done ) | sort -R > /tmp/playlist-$$.pls
    mplayer -quiet $OPTS -vo null -playlist /tmp/playlist-$$.pls
    /bin/rm -f /tmp/playlist-$$.pls

else

    ( for path in "$@" ; do if ! echo "$path" | grep -q -e "^/" ; then path="`pwd`/$path" ; fi ; find "$path" -type f -follow -exec file -F "*" {} \; ; done ) | grep -i -e "\(audio\|video\|MPEG [^s]\|AVI\|Matroska\|ISO Media\)" | cut -d "*" -f 1 | sort -R > /tmp/playlist-$$.pls
    mplayer -quiet $OPTS -playlist /tmp/playlist-$$.pls
    /bin/rm -f /tmp/playlist-$$.pls

fi

