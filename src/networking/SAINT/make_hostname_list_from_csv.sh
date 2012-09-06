#!/bin/sh

if [ $# -ne 2 ] ; then
    echo "Usage: $0 CSV FIELD"
    echo ""
    echo "Generates a list of hostnames, based on a FIELD made up of IP addresses from a CSV file."
    exit 1
fi

CSV="$1"
shift
FIELD="$1"
shift


ARG="-n"
echo "$FIELD" | grep -q -e "^[0-9]\+$" && ARG="-c"

csvgrep.pl -f "$CSV" $ARG $FIELD "\d+" | csvcut.pl -r $ARG $FIELD | sort | uniq | while read IP ; do

    REVIP=`dig +short -x "$IP" | sed -e 's/\.$//g'`

    if [ -n "$REVIP" ] ; then
        echo "$REVIP"
        continue
    else
    

        SERVERNAME=`csvgrep.pl -f $CSV $ARG $FIELD "$IP" | csvcut.pl -c 1 -r`
        if [ -z "$SERVERNAME" ] ; then
            echo "$IP"
            continue
        fi

        REVIP=`host $SERVERNAME | grep 'has address' | head -1 | awk '{print $1}'`
        if [ -n "$REVIP" ] ; then
            echo "$REVIP"
            continue
        else
            echo "$IP"
            continue
        fi

    fi

done

