#!/bin/sh

CONFIGOPTS="--prefix=$HOME/usr"

if [ $# -lt 1 ] ; then
	echo "Usage: $0 TARBALL"
	echo "Decompresses, configures, compiles and installs a TARBALL"
	exit 1
fi

function findext() {
	TAR="$1"
	echo "$TAR" | grep -i -e "\.tar\.gz$" >/dev/null && echo ".tar.gz" && return 0
	echo "$TAR" | grep -i -e "\.tar.bz2$" >/dev/null && echo ".tar.bz2" && return 0
	echo "$TAR" | grep -i -e "\.tgz$" >/dev/null && echo ".tgz" && return 0
	echo "$TAR" | grep -i -e "\.tbz2$" >/dev/null && echo ".tbz2" && return 0
	return 1
}

# Set tarball, config options

tarball=$1
shift
if [ $# -gt 0 ] ; then
	CONFIGOPTS="$@"
fi

# Get tarball specifics

echo "$tarball" | grep gz$ >/dev/null && export TAROPT="-z"
echo "$tarball" | grep bz2$ >/dev/null && export TAROPT="-j"
EXT=`findext "$tarball"`
DNAME=`basename "$tarball" $EXT 2>/dev/null`
if [ -n "$EXT" -a -n "$DNAME" -a ! "$DNAME" = "$tarball" -a ! "$EXT" = "$tarball" ] ; then
	continue
else
	echo "Error: no valid extention found ($EXT / $DNAME / $tarball)"
	exit 1
fi

# Untar and cd

rm -rf "$DNAME"
tar $TAROPT -xf "$tarball"
cd "$DNAME"


# Configure, make, make install

./configure $CONFIGOPTS
if [ ! "$CONFIGOPTS" = "--help" -a $? -eq 0 ] ; then
	make && make install

	if [ $? -eq 0 ] ; then
		echo "TARINST: SUCCESS"
	else
		echo "TARINST: FAIL"
	fi
fi

