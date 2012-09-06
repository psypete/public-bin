#!/bin/sh
#set -x

function return_deps() {
	local RPM="$1"
	local MATCHES=`rpm -q --requires "$RPM" | grep "$PKGNAME" | awk '{print $1}'`
        if [ -n "$MATCHES" ] ; then
                echo "  Package \"$RPM\":"
                echo "$MATCHES" |
                while read LINE ; do
                        echo "      $LINE"
                done
	fi
}

if [ $# -lt 2 ] ; then
	cat <<EOF
Usage: $0 CMD PACKAGE
  CMD options:
	-d	Find all rpms that depend on PACKAGE
EOF
	exit 1
fi

CMD="$1"
PKGNAME="$2"

if [ "$CMD" = "-d" ] ; then
	echo "Finding dependencies for \"$PKGNAME\":"
	rpm -qa | while read LINE ; do
		return_deps "$LINE"
	done
fi

