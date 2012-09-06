#!/bin/sh
# xosd_acpi_stats.sh - report acpi information via xosd
# Copyright (C) 2009 Peter Willis <peterwwillis@yahoo.com>

SLEEP_FOR=60
OFFSET=40
COLOR="green"
ALIGN="right"
POSITION="bottom"

function battery_state() {
    for batt in /proc/acpi/battery/* ; do
        FULL=$(grep "^last full capacity:" $batt/info | awk '{print $4}')
        REMAINING=$(grep "^remaining capacity:" $batt/state | awk '{print $3}')
        PERCENT=$(echo "$REMAINING/$FULL" | bc -l | sed -e 's/^[[:digit:]]\.\|\.//g' | cut -c 1-2)
        STATE=$(grep "^charging state:" $batt/info | awk '{print $3}')
        echo "Battery: $PERCENT% $STATE"
    done
}

function loop_and_report() {
    while [ true ] ; do
        OUTPUT=''

        OUTPUT="$OUTPUT$(battery_state)"
        LINES=$(echo "$OUTPUT" | wc -l)

        echo "$OUTPUT" | osd_cat -p $POSITION -A $ALIGN -c $COLOR -l $LINES -o $OFFSET -d $SLEEP_FOR
        RET=$?


        if [ $RET -ne 0 ] ; then
            echo "Error: osd_cat return status was $RET"
            sleep 10
        fi
        
    done
}

loop_and_report

