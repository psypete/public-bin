#!/bin/sh
for arg in "$@" ; do
    curl -d "URL=$arg" http://is.gd/create.php 2>/dev/null | perl -lne'/short_url" value="([^"]+)"/&&print $1'
    sleep 1
done
