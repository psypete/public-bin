#!/bin/sh
# twoman.sh v0.1 - two-man authentication file crypto
# Copyright (C) 2013 Peter Willis <peterwwillis@yahoo.com>
# 
# This script is designed to allow you to set up a two-man system
# for verifying a file was encrypted using two different random
# keys. You can use this to allow two different users to agree
# on the contents of a file and then perform some operation.
# 


###########################
# How To Set Up twoman.sh #
# 
#     1. create three users: admin1, admin2, and sentry
#     
#     2. Log into each user and run "twoman.sh" with no options.
#        The script will automatically generate a private key for
#        each user in their own $HOME/.twoman/ directory.
#     
#     3. From the sentry user, copy each admin's key to the 
#        ~sentry/.twoman/ directory.
#     
#     4. Create a symlink to each key in the sentry user's directory
#        as follows:
#     
#           ln -s ~sentry/.twoman/admin1.key ~sentry/.twoman/key1
#           ln -s ~sentry/.twoman/admin2.key ~sentry/.twoman/key2
# 

########################
# How To Verify A File #
# 
#     1. As sentry, run:
# 
#           twoman.sh genkey CHALLENGE-$RANDOM
# 
#     2. A new file named "CHALLENGE-4937.key" or similar will be
#        created. Copy the file over to one of the admin users.
# 
#     3. Have that admin user run:
# 
#           twoman.sh sign CHALLENGE-4937.key CHALLENGE-4937.key.admin1
# 
#     4. Copy the new file CHALLENGE-4937.key.admin1 to the other
#        admin user, and as the other admin user, run:
# 
#           twoman.sh sign CHALLENGE-4937.key.admin1 CHALLENGE-4937.key.admin2
# 
#     5. Copy the new file CHALLENGE-4937.key.admin2 to the sentry
#        user, and as the sentry user, run:
# 
#           twoman.sh verify CHALLENGE-4937.key CHALLENGE-4937.key.admin2
# 
#     6. Check the return status of the command, and you're done!
# 
# 

#########
# Notes #
# 
#  - Admin1 and admin2 should not have any access to the sentry user's
#    files or they could improperly influence the validation  of the
#    challenges.
# 
# 
################################################################################



DEBUG=0

# Where is my twoman directory?
TMCONFDIR="$HOME/.twoman"
if [ ! -d "$TMCONFDIR" -a -d "twoman.d" ] ; then
    TMCONFDIR="`pwd`/twoman.d"
elif [ ! -d "$TMCONFDIR" ] ; then
    mkdir -p "$TMCONFDIR"
fi

if [ ! -d "$TMCONFDIR" ] ; then
    echo "Error: could not find key directory" 1>&2 ; exit 1
fi

# Where are my keys?
[ -n "$PRIVKEY" ] || PRIVKEY="$TMCONFDIR/private.key"
[ -n "$PUBKEY" ] || PUBKEY="$TMCONFDIR/public.key"
[ -n "$KEY1" ] || KEY1="$TMCONFDIR/key1"
[ -n "$KEY2" ] || KEY2="$TMCONFDIR/key2"



function twoman_decrypt() {
    local challenge="$1" in="$2" key1="$3" key2="$4"
    [ $DEBUG -gt 0 ] && echo "INFO: Running twoman_decrypt('$challenge','$in')" 1>&2

    PUBKEY="$key1" decrypt_file "$in" ."$in.tmp1" 2>/dev/null &&
    PUBKEY="$key2" decrypt_file ."$in.tmp1" ."$in.tmp2" 2>/dev/null

    # If the first decrypt failed, no tmp1 file was created
    # If the second decrypt failed, only tmp1 exists
    if [ ! -r ."$in.tmp2" ] ; then
        /bin/rm -f ."$in.tmp1"
        return 1
    fi

    SHA_A=`sha256sum ."$in.tmp2" | awk '{print $1}'`
    SHA_B=`sha256sum "$challenge" | awk '{print $1}'`
    [ $DEBUG -gt 0 ] && echo -en "INFO: challenge SHA $SHA_A\nINFO: input SHA     $SHA_B\n" 1>&2

    /bin/rm -f ".$in.tmp1" ".$in.tmp2"
    if [ "$SHA_A" = "$SHA_B" ] ; then
        return 0
    fi
    return 1
}

function encrypt_file() {
    local in="$1" out="$2"
    [ $DEBUG -gt 0 ] && echo "INFO: Running encrypt_file('$in','$out')" 1>&2

    openssl enc -aes-256-cbc -a -salt -in "$in" -out "$out" -pass file:"$PUBKEY"
}

function decrypt_file() {
    local in="$1" out="$2"
    [ $DEBUG -gt 0 ] && echo "INFO: Running decrypt_file('$in','$out')" 1>&2

    #openssl rsautl -in "$in" -out "$out" -inkey "$PRIVKEY" -pkcs -decrypt
    openssl enc -d -aes-256-cbc -a -in "$in" -out "$out" -pass file:"$PUBKEY"
}

function gen_key() {
    local prefix="$1"
    [ $DEBUG -gt 0 ] && echo "INFO: Running gen_key($prefix)" 1>&2

    openssl rand -base64 4096 > "$prefix".key
}

function main() {
    local R=1

    # Do I have a key?
    if [ ! -e "$TMCONFDIR/$USER.key" ] ; then
        echo "Generating encryption key for $USER"
        gen_key "$TMCONFDIR/$USER"
        ln -s "$TMCONFDIR/$USER.key" "$PUBKEY"
    fi

    CMD="$1"; shift

    if [ "$CMD" = "sign" ] ; then
        encrypt_file "$1" "$2"
    elif [ "$CMD" = "decrypt" ] ; then
        decrypt_file "$1" "$2"
    elif [ "$CMD" = "genkey" ] ; then
        gen_key "$1"
    elif [ "$CMD" = "verify" ] ; then
        local challenge="$1" in="$2"
        twoman_decrypt "$challenge" "$in" "$KEY2" "$KEY1"
        R=$?
        if [ $R -eq 1 ] ; then
            twoman_decrypt "$challenge" "$in" "$KEY1" "$KEY2"
            R=$?
        fi

        if [ $R -eq 0 ] ; then
            echo "Success: file \"$in\" is correctly encrypted by both keys"
        else
            echo "Failure: file \"$in\" is not correctly encrypted by both keys"
        fi

        exit $R
    else
        cat <<EOUSE 1>&2
Usage: $0 COMMAND [OPTIONS]

Commands:

  sign CHALLENGE OUTFILE
    - Encrypts a CHALLENGE file using your personal key and writes to OUTFILE

  verify CHALLENGE INFILE
    - Decrypts an INFILE using key2 and key1, and verifies it against CHALLENGE

  genkey PREFIX
    - Generates a new random key named PREFIX.key

EOUSE
        exit 1
    fi
}

# Run the program
main $*
exit 0

