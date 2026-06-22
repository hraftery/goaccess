#!/bin/bash
#
# logrotate_one [options] {logrotate.d_file}
#
# Run the logrotate against a single sub-configuration file, while also
# defining the global settings from /etc/logrotate.conf
#
# For example verbose the log rotation of the 'samba' logs
#   logrotate_one samba
# Or debugging (dryrun) of the sssd files
#   logrotate_one -d sssd
#
# This is needed because "logrotate" does not have any option to limit what it
# rotates, and rotating using a sub-configuration file directly will NOT
# include any 'global' settings.   The "logrotate" command only allows you to
# use configuration from a REAL file, not pipelines or other special files.
# Basically it is hard to work with.
#
# The logrotate -v flag is enabled by default.
#
####
#
# ASIDE: As a helpful hint I sometimes find it good to force a log rotation
# by editing the file "/var/lib/logrotate/logrotate.status" and changing
# the date of the last rotation to the previous year.  While there I would
# also often delete log file entries that no longer exist.
#
# Extra hint.  Sort the "logrotate.status" file, but keep the first line
# as the first line, It makes it a lot easier to find the log files you are
# looking for. Log rotate does not care about the file order, and will even
# scramble the order again next time it runs.
#
###
#
# Anthony Thyssen <A.Thyssen@griffith.edu.au>   20 November 2016
#
# Discover where the shell script resides
PROGNAME=`type "$0" | awk '{print $3}'`  # search for executable on path
PROGDIR=`dirname "$PROGNAME"`            # extract directory of program
PROGNAME=`basename "$PROGNAME"`          # base name of program

Help() {   # Output Full header comments as documentation
  sed >&2 -n '1d; /^###/q; /^#/!q; s/^#//; s/^ //; p' \
          "$PROGDIR/$PROGNAME"
  exit 10;
}
case "$1" in
  -\?|-help|--help|--doc*) Help ;;
esac

# BASHisms..
#  last argument    = "${@:(-1)}"
#  Other arguments  = "${@:1:($#-1)}"

# Is there a logrotate configuration of this name?
if [ ! -f /etc/logrotate.d/"${@:(-1)}" ]; then
    echo >&2 "$PROGNAME: Unable to find \"/etc/logrotate.d/${@:(-1)}\""
    exit 1
fi

# Precaution -- you couldn't have log rotates in the global file!
if grep -q '{' /etc/logrotate.conf; then
  echo >&2 "$PROGNAME: \"/etc/logrotate.conf\" contains log rotations!"
  echo >&2 "  these should be moved into a separate sub-conf file. ABORTING"
  exit 10
fi

# Generate a log rotate file with global settings but without the 'include'
# NOTE: logrotate only works with REAL FILES!  -- Arrgghhhh!
# The file will auto-delete when script exits

umask 77
tmp=`mktemp "${TMPDIR:-/tmp}/$PROGNAME.XXXXXXXXXX"` ||
  { echo >&2 "$PROGNAME: Unable to create temporary file"; exit 10;}
trap 'rm -f "$tmp"' 0
trap 'exit 2' 1 2 3 15

grep -hv '^include ' /etc/logrotate.conf > "$tmp"

# now lets do the log rotate with the pre-prepared global file
# HR260622: remove default -v flag because it writes to STDERR so can't be
#           suppressed by the caller without affecting error output.
logrotate "${@:1:($#-1)}" "$tmp" /etc/logrotate.d/"${@:(-1)}"
echo ''

# tmp file is auto-cleaned
