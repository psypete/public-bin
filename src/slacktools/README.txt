All the stuff in this directory works.

Useful scripts:

 * backoutpkg               - If you have lost the original Slackware package
                              you installed on your system, run this script and
                              it will re-create the package based on the
                              installed one.

 * slackconfig              - Handles the './configure' part of building a
                              Slackware package from source code before 'make'.
 
 * slackmake                - Handles the 'make' and 'make install' part of
                              building a Slackware package, and packages it.
                              

 * slackpack                - Given a tarball, extracts it and runs slackconfig
                              and slackmake, then moves the built package back
                              to the current directory and removes temporary
                              build files.
 
