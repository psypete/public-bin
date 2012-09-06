#!/bin/sh
# get_server_ssl_cert.sh
# Copyright (C) 2009 Peter Willis <peterwwillis@yahoo.com>
# 
# This connect to a host:port and retrieves the server certificate
# and prints its text output as well.

if [ $# -lt 1 ] ; then
    echo "Usage: $0 HOST:PORT [..]"
    exit 1
fi

for hostport in "$@" ; do
    cat /dev/null | openssl s_client -connect "$hostport" 2>/dev/null | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' | openssl x509 -text
done
