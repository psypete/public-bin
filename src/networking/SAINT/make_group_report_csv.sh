#!/bin/sh

#for group in lan unix network unknown ; do

    echo "Sys_Admin,IPAddresses,Email" > "reports/report-sysadmins.csv"

    for admin in sysadmins/* ; do
        NAME=`basename "$admin" .csv | sed -e's/_/ /g'`

        IPADDRS="`csvcut.pl -f "$admin" -n IPAddresses | tail -n +2 | sort | uniq | xargs | sed -e 's/\r//g;s/\n//g;s/ /;/g;s/,/;/g'`;"
        EMAIL=`grep "$NAME" groups/names.map | sed -e 's/^.*mail: \([^[:space:]]\+\).*$/\1/g'`

        if [ -z "$NAME" -o -z "$IPADDRS" -o -z "$EMAIL" -o "x`grep "$NAME" groups/names.map`" = "x" ] ; then
            echo "Not found: $NAME"
            continue
        fi

        echo "$NAME,$IPADDRS,$EMAIL" >> "reports/report-sysadmins.csv"
    done

#done

