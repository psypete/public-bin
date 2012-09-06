#!/bin/sh
if [ $# -lt 2 ] ; then
	echo "Usage: $0 INPUT OUTPUT"
	echo " Converts INPUT into a .flv as OUTPUT"
	exit 1
fi
mencoder $1 -o $2 -oac mp3lame -ovc lavc -lavcopts vcodec=flv:vbitrate=400 -vop scale=320:240 -of lavf -lavfopts format=flv -ofps 30
