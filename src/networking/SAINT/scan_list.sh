#!/bin/sh

SAINTDIR="/usr/local/saintnode"
LISTDIR="/home/pwillis/scan.d"

if [ $# -lt 1 ] ; then
    echo "Usage: $0 GROUP"
    exit 1
fi

GROUP="$1"; shift
OPWD=`pwd`

cd $SAINTDIR

for list in "$LISTDIR"/"$GROUP"_list.* ; do
    #HOSTS=`cat $list | xargs | sed -e 's/ /,/g'`
    HOSTS=`cat $list | xargs`
    cd $SAINTDIR
    set -x
    ./saint -q -d "$GROUP"_group -ffff -X -T -bb -C "$GROUP"_group-hvs -c "send_results=1; use_credentials_file=0;" -m 20 $HOSTS
    set +x
done

cd $OPWD

