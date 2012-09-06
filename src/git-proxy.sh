#!/bin/sh
BINDIR="$HOME/bin"
SRCDIR="$BINDIR/src"
PROXY="localhost:8081"

# if connect doesn't exist, try to compile it
if [ ! -e "$BINDIR/connect" ] ; then
    if [ -e "$SRCDIR/connect.c" ] ; then
        gcc -o "$BINDIR/connect" "$SRCDIR/connect.c"
        if [ $? -eq 0 ] ; then
            echo "Compile of connect.c succeeded."
            chmod 755 "$BINDIR/connect"
        else
            echo "Error: Compile of connect.c failed."
            exit 1
        fi
    else
        echo "Error: connect.c not found."
        exit 1
    fi
fi

$BINDIR/connect -S $PROXY "$@"
