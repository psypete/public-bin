#!/bin/sh

if [ "$1" = "-h" -o "$1" = "--help" -o $# -lt 1 -a -t 0 ] ; then
    echo "Usage: cat CSV_FILE | $0"
    echo "Usage: $0 CSV_FILE"
    echo ""
    echo "WARNING: THIS PRINTS DUPLICATE LINES"
    echo ""
    echo "Skips any lines with a 'Rack' column including the word 'Virtual',"
    echo "and any 'OS' column including the substring 'V-'."
    echo ""
    echo "Example:"
    echo "  (head -1 active_server_list.csv; cat groups/hosts_in_*_group.list) | $0"
    echo "  $0 active_server_list.csv"
    exit 1
fi

CAT="$1"

cat $CAT | csvgrep.pl -n Rack -v "Virtual" | csvgrep.pl -n OS -v "V-"
