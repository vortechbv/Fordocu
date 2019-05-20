# Copyright (C) 2009-2010  Planbureau voor de Leefomgeving (PBL)
#
# full notice can be found in LICENSE

package f90fileio;

=head1 PACKAGE f90fileio

 This package contains functions to read F90 sources.

=head1 CONTAINS

=cut

require 5.003;

use strict;
use warnings;

use List::Util qw[max];
use utils ('my_die', 'trim', 'filesep', 'split_path');

use vars ('$VERSION', '@EXPORT_OK', '@ISA');
$VERSION = '1.0';
@ISA     = ('Exporter');

our @EXPORT_OK = (
    'open_file',        'read_line',        'currently_reading',
    'main_file',        'get_string',       'code_and_comment',
    'set_fileiooption', 'fixed_fortran',
    'return_strings',   'guessed_format',   'hashed_comments',
    'reset_comments',   'line_number',
    'clear_pseudocode', 'get_pseudocode',   'after_comments'
);

###########################################################################
#
# PUBLIC VARIABLES (SETTINGS)
#

# Set this to use fixed-form Fortran, like good old Fortran 77.
our $fixed_form    = 0;
our $fixed_linelen = 72;
our $single_bang   = 0;
our $comments_eol  = 0;

# Search directories
our @input_path;


###########################################################################
#
# PRIVATE VARIABLES (ADMINISTRATION)
#

# Set this to descend into include files and treat the contents as
# part of the subroutine.
my $follow_includes = 1;

# A "left-over" piece of a statement is stored here when semi-colons are
# encountered.
my $leftover    = "";
my $leftover_no = 0;    # Line number

# Count number of continution lines read (if any)
my $continuation_counter = 0;

# List of strings' values.
my @strings = ();

# Administration of opened files:
my $nfile        = 0;     # number of open files
my @openfiles    = ();    # names of open files
my @orgfilenames = ();    # original names of open files
my @line_numbers = ();    # line numbers where last reading in file
my $openfile     = '';    # name of file where last line came from
my $orgfilename  = '';    # original name of file where last line came from
my $current_line_start= 0; # Begin and end of the line returned last by read_line
my $current_line_end  = 0;


# Administration of accumulated comments
our @collected_comments      = ();
our $comments_started_at     = 0;
our $comment_is_eoln         = 0;
our %macrodata               = ();

#
# macrodata is a struct with the following items in it:
#
#   _current       => key of the macro currently under construction
#   _order         => array with the keys in chronological order
#   $key           => array with lines for the meaning of the macro
#                     with the name $key
#
#   A special key is 'see', because it is processed differently.
#   This key is not stored in the field _order.
#

our $pseudocode = '';

#########################################################################
sub get_pseudocode() {
   my $pseudo = $pseudocode;
   $pseudocode = '';
   return $pseudo;
}

sub set_fileiooption($;$){
   my $option = shift;
   if (not @_)  {
      if    ($option eq 'comments_eol'            ) { $comments_eol= 1;}
      elsif ($option eq 'fixed'                   ) { $fixed_form  = 1;}
      elsif ($option eq '!'                       ) { $single_bang = 1;}
      elsif ($option eq 'free'                    ) { $fixed_form  = 0;}
      else          {my_die("unknown option '$option'"); die;}
   } elsif (@_ ==1) {
      my $arg = shift;
      if    ($option eq 'add_path'      ) { push(@input_path, split_path($arg)); }
      elsif ($option eq 'fixed_linelen' ) { $fixed_linelen = $arg;}
      else          {my_die("unknown option '$option'"); die;}
   } else {
     my_die("too many (@_) arguments for option '$option'\n");
   }
}

sub reset_comments () {

=head2 reset_comments

 Empty the variables used to store the internal documentation
 after they have been stored in structs so they can be processed into
 HTML and/or code.

=cut

   @collected_comments      = ();
   %macrodata               = ();
   $comments_started_at     = 0;
   $comment_is_eoln         = 0;
}

sub clear_pseudocode() {$pseudocode='';}

#------------------------------------------------------------------------
sub hashed_comments()
{

=head2 %comments = hashed_comments ()

  Returns a list that would fit right into a hash table you're making.

  OUTPUT VARIABLES
      %comments - a hash consisting of the field 'comments'
                  whose value is the current comments

=cut

   my %mdcopy   = %macrodata;
   my @comments = @collected_comments;

   foreach my $item (@comments) {
      $item->{printed} = 0;
      $item->{guessed} = 0;
      if ($item->{line} =~ /!\?/) { $item->{guessed} = 1;}
      $item->{after_the_line} = 0,
   }

   return (
           'collected_comments' =>  \@comments,
           'macrodata'          =>  \%mdcopy,
   );
}

#------------------------------------------------------------------------
sub after_comments($)
{

=head2 @comments = after_comments ($type??)

  Returns the comment lines which are assumed to belong to the previous
  statement, being a module, subroutine, program or function

  INPUT VARIABLE
      $stmt - statement classification of the statement just read,
              i.e. the first statement inside the subroutine etc.

  OUTPUT VARIABLE
      @comments - comments for the module, subroutine, program or function

   The comments assigned to the subroutine etc are removed from the
   collected comments, so they won't also be given to the next statement.

=cut

   my $stmt = shift;
   my @comments =();

   if ($stmt ne "var" or $comments_eol) {
      # In general, we assume the explanations right after the
      # subroutine/program/etc declaration to explain the subroutine. Only the
      # end-of-line comments (after the new line of code) obviously don't belong
      # to to the subroutine.

      my @kept_comments = ();
      foreach my $item (@collected_comments) {
         if ($item->{comment_is_eoln}) {
            push(@kept_comments, $item)
         } else {
            $item->{after_the_line} = 1;
            push(@comments, $item)
         }
      }
      @collected_comments = @kept_comments;
   } else {
   # In case of multiple variable explanation paragraphs, the last paragraph
   # may be the explanation of the next variable,

      # Identify the text before the last paragraph
      my $i = $#collected_comments;
      my $iend=$i;
      while ($i >= 1) {
         if ($collected_comments[$i]->{line} =~ /^!*\\nEMPTY_LINE\\n$/) {
            $iend = $i; last;
         }
         $i--;
      }

      # Assign the text before the last paragraph to the subroutine etc,
      # and the last paragraph to the variable.
      my @kept_comments = ();
      $i = 0;
      foreach my $item (@collected_comments) {
         if ($item->{comment_is_eoln}) {
            push(@kept_comments, $item)
         } elsif ($i>$iend) {
            push(@kept_comments, $item)
         } else {
            $item->{after_the_line} = 1;
            push(@comments, $item)
         }
         $i++;
      }
      @collected_comments = @kept_comments;
   }

   return \@comments;
}

#########################################################################
sub do_macro($;$) {

=head2 do_macro($macro,$current)

 Process the fordocu-comment macros (comments with a @):

 INPUT VARIABLES

      $macro="@see $reference [#$part]" (to $reference.html)
      $macro="@author $author"
      $macro="@version $version"
      $macro="@p $pseudocode"
      etc.

      $current: name of the current hash key in macrodata to add to

=cut

   my ( $macro, $current ) = @_;

   # Remove blanks at end of macro
   $macro =~ s/\s*$//;

   if ($current) {
      push( @{ $macrodata{$current} }, $macro );
   } elsif ( $macro =~ /^see/i ) {

      # Process @see $reference [# $part]
      #
      #  a HTML-reference is made to $reference.html
      #  at location $part

      # Check correct macro syntax
      my_die('Invalid @see macro')
         unless $macro =~ /^see\s+(\w+)(#\w+)?$/;

      my $reference = $1;
      my $part      = $2;

      if ($part) {

         # Optional part-address given: make a location-type reference
         # remove #-character from part
         $part = substr( $part, 1 );

         push( @{ $macrodata{see} },
              '<A HREF="'
              . "$reference.html#"
              . lc($part) . '">'
              . "$part</A> in module "
              . "<A HREF=\"$reference.html\">$reference</A>"
             );
      } else {

         # Optional part-address not given: make a reference to the html-file
         push( @{ $macrodata{see} },
              "module <A HREF=\"$reference.html\">$reference</A>"
             );
      }
   } elsif ( $macro =~ /^p\s/i ) {

      # Add pseudocode text to $pseudocode
      # as well as to @comments
      $pseudocode .= "\n" if $pseudocode;
      $pseudocode .= $';
   } elsif ($macro =~ /^(\w.*)\s+\:\s*/i   or
            $macro =~ /^(\w+)\b\s*[\:]?\s*/i ) {

      # There are two types of macro supported:
      #  + one with the keyword ending with a space and then
      #    a colon. Due to the colon format, it is possible that
      #    an incorrect guess is made...
      #  + one without the space-and-colon. In this case, keywords
      #    have to be a single word.

      # Store most macro values in %macrodata
      # The lower case macro name is the key name
      my ( $key, $value ) = ( lc($1), $' );
      $key =~ s/\s+$//g;

      $macrodata{_order}   = [] unless $macrodata{_order};
      $macrodata{$key}     = [] unless $macrodata{$key};
      $macrodata{_current} = $key;

      push( @{ $macrodata{_order} }, $key );
      push( @{ $macrodata{$key} },   $value );

   } else {

      # Error: unrecognized macro
      my_die("Unrecognized macro $macro");
   }
   return;
}

#--------------------------------------------------------------
sub addto_comments($) {

=head2 addto_comments($com);

 Read the special fordocu-comments (the ones preceded by !!)
 and store their contents in the arrays of the module.


 INPUT VARIABLES

   $com     a line from the Fortran-code, possibly containing
            fordocu-comments
   $lineno  current source file line number

 OUTPUT VARIABLES

   All comments except macros are stored in @comments.
   Macros are passed to routine do_macro (See there)

=cut

   my $line = shift;
   my $com  = $line;

   # Remove anything before !, !! or !!?
   $com =~ s/\s*!!*\?*//;

   # Check for macros and paragraph breaks.
   if ( $com =~ /^\s*@/ ) {
      $com =~ s/^\s*@\s*//;
      do_macro($com);
   } elsif ( $macrodata{_current} ) {
      $com =~ s/^\s*//;
      if ($com) {
         do_macro( $com, $macrodata{_current} );
      } else {
         $macrodata{_current} = '';
      }
   }

   my %comment_item = (
      line            => $line,
      comment_is_eoln => $comment_is_eoln ,
      guessed         => 0,
   );
   if ($line =~ /!\?/) { $comment_item{guessed} = 1;}

   push (@collected_comments, \%comment_item);

}


#------------------------------------------------------------------------
sub continuation()
{

=head2 ($counter) = continuation();

  Return the value of the continuation counter.

  OUTPUT VARIABLES
     $counter  - value of the continuation counter

=cut

   return 0 if $nfile == 0;
   return $continuation_counter;
}

#------------------------------------------------------------------------
sub line_number(;$)
{

=head2 ($iline) = line_number([$startend]);

  Return the location where the last line was read.

  INPUT VARIABLES
     $startend - 'start' (default): line number where line started
                 'end':             line number where line ended
                 'comment_start':   line number where comments leading up
                                    to this line started

  OUTPUT VARIABLES
     $iline  - line number from which current line came

=cut
   my $startend = shift;

   return 0 if $nfile == 0;

   if (defined $startend and $startend eq "comment_start") {
     return $comments_started_at
        if ($comments_started_at and (not $comment_is_eoln));
     return $current_line_start;
   } elsif (defined $startend and $startend eq "end") {
      return $current_line_end;
   } else {
      return $current_line_start;
   }
}

#------------------------------------------------------------------------
sub currently_reading()
{

=head2 ($iline,$file) = currently_reading();

  Return the location where the last line was read

  OUTPUT VARIABLES
     $iline  - line number from which current line came
     $file   - file name from which current line came

  This subroutine may also be called for $iline alone, without
  brackets:
      $iline = currently_reading();

=cut

   return ($current_line_start, $openfile, $orgfilename) if wantarray;
   return $current_line_start;
}

#------------------------------------------------------------------------
sub main_file()
{

=head2 ($file,$line) = main_file();

  Return the name of the file where the code started

  OUTPUT VARIABLES
     $file   - main file name

=cut

   if (wantarray) { return ($openfiles[0], $line_numbers[0]); }
   else           { return $openfiles[0]; }
}

#------------------------------------------------------------------------
sub code_and_comment ($;$)
{

=head2 ($code,$comment) = code_and_comment($line,[$no_cmt_handling]);

  Separate comments from code.
  INPUT VARIABLES
     $line  - a line of Fortran-source
     $no_cmt_handling - if set to 1, skip comment storage
  OUTPUT VARIABLES
     $code     - the Fortran-code (source stripped of comments)
     $comments - the stripped comments

  This subroutine may also be called for $code alone, without
  brackets:
      $code = code_and_comment($line);

=cut

   my ($line, $no_cmt_handling) = @_;
   my $code    = $line;
   my $comment = '';

   # In fixed form, comments may start with several codes,
   #    [*, d, c, D, C, #, !]; possibly others. Any line starting with
   # non-space is therefore interpreted as a comment line: replace first
   # character by !
   substr($code, 0, 1) = '!'
     if (($fixed_form)
         and not($code =~ /^[0-9\s]/));

   # In free format, the comments start with ! Compiler directives, however,
   # start with '#'. These are ignored
   $code = '' if ($code =~ /^#/);

   unless ($no_cmt_handling) {

      my $is_eoln = ($code =~ /^\s*[^!].*[A-Za-z0-9]+.*!/);
      $comment_is_eoln = 1 if ($is_eoln);

      # Store line number if this is a new comment block
      if (not $comments_started_at and $code ne '') {
         $comments_started_at = $line_numbers[$nfile - 1];
      }

      if ($code =~ /^([^"'!]|('[^']*')|("[^"]*"))*(!.*)$/) {
         # Grab single comments (!)
         addto_comments($4);
      }
   }

   # Separate comments from code
   if ($code =~ /^([^"'!]|(\'[^']*')|("[^"]*"))*!(.*)$/)
   {
      $code = substr($line, 0, length($line) - length($4) - 1);
      $comment = $4;
   }
   return ($code, $comment) if wantarray;
   return $code;
}

#------------------------------------------------------------------------
sub get_string ($)
{

=head2 $str = get_string($n);

  Returns the physical value for the given string number.

  INPUT VARIABLES
     $n   - index of string to be returned
  OUTPUT VARIABLES
     $str - f90fileio's $n-th string

=cut

   my $n = shift;
   return $strings[$n];
}

#------------------------------------------------------------------------
sub return_strings($)
{

=head2 $strout = return_strings($strin);

  Returns the physical value for the given string numbers
  for all strings in the given $strin.

  INPUT VARIABLES
     $strin  - input string
  OUTPUT VARIABLES
     $strout - output string with all $strin's strings returned

=cut

   my $strin  = shift;
   my $strout = '';

   for (my $pos = 0 ; $pos < length($strin) ; $pos++) {
      my $char = substr($strin, $pos, 1);
      if ($char eq "\'") {
         my $nextpos = index($strin, "\'", $pos + 1);
         if ($nextpos > $pos + 1) {
            my $key = substr($strin, $pos + 1, $nextpos - $pos - 1);
            $char = get_string($key);
            $pos  = $nextpos;
         }
      }
      $strout .= $char;
   }
   return $strout;
}

#------------------------------------------------------------------------
sub find_file ($)
{

=head2 find_file ($filename);

  Tries to find the file specified.
  Returns the path of the file found.

  INPUT VARIABLES
      $filename - name of the file to be found.
  OUTPUT VARIABLES
      $result - full file path if found - empty if not found

=cut

   my $filename = shift;

   use File::Basename;

   my $fsep   = filesep();
   my $locdir = '.';
   $locdir = dirname($orgfilenames[0]) if ($nfile > 0);

   foreach my $dir ($locdir, '.', @input_path) {
      my $fname = $dir eq '.' ? $filename : "$dir$fsep$filename";
      return $fname     if (-f $fname);
      return uc($fname) if (-f uc($fname));
      return lc($fname) if (-f lc($fname));
      $fname = "$dir$fsep" . ucfirst(lc($filename));
      return $fname if (-f $fname);
      $fname = "$dir$fsep" . uc($filename);
      return $fname if (-f $fname);
      $fname = "$dir$fsep" . lc($filename);
      return $fname if (-f $fname);
   }
   return "";
}

#------------------------------------------------------------------------
sub open_file ($)
{

=head2 open_file ($filename);

  Starts reading the specified file and adds the file
  to the open file administration

  INPUT VARIABLES
      $filename - name of the file to be opened
  OUTPUT VARIABLES
      File handle IN is set;
      f90fileio's file administration is updated

=cut

   my $filename = shift;

   my $fname = find_file($filename);
   my_die("Couldn't find $filename") if (!$fname);

   open(IN, $fname)
      or my_die("Couldn't open file '$fname'");
   $openfiles[$nfile]    = $fname;
   $orgfilenames[$nfile] = $filename;
   $line_numbers[$nfile] = 0;
   $nfile++;
   $continuation_counter = 0;
}

#------------------------------------------------------------------------
sub close_file ()
{

=head2 close_file ()

 Cleans up from reading the current file.
 Possibly goes back to point in previous file from where current file
 was entered.

=cut

   close IN;
   $nfile--;
   if ($nfile > 0) {
      # Open files remain: close curent file, open previous one and
      # discard the first lines until the point where the current file was
      # entered
      $continuation_counter = 0;
      my $iline    = $line_numbers[$nfile - 1] - $continuation_counter;
      my $filename = $openfiles[$nfile - 1];
      open IN, $filename
         or my_die("cannot open file '$filename'");

      foreach my $i (1 .. $iline) { my $line = <IN>};
   } else {
      # No more files open: clean up strings
      @strings = ();
   }

   # Reset stored comments
   @collected_comments   = ();
   $comments_started_at  = 0;
   $continuation_counter = 0;
   return;
}

#------------------------------------------------------------------------
sub may_ignore_comment_line()
{

=head2 ($ok) = may_ignore_comment_line()

  The current line read is a comment line;
  preview whether the first non-empty,
  non-comment line is a fixed format continuation
  line. If it is, the current line must be skipped.

=cut

   my $pos  = tell(IN);
   my $ok   = 0;
   my $line = <IN>;
   chomp($line) if $line;
   while ($line) {
      # Ignore subsequent comment and empty lines
      if ($line !~ /^\s*$/ && $line !~ /^[^0-9\s]/) {
         $ok = ($line =~ /^\s....\S/);
         last;
      }
      $line = <IN>;
      chomp($line) if $line;
   }
   seek(IN, $pos, 0);
   return $ok;
}

#------------------------------------------------------------------------
sub read_file_line()
{

=head2 ($line,$lineno) = read_file_line ();

   Read a 'file line' (text starting after \n and ending at next \n).
   Possibly, a new or previous file must be entered to find the next
   line in the program

   OUTPUT VARIABLES
       $line   - next line in the Fortran code
       $lineno - the line number of that line
       f90fileio's file administration is updated

=cut

  my ($line,$lineno) = rd_file_line();
  my $idebug = 0;

  # If the line is empty, add an EMPTY_LINE code to the collected comments
  $line = '!!\nEMPTY_LINE\n' if ($line =~ /^\s*$/ and $lineno != 0);

  warn "read_file_line: $lineno:# '$line'\n" if ($idebug > 3);

  if(wantarray) {
    return ($line,$lineno);
  }
  return $line;
}


sub rd_file_line();    # Recursive

sub rd_file_line()
{

   return ('', 0) unless $nfile > 0;
   my $line = <IN>;
   if (defined($line)) {
      chomp($line); $line = ' ' if ($line eq '');
      $line_numbers[$nfile - 1]++;
   }

   while ((!defined $line) and ($nfile > 0)) {
      close_file();
      if ($nfile > 0) {
         $line = <IN>;
         if (defined($line)) {
            chomp($line); $line = ' ' if ($line eq '');
            $line_numbers[$nfile - 1]++;
         }
      }
   }

   return ('', 0) if ($nfile <= 0);

   # Modify leading tabs to spaces
   $line =~ s/^\t/\ \ \ \ \ \ /;

   if (    $follow_includes
       and $line =~ /^ *include *['"](.+)["']/i) {
      open_file($1);
      return rd_file_line();
   }

   while ($line eq '') {
      $line = rd_file_line();
   }

   $line =~ s/[\r\n]//g;
   if (length($line)>$fixed_linelen and $fixed_form) {
      my $cutline = substr($line, 0, $fixed_linelen);

      my $hascomments = ($cutline =~ /!/);
      if ($cutline =~ /^[^\s]/) {
         $hascomments = 1 unless $cutline =~ /^[0-9]/;
      }

      $line = $cutline unless ($hascomments);
   }

   #print $line_numbers[$nfile - 1], '(', $continuation_counter, ')', ' ', $line, "\n";

   return ($line, $line_numbers[$nfile - 1]) if wantarray;
   return $line;
}

#------------------------------------------------------------------------
sub read_line()
{

=head2 ($line, $lineno, $label) = read_line ();

  Reads a line of Fortran 90 doing whatever it takes.  This may involve
  reading multiple lines from the current file, walking into files, etc.

  INCLUDE is parsed at this level.

  Note that the returned string may have various cases (lc isn't called).

=cut

   $continuation_counter = 0;
   my ($line, $label, $justdone, $lineno);

 ALLOVERAGAIN:

   # First, read a line from the file
   # NB: a line from the file may or may not be a (complete) Fortran-line.
   $justdone = 0;

   if ($leftover ne '') {

      # Use left over line fragment if there is one
      $line        = $leftover;
      $lineno      = $leftover_no;
      $leftover    = '';
      $leftover_no = 0;
      $line = code_and_comment($line, $justdone);
      $justdone = 1;
   } else {

      # Read from the input file, until a valid line is found
      ($line, $lineno) = read_file_line;

      # Remove comments from the line and remember the comments
      $line = code_and_comment($line, $justdone);
      $justdone = 1;
   }
   $current_line_start = $lineno;
   $current_line_end   = $lineno;

   # Set the pointers to the current line in the file
   $openfile    = $openfiles[$nfile - 1];
   $orgfilename = $orgfilenames[$nfile - 1];

   # This is used for fixed-form continuations.
   my $lastlen = length $line;

   my $continue = 0;

   # Keep adding continuation lines as long as neccessary
   while (1) {

      # Remove comments from the line and remember the
      # double comments
      $line = code_and_comment($line, $justdone);
      $justdone = 1;

      if ($fixed_form) {

         # Fixed-form continuations.
         # Check next line for continuation mark.
         # Also continue if the next line starts with at least one
         # space character and it only contains a comment and
         # we are already reading end-of-line comments
         ($leftover, $leftover_no) = read_file_line();

         $justdone = 0;
         unless (defined $leftover) {
            $leftover    = '';
            $leftover_no = 0;
         }
         chomp $leftover;
         $leftover =~ s/^[^0-9\s]/!/;
         if ($leftover =~ /^\s....\S/
             || ($comment_is_eoln && $leftover =~ /^\s+!/)) {
            $continuation_counter++;

            # Pad previous line with spaces if it had less than 72 characters.
            $line .= ' ' x (72 - $lastlen) if $lastlen < 72;

            # Add next (continuation) line to the line.
            $line .= substr($leftover, 6);
            $lastlen = length $leftover;
            $current_line_end = $leftover_no;

            # Continue on to check the next line.
            $leftover = '';
            next;
         }
         next if ($leftover =~ /^!/) && may_ignore_comment_line();
      } elsif ($continue || $line =~ /&\s*$/) {
         $continuation_counter++;

         # Free-form continuations.
         $line = $` if $line =~ /&\s*$/;
         my ($rest, $rest_no) = read_file_line();

         $current_line_end = $rest_no;
         $justdone = 0;
         chomp $rest;
         $rest = $' if $rest =~ /^\s*&/;
         $line .= $rest;

         # Blank lines don't stop the continuation.
         $continue = ($rest =~ /^\s*(?:!.*)?$/);
         next;
      } elsif ($comment_is_eoln) {

         # Possible free-form continuation:
         # an end-of-line comment may be continued
         # on the next line

         my $line_indent_depth = 0;
         if ($line =~ /^(\s*)[^\s]/) {
            $line_indent_depth = length $1;
         }
         my ($rest, $rest_no) = read_file_line();

         chomp $rest;
         my $rest_indent_depth = 0;
         if ($rest =~ /^(\s*)[^\s]/) {
            $rest_indent_depth = length $1;
         }

         if ($rest =~ /^\s+!/ and
             $rest_indent_depth > $line_indent_depth)
         {
            # The next 'file-line' has ONLY comments and is indented
            # at least as far as the EOLN-comment of the current line.
            #   ===> this line belongs to the current EOLN-comment
            my $justdone = 0;
            $rest = code_and_comment($rest, $justdone);
            $justdone = 1;
            $current_line_end = $rest_no;
         } else {
            # This line does not belong to the current EOLN-comment.
            #   ===> it must be (the start of) the next line.
            $leftover    = $rest;
            $leftover_no = $rest_no;
            last;
         }
         $line .= $rest;
         next;
      }
      last;
   }

   # Replace strings to avoid confusion.
   my @quotes;
   while ($line =~ / " ([^"]|"")* " | ' ([^']|'')* ' /xg) {
      push @quotes, [length $`, length $&, $&];
   }
   for my $quote (reverse @quotes) {
      ## Process in reverse order so that $start is preserved despite replacement
      my ($start, $length, $string) = @$quote;
      push @strings, $string;
      substr($line, $start, $length) = "\'" . $#strings . "\'";
   }

   # Semicolons.
   if ($line =~ /^([^;]*);(.*)$/) {
      $line = $1;
      if (not $2 =~ /^\s*$/) {
         if ($leftover eq '') {
            $leftover = $2;
         } else {
            $leftover = "$2;$leftover";
         }
      }
   }

   # Get rid of spaces and label numbers at start of line
   $line =~ s/^([ 0-9]*)//;
   $label = $1;
   $label =~ s/^\ +//;
   $label =~ s/([0-9]+).*/$1/;

   # Get rid of spaces on either end.
   $line = trim($line);
   goto ALLOVERAGAIN if ((!$line) and $nfile > 0);

   # Remove spaces halfway in numbers, because the parser doesn't
   # approve of them (expr_parse)
   $line =~ s/([0-9])  *([0-9])/$1$2/g if $line;

   if (0) {print "$lineno ($comments_started_at) # $line\n"};

   $current_line_start = $lineno;
   return ($line, $lineno, $label);
}

sub fixed_fortran() {return $fixed_form;}

sub guessed_format($) {

=head2 $fformat = guessed_format($file)

  Guess the kind of fortran format used in a file.

  OUTPUT VARIABLES
    $file - name of the file to check

  OUTPUT VARIABLES
    $fformat - fortran file format:
               'free'       free format
               'fixed'      fixed file format
               'nofile'     file could not be opened/read

=cut

# f90 and f95 allow both fixed and free source form.
# Assume fixed source form unless signs of free source form
# are detected in the first five columns of the first b:lmax lines.
# Detection becomes more accurate and time-consuming if more lines
# are checked. Increase the limit below if you keep lots of comments at
# the very top of each file and you have a fast computer.

# This test was taken from the file fortran.vim - syntax highlighting for (g)vim

  my $file = shift;

  my $lmax = 250;
  open FILE, "<$file" or return 'nofile';

  my $iline=0;
  my $free_line = ''; my $ifree;
  my $prev_line = '';
  while ($iline<=$lmax and my $line = <FILE>) {
    $iline++;
 
    # If the fixed-form margin (first 5 letters, unless there is a tab, which 
    # counts as many spaces) is not comment, but still has something
    # else than numbers or whitespace, then this must be free-form
    my $test = substr($line,0,5);
    if ( not $test =~ /^[Cc*!#]/ and not $test =~ /^\s+[!#]/ 
         and $test =~ /[^0-9\s]/ and not $test =~ /^\s*\t/) {
       $free_line = $line;
       $ifree = $iline;
       last;
    }

    # If the line ends with a '&' before the end of the fixed-line, this must be free-form
    if ($line =~ /^(.*)\&\s$/) {
       if (length($1)<$fixed_linelen) {
           $free_line = $line;
           $ifree = $iline;
           last;
       }
    }

    # if previous line ended with a '&', but this one does not have a non-whitespace
    # in the fixed-form continuation column, then this must be free-form
    if ($prev_line =~ /\&\s*$/ and not $line =~ /     [^s]/) {
       $free_line = $line;
       $ifree = $iline;
       last;
    } 
  }

  return ('free', $ifree, $free_line) if ($ifree);
  return ('fixed','','');
}




1;
