# Copyright (C) 2009-2010  Planbureau voor de Leefomgeving (PBL)
#
# full notice can be found in LICENSE



#! /bin/sh

# Run this script to prepare environment variables. 
# Either run it in its own directory or 
# add the script's own directory as a
# command-line argument.
#
# Use this script with sh, ksh, bash or another 
# non-csh-related shell. Invoke with:
# . setup_fordocu.sh [<directory>]
# ([] denotes an optional argument, <> an argument value)

if [ -z "$1" ]
then
    export FORDOCUROOT=`pwd`
else
    export FORDOCUROOT=$1
fi

export PATH=$FORDOCUROOT:$PATH

