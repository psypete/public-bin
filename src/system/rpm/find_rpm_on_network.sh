#!/bin/sh
if [ $# -lt 1 ] ; then
	echo "Usage: $0 FILENAMEGLOB"
	echo "Searches build boxes for a user's built RPM matching FILENAMEGLOB."
	exit 1
fi

FNAMEGLOB="$1"

for box in buildfc3 buildel4 buildel64 ; do
	echo "Searching $box in /spln/local/ ..." > /dev/stderr
	ssh $box "for dir in /spln/local/* ; do \
		find \$dir -type f -iname '\$FNAMEGLOB' \
	; done"
done

for dir in /net/johnliao /net/mlewandowski /net/share/oldaccounts/* /net/pwillis /net/dennism ; do
	#echo "Searching $dir ..." > /dev/stderr
	for subdir in fc3 centos44 build_trees/fc3 build_trees/centos44 ; do
		if [ -d "$dir/$subdir/RPMS" ] ; then
			echo "Searching $dir/$subdir/RPMS ..."
			find $dir/$subdir/RPMS -type f -iname "$FNAMEGLOB"
		fi
	done
done

