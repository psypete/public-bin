#!/bin/sh
# print punk blog post
# Copyright (C) 2009 Peter Willis <peterwwillis@yahoo.com>

echo "What's the image URL? (not shortened)"
read IMGURL
curl -o tmp.img "$IMGURL"
# The image get was successful
if [ $? -eq 0 ] ; then
    /bin/sh -c "xv tmp.img && rm -f tmp.img" &
    echo "Day of month?"
    read DAYOFMONTH
    echo "Venue?"
    read VENUE
    echo "Band list?"
    read BANDLIST
    echo "Time, Cost, Ages ?"
    read TIMECOSTAGES
    if [ -n "$IMGURL" -a -n "$DAYOFMONTH" -a -n "$VENUE" -a -n "$BANDLIST" -a -n "$TIMECOSTAGES" ] ; then
        SHORTURL=`make-is_gd.sh $IMGURL`
        echo -en "$DAYOFMONTH\n<b>$VENUE</b> - <i>$BANDLIST</i>\n$TIMECOSTAGES\n<a href=\"$SHORTURL\"><img style=\"width: 200px; height: 300px;\" src=\"$SHORTURL\" border=\"0\"></a>\n"
    else
        echo "Error: one of the fields was empty"
        exit 1
    fi
else
    echo "Error: could not get image"
    exit 1
fi
