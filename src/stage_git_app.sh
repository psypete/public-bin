#!/bin/bash
# stage_git_app.sh - checkout a version of a git repository and run an app
# 
# The purpose of this script is to make a temporary copy of the git repository
# and run an application on it. It is mainly used to test an application on a
# local repo while actively developing on it. For example, long-running tests
# that you may want to run on a given codebase, but still be able to continue
# development in a different branch while the test is running.
# 
# It is assumed this script lives in a 'bin' directory in the repository.
# 
# Example:
#  1. Make some changes to your local repo
#  2. Run your app with stage_git_app.sh
#  2a. Now your app is running with the branch you specified, but in a temp
#      directory isolated from your repo.
#  3. In your repo, continue development, and app run is unaffected
# 

PGM="stage_git_app"

# Make temp directories readable by other users
umask 0022

# Resolve full path to wrapper script
pushd . > /dev/null
SCRIPT_PATH="${BASH_SOURCE[0]}";
if ([ -h "${SCRIPT_PATH}" ]) then
  while([ -h "${SCRIPT_PATH}" ]) do cd `dirname "$SCRIPT_PATH"`; SCRIPT_PATH=`readlink "${SCRIPT_PATH}"`; done
fi
cd `dirname ${SCRIPT_PATH}` > /dev/null
SCRIPT_PATH=`pwd`
popd  > /dev/null

# Strip the '/bin' from $SCRIPT_PATH
# If your script isn't in a 'bin' directory in your repo,
# modify REPO_PATH to point to your repo's root directory
REPO_PATH="${SCRIPT_PATH%/*}"

DIR=`mktemp -d`
# Make temp directory readable by other users
chmod 755 "$DIR"
if [ ! -d "$DIR" ] ; then echo "Error: could not make temp directory" ; exit 1 ; fi
echo "$$" > "$DIR/$PGM.pid"

if [ $# -eq 0 -o "$1" = "-h" ] ; then
    cat <<EOUSAGE
Usage: $0 [--branch BRANCH] [ARGS ..]

This script is a wrapper around any application. It will first copy 
the current HEAD of the repository this script resides in into a
temp directory. Then it runs an application (provided as arguments
to this script) in the directory with the ARGS you specify. 

Use the optional --branch option to specify a branch or commit to
check out before running the application. If you do not specify the
--branch option, it will default to HEAD. To find out what your
current 'HEAD' is, use \`cat .git/HEAD\`.

If HEAD is used, any unstaged changes in your repo's working
directory will be applied on top of the checked-out HEAD using 
'git diff-files --binary'. This is only done for HEAD.

The BRANCH value can be any 'tree-ish' object to git, such as a
commit or git tree, relative to the repository that this script is
located in.

If you use --branch, it MUST be the first argument, and it MUST
be followed by a git commit, tree or branch. After that the rest
of the arguments are executed in the temp directory.

Examples:

 - To check out the HEAD and run the application:

    $ /repo/bin/$PGM.sh ./bin/someapp-in-repo --argument --blah 123

 - To check out the 'bug_12345' branch and run the application:

    $ /repo/bin/$PGM.sh --branch bug_12345 ./bin/someapp -p foobar

 - To check out commit 8eba6cdcd31a9a97e30dedb79b6e3cd95d1edea6
   and run the application:

    $ /repo/bin/$PGM.sh --branch 8eba6cdcd31a9a97e30dedb79b6e3cd95d1edea6 ./bin/myapp --argument1 --argument2

EOUSAGE

    rm -rf "$DIR"
    exit 1
fi

BRANCH="HEAD"
if [ "$1" = "--branch" ] ; then
    BRANCH="$2"
    shift
    shift
fi

echo "Cleaning up old temp directories..."
for OLDD in $(find /tmp/tmp.* -maxdepth 0 -uid $UID 2>/dev/null) ; do
    pid=`cat $OLDD/$PGM.pid 2>/dev/null`
    if [ x"$pid" = "x" -o ! -d "/proc/$pid" ] ; then
        echo ""
        echo "Warning: an old temporary directory was found."
        echo "The old wrapper process is no longer running. (process '$pid')."
        echo -en "Would you like to clean up the old directory '$OLDD' ? [Y/n] "
        read ANSWER
        if [ x"$ANSWER" = "x" -o "$ANSWER" = "y" -o "$ANSWER" = "Y" ] ; then
            echo "Deleting old directory '$OLDD' ..."
            rm -rf "$OLDD"
        fi
    fi
done


echo ""
echo "Checking out index $BRANCH of repo $REPO_PATH to $DIR ..." &&
cd "$REPO_PATH" &&

# Do not forget the trailing slash on $DIR here!
# Otherwise it will just prefix every file
# with "/some/path"
#git checkout-index -a -f --prefix="$DIR/" &&

git archive --format=tar $BRANCH | tar -xC "$DIR"

if [ $? -ne 0 ] ; then
    echo "Error: could not archive git; exiting"
    exit 1
fi

# Copy over a diff of changed local files and apply the diff
# if we're working on HEAD, since there may be local changes
# in the working directory.
( if [ "$BRANCH" = "HEAD" ] ; then
    echo "Applying any locally changed files to $DIR ..." ;
    git diff-files --binary > "$DIR/$PGM.diff" ;
    if [ -s "$DIR/$PGM.diff" ] ; then
        cd "$DIR" ;
        git apply --binary "$PGM.diff" ;
    else
        /bin/rm -f "$DIR/$PGM.diff" ;
    fi ;
  fi
)

if [ $? -ne 0 ] ; then
    echo "Error: could not apply locally-changed files; exiting"
    exit 1
fi

# Hack for a specific problem; ignore
## Copy any -c argument files (that might not have been fully-qualified paths)
## over to the new $DIR so the application can use them
#cd "$REPO_PATH" &&
#for file in $* ; do
#    if [ -f "$file" ] ; then
#        echo "Copying file '$file' to '$DIR/'" ;
#        cp --parents "$file" "$DIR/" ;
#    fi
#done &&

cd "$DIR" &&

echo ""
echo -en "Running $@\n\n" &&
"$@"
RET=$?

if [ ! "x$CLEANUP_ON_EXIT" = "x0" ] ; then
    cd ..
    rm -rf "$DIR"
    exit $RET
fi
