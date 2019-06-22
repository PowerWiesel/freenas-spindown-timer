#!/usr/bin/env bash

# ##################################################
# FreeNAS HDD Spindown Timer
# Monitors drive I/O and forces HDD spindown after a given idle period.
#
# See: https://github.com/ngandrass/freenas-spindown-timer
#
#
# MIT License
# 
# Copyright (c) 2019 Niels Gandraß
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# ##################################################

TIMEOUT=3600       # Default timeout before considering a drive as idle
IGNORED_DRIVES=""  # Default list of drives that are never spun down
VERBOSE=1          # Default verbosity level
DRYRUN=0           # Default for dryrun option

##
# Prints the help/usage message
##
function print_usage() {
    cat << EOF
Usage: $0 [-h] [-q] [-d] [-t TIMEOUT] [-i DRIVE]

Options:
  -q         : Quiet mode. Outputs are suppressed if flag is present
  -d         : Dry run. No actual spindown is performed
  -t TIMEOUT : Number of seconds to wait for I/O before considering a drive as idle
  -i DRIVE   : Ignores the given drive and never issue a spindown for it
  -h         : Print this help message
EOF
}

##
# Writes argument $1 to stdout if $VERBOSE is set
##
function log() {
    if [[ $VERBOSE -eq 1 ]]; then
        echo $1
    fi
}

##
# Retrieves a list of all connected drives (devices prefixed with "ada").
#
# Drives listed in $IGNORE_DRIVES will be excluded.
##
function get_drives() {
    local DRIVES=`iostat -x | grep 'ada' | awk '{print $1}'`

    # Remove ignored drives
    for drive in ${IGNORED_DRIVES[@]}; do
        DRIVES=`grep -v "${drive}" <<< ${DRIVES}`
    done

    echo ${DRIVES}
}

##
# Waits $TIMEOUT seconds and returns a list of all drives that didn't
# experience I/O operations during that period.
#
# Devices listed in $IGNORED_DRIVES will never get returned.
##
function get_idle_drives() {
    # Wait for $TIMEOUT seconds and get active drives
    local IOSTAT_OUTPUT=`iostat -x -z -d ${TIMEOUT} 2`
    local CUT_OFFSET=`grep -no "extended device statistics" <<< ${IOSTAT_OUTPUT} | tail -n1 | grep -Eo '^[^:]+'`
    local ACTIVE_DRIVES=`tail -n +$((CUT_OFFSET+2)) <<< ${IOSTAT_OUTPUT} | awk '{printf $1}{printf " "}'`

    # Remove active drives from list to get idle drives
    local IDLE_DRIVES="$(get_drives)"
    for drive in ${ACTIVE_DRIVES}; do
        IDLE_DRIVES=`grep -v "${drive}" <<< ${IDLE_DRIVES}`
    done

    echo ${IDLE_DRIVES}
}

##
# Forces the spindown of the drive specified by parameter $1 trough camcontrol
##
function spindown_drive() {
    if [[ $DRYRUN -eq 0 ]]; then
        camcontrol standby $1
    fi

    log "Spun down idle drive: $1"
}

# Parse arguments
while getopts ":hqdt:i:" opt; do
  case ${opt} in
    t ) TIMEOUT=${OPTARG}
      ;;
    i ) IGNORED_DRIVES="$IGNORED_DRIVES ${OPTARG}"
      ;;
    q ) VERBOSE=1
      ;;
    d ) log "Performing a dry run..."; DRYRUN=1
      ;;
    h ) print_usage; exit
      ;;
    : ) print_usage; exit
      ;;
    \? ) print_usage; exit
      ;;
  esac
done

# Main program
log "Waiting ${TIMEOUT} seconds for I/O on the following drives: $(get_drives)"

for drive in $(get_idle_drives); do
    spindown_drive ${drive}
done
