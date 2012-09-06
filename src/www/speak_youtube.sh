#!/bin/sh
# text2speech using youtube - copyright (c) 2009 peter willis
# i'm too lazy to interpret 't=' so i'm using an old one.
# youtube cuts off text after about twenty-two words so split
# it up into multiple requests.

T="vjVQa1PpcFP9d844NLJLKSne06g1Etm2zMDdSSYhNSQ%3D"

# URL-encode words with awk
function url_encode_words() {
    echo "$@" | awk '
    BEGIN {
        EOL = "%0A"     # "end of line" string (encoded)
        split ("1 2 3 4 5 6 7 8 9 A B C D E F", hextab, " ")
        hextab [0] = 0
        for ( i=1; i<=255; ++i ) ord [ sprintf ("%c", i) "" ] = i + 0
    }
    {
        encoded = ""
        for ( i=1; i<=length ($0); ++i ) {
            c = substr ($0, i, 1)
            if ( c ~ /[a-zA-Z0-9.-]/ ) {
                encoded = encoded c     # safe character
            } else if ( c == " " ) {
                encoded = encoded "+"   # special handling
            } else {
                # unsafe character, encode it as a two-digit hex-number
                lo = ord [c] % 16
                hi = int (ord [c] / 16);
                encoded = encoded "%" hextab [hi] hextab [lo]
            }
        }
        print encoded
    }'
}

function download_words() {
    FILE="$1"
    shift
    TMP=`echo "$@" | sed -e 's/ /+/g'`
    echo "speaking \"$TMP\""
    echo -en "GET /preview_comment?q=$TMP&a=&s=&l=&t=$T HTTP/1.1\nHost: www.youtube.com\n\n" | nc -v www.youtube.com 80 > $FILE
}

function play_all() {

    BUFFER=`url_encode_words "$@" | sed -e 's/%20/ /g;s/+/ /g'`
    FILES=""
    COUNTER=0
    while [ -n "$BUFFER" ] ; do
        CUT=`echo "$BUFFER" | cut -d " " -f 1-21`
        FILE="/tmp/speak.$$.$COUNTER.mp3"
        download_words "$FILE" "$CUT"
        FILES="$FILES $FILE"
        BUFFER=`echo "$BUFFER" | sed -e "s/$CUT//"`
        COUNTER=$(($COUNTER+1))
    done
    play $FILES
    [ $? -eq 0 ] && /bin/rm $FILES

}

if [ $# -lt 1 ] ; then
    echo "Usage: $0 WORDS [..]"
    exit 1
fi

play_all "$@"

