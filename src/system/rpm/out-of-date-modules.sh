#!/bin/sh

yum list | grep "^perl-" | grep -v installed | while read LINE ; do
  PKG=`echo "$LINE" | awk '{print $1}' | cut -d . -f 1`
  VER=`echo "$LINE" | awk '{print $2}'`
  CURVER=`rpm -q $PKG | sed -e "s/$PKG-//g"`
  if echo "$CURVER" | grep -q "is not installed" ; then
    echo "Missing pkg $PKG ($VER)"
  else
    echo "Have old pkg $PKG $CURVER (newest is $VER)"
  fi
done

