@echo off

rem Copyright (C) 2009-2010  Planbureau voor de Leefomgeving (PBL)
rem 
rem full notice can be found in LICENSE


rem Run this script to prepare environment variables. 
rem Either run it in its own directory or 
rem add the script's own directory as a
rem command-line argument.
rem
rem Invoke with:
rem setup_fordocu.bat [<directory>]
rem ([] denotes an optional argument, <> an argument value)

if "%1"=="" (
   set FORDOCUROOT=%~dp0
) else (
   set FORDOCUROOT=%1
)

set PATH=%FORDOCUROOT%;%PATH%

echo FORDOCUROOT is set to '%FORDOCUROOT%'

