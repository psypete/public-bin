#!/bin/sh

if [ $# -lt 2 ] ; then
    echo "Usage: $0 CSV GROUP_LIST"
    exit 1
fi

CSV="$1"
shift
GROUP_LIST="$1"
shift

for group in network lan unix telecom unknown ; do
    echo "Making $group list from $GROUP_LIST"
    grep "Group ${group}" $GROUP_LIST | awk '{print $2}' | xargs -I "{}" -n 1 grep -e "^{}," "$CSV" > hosts_in_${group}_group.list
    echo "Sorting IPs"
    ( head -1 "$CSV" ; cat "hosts_in_${group}_group.list" ) | csvcut.pl -n "IPAddresses" -r | perl -ne'@_=map{($_>-1&&$_<256)?$_:()}split/\./,$_;print join".",@_ if@_==4' | sort | uniq > ips_in_${group}_group.list
done

