# Copyright (C) 2009-2010  Planbureau voor de Leefomgeving (PBL)
#
# full notice can be found in LICENSE

package utils;
#
require 5.003;

use strict;
use warnings;
use File::Glob ("bsd_glob");
use f90fileio('currently_reading', 'main_file');

use vars('$VERSION','@ISA','@EXPORT_OK');
@ISA = ('Exporter');
our $errwarndir      = './';

our @EXPORT_OK = (
    'remove_files',     # delete files in directory but leave .svn directories
    'filesep',          # return the correct separator character for file paths
    'trim',             # Strip leading and trailing spaces from a string
    'balsplit',         # Splits a string taking '()'-s into account
    'my_die',           # Produce an extensive error message (but do not die)
    'split_path',       # Split the given input path into an array of directories.
    'backticks_without_stderr', # Run command, return stdout but discard stderr
    'print_hash',       #  Print a hash struct to the screen recursively.
);

#########################################################################

sub remove_files ($);

sub remove_files ($)
{

=head2 remove_files($dir)

   Remove the files in the given directory but leave .svn directories intact

   INPUT VARIABLES
      $dir - name of the directory from which the files
             are to be removed

=cut

   my $dir = shift;

   ## Get directory contents.
   my @paths = bsd_glob ("$dir/*");

   ## Loop over all files/directories in directory.
   foreach my $path (@paths) {
      if (-d $path) {
         ## current path is a directory: find all files recursively but do
         ## nothing if it is a .svn directory!
         if ( !($path =~ m/.svn$/) ) {
            remove_files("$path") ;
         }
      } else {
         ## current path is a file: DELETE it.
         unlink ($path) if (-f $path);
      }
   }
}

#########################################################################

sub filesep()
{

=head2 $fs = filesep

   return the correct separator character for file paths

   OUTPUT VARIABLES
      $fs - file separator character

=cut

   return "\\" if $^O =~ /win/i;
   return '/';
}

#########################################################################

sub trim
{

=head2 $stringout = trim($stringin)

  Strip leading and trailing spaces from a string

  INPUT VARIABLES
    $stringin  - input string

  OUTPUT VARIABLES
    $stringout - output string, equal to input string without leading
                 and trailing spaces

=cut

   my ($s) = @_;
   return unless $s;
   $s =~ s/^\s*//;
   $s =~ s/\s*$//;
   return $s;
}

#########################################################################

sub balsplit
{

=head2 substr($str, $left) = balsplit($sep,$str)

  Splits a string into pieces divided by sep when
  sep is "outside" ()s. Returns a list just like split.

  INPUT VARIABLES
    $sep  - seperation mark
    $str  - string to split

  OUTPUT VARIABLES
    $str  - part of the string that is separated
    $left - position where string is divided

=cut

   my ($sep, $str) = @_;
   my ($i, $c);
   my ($len, $level, $left) = (length($str), 0, 0);
   my (@list) = ();

   for ($i = 0 ; $i < $len ; $i++)
   {
      $c = substr($str, $i, 1);
      if ($c eq "(")
      {
         $level++;
      }
      elsif ($c eq ")")
      {
         $level--;
         die "balsplit: Unbalanced parens (too many )'s)" if $level < 0;
      }
      elsif ($c eq $sep && $level == 0)
      {
         push(@list, substr($str, $left, $i - $left));
         $left = $i + 1;
      }
   }

   push(@list, substr($str, $left));
   return @list;
}

#########################################################################
sub my_die($;$)
{

=head2 my_die($msg;$type)

   Write a with a proper error message, including a call stack
   but do not die

   INPUT VARIABLES
      $msg  - description of what went wrong
      $type - message type (e.g. 'ERROR', 'WARNING', 'NEWSFLASH')

=cut


   my $msg = shift;
   my $type= shift;
   $type='ERROR' unless ($type);

   my $warning = "\n" . "************************" x 3 . "\n\n";

   # Print the error message and the location where it went wrong
   my ($package, $file, $line, $call) = caller(0);
   $file =~ s/.*[\/\\]//;
   $warning .= "$type in line $line of '$file':\n\n" . "     $msg";

   # The following :: operators are necessary, despite the use-line above.
   # I don't understand why. I suggest leaving it like this and not spending
   # time on it.
   my ($iline,    $file2)    = f90fileio::currently_reading();
   my ($mainfile, $mainline) = f90fileio::main_file();
   $warning .= "\n\n     " . lc($type) . " occurred in line $iline of $file2\n"
            if ($iline>=1 and $file2);
   $warning .= "     from 'include' in line $mainline of $mainfile\n"
     if ($mainfile and $file2 and $mainfile ne $file2);
   $warning .= "\n\n";

   # Print the call stack
   $warning .= "     Call stack:\n";
   my $i = 1;
   do
   {
      ($package, my $file, my $line, my $call) = caller($i);
      $file =~ s/.*[\/\\]// if $file;
      $i++;
      $warning .= "       line $line of file $file: call $call\n"
        if $package;
   } until !$package;

   $warning .= "\n" . "************************" x 3 . "\n\n";

   if ($type eq "ERROR") {
      open ERRORS, ">>$errwarndir/fordocu.err"
           or die("\n\nCannot open '$errwarndir/fordocu.err' for appending\n\n");
      print ERRORS $warning;
   } else {
      open WARNINGS, ">>$errwarndir/fordocu.warn"
           or die("\n\nCannot open '$errwarndir/fordocu.warn' for appending\n\n");
      print WARNINGS $warning;
   }
   warn $warning;
}

#########################################################################
sub split_path($) {

=head2 split_path

 Split the given input path into an array of directories.

 INPUT VARIABLES

    $inpath - input path (starts with -I; (semi)colon-separated)

 OUTPUT VARIABLES

    Array of input directory names

=cut

   my $inpath = shift;
   $inpath =~ s/^-I//gi;

   if ( $inpath =~ /;/ ) { return split( /;/, $inpath ); }
   return split( /:/, $inpath );
}

#########################################################################

sub backticks_without_stderr($) {

=head2 $out = backticks_without_stderr($cmd)

   Run the command (on the Operating System) and return the
   output. Redirect standard error so that error messages
   remain invisible.

   INPUT VARIABLES
       $cmd - command to be run

   OUTPUT VARIABLES
       $out - standard-out of the program

=cut

  my $cmd = shift;
  my $out;

  # Create the correct name for the null-device
  my $nullfile = "/dev/null";
  if ($^O !~ /x/i) { $nullfile = "null"; }

  # Remember what STDERR currently is, and then redirect STDERR to null device
  open (ORIGSTDERR, ">&STDERR") or my_die("Failed to save STDERR");
  print ORIGSTDERR "";
  open (STDERR, ">$nullfile")   or my_die("Failed to redirect STDERR to null device");

  # Run the command
  $out = `$cmd`;

  # Set STDERR back to what it was.
  open (STDERR, ">&ORIGSTDERR") or my_die("Failed to restore STDERR");

  return $out;
}

#########################################################################
sub print_hash ($$;$$);    # Recursive

sub print_hash ($$;$$)
{

   #  print_hash ($hash, $header, $indent, $print_header);
   #
   #  Print a hash struct to the screen recursively.
   #
   #  ----------------------------------------------------------------
   #
   #  INPUT VARIABLES
   #
   my $hash         = shift;    # Pointer to the hash that should be printed.
   my $header       = shift;    # Header with info about the hash to be printed
                                # to the screen.
   my $indent       = shift;    # Number of positions to indent a key/value pair.
   my $print_header = shift;    # Flag that indicates whether the header should
                                # be printed (1 = yes = default, 0 = no).

   #
   #  ----------------------------------------------------------------------------
   #
   #  OUTPUT VARIABLES
   #
   #  None.
   #
   # --------------------------------------------------------------------------

   # Default indentation is three columns.
   $indent = 3 if (not defined($indent));
   return if ($indent > 12);

   # The header is printed by default.
   $print_header = 1 if (not defined($print_header));

   # Print information header to the screen if requested.
   print "\n" . "$header " . "($hash):\n" if ($print_header);

   # Define indentation string.
   my $indent_str = " " x $indent;

   # Loop over all keys in the hash.
   foreach my $key (sort (keys(%$hash)))
   {

      # Determine type of the value.
      my $value = $hash->{$key};
      my $type  = ref($value);

      if ($type ne "HASH")
      {

         # If value does not contain a hash, print key/value pair to the
         # screen.
         printf "%s%-15s : %-20s\n", $indent_str, $key, $value;
      }
      else
      {

         # If value contains a hash, only print the key to the screen and call
         # current sub recursively to print the sub-hash to the screen.
         printf "%s%-15s :\n", $indent_str, $key;
         my $indent   = $indent + 3;
         my $sub_hash = $hash->{$key};
         print_hash($sub_hash, '', $indent, 0);
      }
   }
}


1;
