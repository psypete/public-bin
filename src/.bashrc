# .bashrc

[ -n "$RC_BEEN_HERE" ] && return
RC_BEEN_HERE=1

# User specific aliases and functions

alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
alias cf='cd /var/cfengine'
alias grep='grep --exclude=.svn'
alias svn='/net/pwillis/bin/svn.sh'
alias xboard='xboard -size 37x37 -ics -icshost localhost'

if [ -f /etc/profile ]; then
    . /etc/profile
fi

# Source global definitions
if [ -f /etc/bashrc ]; then
    . /etc/bashrc
fi

export PATH=/sbin:/usr/sbin:$PATH:$HOME/bin:/usr/local/pkg/bin:/usr/local/pkg/sbin:/usr/local/pkg/rv/bin
export CFINPUTS=/var/cfengine/inputs
export REPOS=https://repo000/repos/
alias route='route -n'

# load any location specific additions
for i in `ls ~/.bashrc-* 2>/dev/null`; do
    .  $i
done

if [ -e $HOME/usr/System/Library/Makefiles/GNUstep.sh ] ; then
    export GNUSTEP_ROOT=$HOME/usr/System
    . $HOME/usr/System/Library/Makefiles/GNUstep.sh
    export CPATH="$CPATH:$HOME/usr/include"
    export C_INCLUDE_PATH=$CPATH
    export CPLUS_INCLUDE_PATH=$CPATH
    export OBJC_INCLUDE_PATH=$CPATH
fi

export LIBRARY_PATH=$HOME/usr/lib

# Needed to compile cpp apps like libcdaudio
# No... apparently just need gcc-c++ package installed (duh!)
#export PATH="$PATH:/usr/lib/gcc-lib/i386-redhat-linux/3.2.3"

export JAVA_HOME=/usr/lib/jvm/java-1.5.0-sun

BLUE=`tput setf 1`
GREEN=`tput setf 2`
CYAN=`tput setf 3`
RED=`tput setf 4`
MAGENTA=`tput setf 5`
YELLOW=`tput setf 6`
WHITE=`tput setf 7`

#set xterm title
case "$TERM" in
  xterm | xterm-color | rxvt)
    XTERM_TITLE='\[\033]0;\W@\u@\H\007\]'
    PROMPT_COMMAND='RET=$?; echo -ne "\033]0;${USER}@${HOSTNAME}: ${PWD}\007"'
  ;;
  *)
    PROMPT_COMMAND='RET=$?'
  ;;
esac;

RET_VALUE='$(echo $RET)' #Ret value not colorized - you can modify it.
RET_SMILEY='$(if [[ $RET = 0 ]]; then echo -ne "\[$GREEN\]:)"; else echo -ne "\[$RED\]:("; fi;)'
PS1="\[$GREEN\]\u@\h \[$BLUE\]\w/\[$GREEN\] $RET_SMILEY\[$WHITE\] "

