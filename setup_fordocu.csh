# Copyright (C) 2009-2010  Planbureau voor de Leefomgeving (PBL)
#
# full notice can be found in LICENSE



#! /bin/csh

# Run this script to prepare environment variables. 
# Either run it in its own directory or 
# add the script's own directory as a
# command-line argument.
#
# Use this script with csh, tcsh or another 
# csh-related shell. Invoke with:
# source setup_fordocu.csh [<directory>]
# ([] denotes an optional argument, <> an argument value)

if ("$1" == "") then
   setenv FORDOCUROOT `pwd`
else
   setenv FORDOCUROOT $1
endif
   
setenv PATH ${FORDOCUROOT}:${PATH}
