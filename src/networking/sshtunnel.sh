#!/bin/sh
set -x

SSH_OPTIONS="-a -o BatchMode=yes -o Cipher=blowfish -o ConnectionAttempts=1 -o ConnectTimeout=20 -i /root/.ssh/sshtunnel"

if [ "$1" = "-h" -o "$1" = "--help" -o $# -ne 1 ] ; then
  echo "Usage: $0 [USER@]REMOTEHOST[:PORT]"
  exit 1
fi

REMOTEHOST="$1"
HOST=`echo "$REMOTEHOST" | cut -d '@' -f 2- | cut -d ':' -f 1`
REMOTEPORT=`echo "$REMOTEHOST" | grep -o -e ":[[:digit:]]\+" | cut -d : -f 2`
[ -n "$REMOTEPORT" ] || REMOTEPORT=22

#while [ true ] ; do
    # -o BatchMode=yes,Cipher=blowfish,ConnectionAttempts=1,ConnectTimeout=10
    pppd nodetach noauth passive maxfail 1 pty "ssh $SSH_OPTIONS -t -p $REMOTEPORT $REMOTEHOST sudo /usr/sbin/pppd nodetach notty noauth noproxyarp" noproxyarp ipparam vpn 10.2.2.107:10.2.2.1 >pppd.log & pppid=$!

    sleep 10

    if [ ! -d "/proc/$pppid" ] ; then
        echo "Error: pppd died"
        exit 1
    fi

    PPPINTF=`grep 'Connect: ppp' pppd.log | awk '{print $2}'`

    DEFAULTROUTE=`route -n | grep UG | tail -n 1`
    DEFAULTIP=`echo "$DEFAULTROUTE" | awk '{print $2}'`
    DEFAULTINTF=`echo "$DEFAULTROUTE" | awk '{print $8}'`
    PTPIP=`ifconfig | grep -A 1 "^$PPPINTF" | grep P-t-P: | sed -e 's/^.*P-t-P:\(.*\)[[:space:]].*$/\1/g'`

    if [ -z "$PPPINTF" -o -z "$DEFAULTROUTE" -o -z "$DEFAULTIP" -o -z "$DEFAULTINTF" -o -z "$PTPIP" ] ; then
        echo "Error: could not find all necessary routing information"
        exit 1
    fi

    route add -host "$PTPIP" dev "$PPPINTF"
    route add -host "$HOST" gw "$DEFAULTIP" dev "$DEFAULTINTF"
    route add default gw "$PTPIP"

    wait
#    sleep 5
#done

