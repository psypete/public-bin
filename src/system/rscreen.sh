#!/bin/sh
# rscreen.sh - resume a detached screen process
# Copyright (C) 2004-2005  Peter Willis <psyphreak@phreaker.net>

function showpids {
	SCREENPIDS="`ps ax | grep SCREEN | grep -v grep`"
	[ -n "$SCREENPIDS" ] || return 1
	echo -n " 0 QUIT 1 \"NEW SHELL\""
	echo "$SCREENPIDS" | while read SCREENPID ; do
	        PID=`echo "$SCREENPID" | awk '{print $1}'`
	        PIDNAME=`echo "$SCREENPID" | sed -e 's:.*SCREEN ::g'`
	        echo -n " $PID \"$PIDNAME\""
	done
}

function doscreenthingie {
	[ -n "$TMPDIR" ] || TMPDIR="/tmp"
	TMPFILE="$TMPDIR/dialog.$$"
	[ -e "$TMPFILE" ] && exit 1
	touch "$TMPFILE" 2>/dev/null 1>/dev/null
	if [ $? -ne 0 ] ; then
	        echo "ERROR: COULD NOT TOUCH \"$TMPFILE\"; EXITING"
	        exit 1
	fi
	screen -wipe 2>/dev/null 1>/dev/null
	DIALOGARGS="`showpids`"
	if [ ! -n "$DIALOGARGS" ] ; then
	        echo "ERROR: NO SCREEN PROCESSES APPEAR TO BE RUNNING"
	        exit 1
	fi
	echo "dialog --stderr --menu \"Please select a screen process to resume.\" 0 0 0$DIALOGARGS 2>\"$TMPFILE\"" > "$TMPFILE"
	/bin/sh "$TMPFILE"
	SCREENPID=`cat "$TMPFILE"`
	rm -f "$TMPFILE"
	if [ -n "$SCREENPID" ] ; then
	        if [ x"$SCREENPID" = "x0" ] ; then
	                exit 0
	        elif [ x"$SCREENPID" = "x1" ] ; then
	                screen -d -m bash
	        fi
	        screen -dr $SCREENPID
	fi
}

if [ -n "$STY" ] ; then
        echo "Error: Looks like you're already in a screen process."
        echo "Running rscreen.sh from a running screen is a Bad Thing(TM)."
        exit 1
fi

while [ true ] ; do
        doscreenthingie
done

