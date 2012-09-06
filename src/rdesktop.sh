#!/bin/bash

SERVER=ops-wints-2.dev.sportsline.com

if [ -n "$1" ] ; then
	SERVER="$1"
fi

echo "Connecting to $SERVER ..."

rdesktop $SERVER -g 1024x768 -a  16 -u pwillis -d cbs -x m -P -z -a 8 -C -B -g 1024x768
