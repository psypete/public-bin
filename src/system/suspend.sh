#!/bin/sh

# discover video card's ID
ID=`lspci | grep VGA | awk '{ print $1 }' | sed -e 's@0000:@@' -e 's@:@/@'`

# securely create a temporary file
TMP_FILE=`mktemp /var/tmp/video_state.XXXXXX`
trap 'rm -f $TMP_FILE' 0 1 15

OLDVT=`fgconsole`

# switch to virtual terminal 1 to avoid graphics
# corruption in X
chvt 1

# write all unwritten data (just in case)
sync

# dump current data from the video card to the
# temporary filecat 
cat /proc/bus/pci/$ID > $TMP_FILE

sync

sleep 1

# suspend
echo -n mem > /sys/power/state

sleep 1

# restore video card data from the temporary file
# on resume
cat $TMP_FILE > /proc/bus/pci/$ID

# switch back to virtual terminal 2 (running X)
chvt $OLDVT

# remove temporary file
rm -f $TMP_FILE
