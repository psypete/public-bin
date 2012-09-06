# .bash_profile
# NEVER EVER DO THIS AGAIN!!!! :)
#set -o vi

[ -n "$PROFILE_BEEN_HERE" ] && return
PROFILE_BEEN_HERE=1

[ "$USER" != "root" ] && alias loadenv='loadenv -D'
export HISTCONTROL=ignoreboth      # man bash for this oen.

export PATH=$PATH:/net/sysadm/bin:/net/sysadm/sbin:/usr/X11R6/bin:/usr/sbin:/usr/local/pkg/bin:/usr/local/pkg/sbin:$HOME/bin:$HOME/usr/bin
export MANPATH=/usr/man:/usr/local/man:/usr/X11R6/man:/usr/lib/courier-imap/man::/usr/kerberos/man

export CVSROOT=/net/cvsroot
#export CVSROOT=:pserver:dooher@cvs.sportsline.com:/repository/normandy

export KICKSTART_ROOT=$HOME/src/kickstart
#export SPLNUTIL_LIB=/net/dooher/src/spln-util/lib

# Get the aliases and functions
if [ -f ~/.bashrc ]; then
	. ~/.bashrc
fi

# User specific environment and startup programs

PATH=$PATH:$HOME/bin:$HOME/usr/bin:/net/sysadm/sbin:/net/sysadm/bin:
BASH_ENV=$HOME/.bashrc
USERNAME="$USER"
HISTSIZE=5000
HISTFILESIZE=5000
HISTIGNORE=ls,asd

LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$HOME/usr/lib:$HOME/oracle/lib

# Peter's settings
EDITOR=vim
ORACLE_HOME=$HOME/oracle

export USERNAME BASH_ENV PATH HISTSIZE HISTFILESIZE HISTIGNORE EDITOR ORACLE_HOME

for i in `ls ~/.bash_profile-* 2>/dev/null`; do
    .  $i
done
