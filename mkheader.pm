# Copyright (C) 2009-2010  Planbureau voor de Leefomgeving (PBL)
#
# full notice can be found in LICENSE

package mkheader;

=head1 PACKAGE mkheader

 This package contains functions to generate header output files.

=head1 CONTAINBREAKS

=cut

require 5.003;
use strict;
use warnings;

use File::Path('mkpath');
use f90fileio('fixed_fortran');
use htmling('attriblist', 'split_use');
use typing('type_to_f90');
use utils('my_die','remove_files');
use stmts('print_stmt');

use vars ('$VERSION', '@EXPORT_OK', '@ISA');
$VERSION = '1.0';
@ISA     = ('Exporter');

our @EXPORT_OK = ('toplevel2header', 'delayed_write', 'set_headeroption',
                  'clear_mkheader_path');

# Header styles:
#    0 - no header
#    1 - default headers
our $headerstyle = 0;

# Split source files into program units?
our $do_split = 0;

# Header output directory
our $output_path = 'header';

# Force usage of kind or *
our $force_kind = 0;
our $force_star = 0;

# Force reserved words to upper case
our $force_upper = 0;

# Force variable declaration comments to the end of the line
# Instead of the start of a new line
our $var_eol_cmt = 0;

# Attempt to align variable declarations vertically
our $valign = 0;

# Reduce the number of times the word "dimension" occurs
our $less_dim = 0;

# Suppress the generation of double exclamation marks
our $no_dblmarks = 0;

# Do not indent modules
our $no_modindent = 0;

# Handy constants
my $SF    = '(?:subroutine|function)';
my $SFMP  = '(?:subroutine|function|module|program|block\s*data)';
my $SFMPI = '(?:subroutine|function|module|program|block\s*data|interface)';

# Line lengths for word wrap
my $MAXLEN_FIXED = 65;
my $MAXLEN_FREE  = 132;
my $MAXLEN_FRCMT = 90;    # Maximum length of comment lines in free format
my $MINLEN       = 32;    # Minimum wrap margin
my $MAXSPC       = 40;    # Maximum number of leading spaces

# Positions for vertical alignment
my $ALIGN_INTENT = 12;
my $ALIGN_COLON  = 50;
my $ALIGN_ASSIGN = 65;
my $ALIGN_BANG   = 80;

# Fixed format comment character
my $CMTCHAR = '!';

# Fixed format continuation character
my $CNTCHAR = '&';

# Continuation indentation depth
my $CINDENT = 2;

# Normal indentation depth
my $DINDENT = 3;

# Current normal indentation level
my $nindent = 0;

# Is last line printed an empty line?
my $lastline_was_empty = 0;

# Temporary storage of top-level data
# so they can all be written together
my @topstore = ();

#-----------------------------------------------------------------------------

sub clear_mkheader_path() { remove_files($output_path); }

sub set_headeroption($;$){
   my $option = shift;
   if (not @_)  {
      if    ($option =~ 'do_split'     ) { $do_split     = 1;}
      elsif ($option =~ 'headerstyle'  ) { $headerstyle  = 1;}
      elsif ($option =~ 'force_kind'   ) { $force_kind   = 1;}
      elsif ($option =~ 'force_star'   ) { $force_star   = 1;}
      elsif ($option =~ 'var_eol_cmt'  ) { $var_eol_cmt  = 1;}
      elsif ($option =~ 'force_upper'  ) { $force_upper  = 1;}
      elsif ($option =~ 'valign'       ) { $valign       = 1;}
      elsif ($option =~ 'less_dim'     ) { $less_dim     = 1;}
      elsif ($option =~ 'no_dblmarks'  ) { $no_dblmarks  = 1;}
      elsif ($option =~ 'no_modindent' ) { $no_modindent = 1;}
      else          {my_die("unknown option '$option'"); die;}
      my_die("Cannot force both * and kind formats")
                  if $force_kind && $force_star;
   } else {
      if ($option =~ 'output_path' ) {
         $output_path = shift;
      }
      else           {my_die("unknown option '$option'"); die;}
   }
}


sub writetext($;$$)
{

=head2

  writetext(@lines; $flags, $label) or
  writetext($lines; $flags, $label)

  Write text to the output file

  INPUT VARIABLES
     $lines : text to write

     $flags : struct with options set (1) or unset (0):
                  begin_empty_line : print newline at start of this function
                  end_empty_line   : print newline at end of this function
                  to_description   : text is part of the 'description' of an item
                                     (comment that goes into HTML)
                  guessed          : comments were guessed (marked as such in the
                                     code or taken from dictionary)
                  no_wrap          : disallow wrapping (breaking line up)
                  no_force_upper   : do not override the force_upper setting
                  first_commentline:

     $label : label (if any)

=cut

   my $lines = shift;
   my $flags = shift;
   my $label = shift;
   $flags = {} unless $flags;

   my @lines = ();
   if (ref $lines ) {
      @lines = @$lines;
   } else {
      foreach my $line (split('\n',$lines)) {
         push(@lines,{
               line           => $line,
               guessed        => $flags->{guessed},
               to_description => $flags->{to_description},
             } );
      }
   }

   my $done_white = 0; # Flag if whitespace at beginning of line is handled
                       # already.

   #Add empty line if requested
   if ($flags->{begin_empty_line} and not $lastline_was_empty) {
      print OUT "\n";
      $lastline_was_empty = 1;
   }

   # DeHTML-ize text
   foreach my $line (@lines) {
      $line->{line} =~ s/<br>/\n/ig;
      $line->{line} =~ s/<[^\/]p[\/]?>/\n/ig;
      $line->{line} =~ s/<[\/]?(\w+)[\/]?>//ig;
   }

   # If the text is empty - add an empty line
   push(@lines,{
               line           => '',
               guessed     => $flags->{guessed},
               to_description => $flags->{to_description},
               is_comment     => $flags->{is_comment},
             } ) if (not @lines);

   # Determine how many leading spaces to remove from each line
   # The number of spaces removed is the minimum number of
   # leading spaces in the given $text block.
   my $leadingspaces = -1;
   foreach my $line (@lines) {
      next if ($line->{line} =~ /\\nEMPTY_LINE\\n/);
      if ($line->{line} =~ /^(\s*)[^\s]/) {
         my $pos = length($1);    # Number of leading spaces on this line
         $leadingspaces = $pos
            if ($leadingspaces < 0 or $leadingspaces > $pos);
      }
   }
   $leadingspaces = 0       if $leadingspaces < 0;
   $leadingspaces = $MAXSPC if $leadingspaces > $MAXSPC;

   # remove the leading spaces: they will be replaced afterward
   foreach my $line (@lines) {
      next if ($line->{line} =~ /\\nEMPTY_LINE\\n/);
      if (length($line->{line}) >= $leadingspaces) {
         $line->{line} = substr($line->{line},$leadingspaces);
      }
   }
   $leadingspaces = ' ' x $leadingspaces;

   # Calculate wrap margin
   my $wraplen;
   if ( fixed_fortran()) {
      $wraplen = $MAXLEN_FIXED;
   } elsif ($flags->{to_description}) {
      $wraplen = $MAXLEN_FRCMT - 3;
   } else {
      $wraplen = $MAXLEN_FREE;
   }
   $wraplen-- if (not fixed_fortran());
   $wraplen -= $nindent * $DINDENT;
   $wraplen = $MINLEN if $wraplen < $MINLEN;

   # Split lines that are too long
   # Copy result into @lineinfo
   my @lineinfo;
   foreach my $line (@lines) {
      my $l            = $line->{line};
      my $continuation = 0;

      $l =~ s/\s+$//;

      # If this line is a comment line without any letters or digits,
      # just cut it
      if (   $flags->{is_comment} and length($l) >= $wraplen and $l !~ /\w/) {
         $l = substr($l, 0, $wraplen - 1);
      }

      # Do the actual splitting
      while ( not $flags->{no_wrap} and
              ( ($continuation     and length($l) >= $wraplen - $CINDENT) or
                (not $continuation and length($l) >= $wraplen) ) ) {

         # Calculate a good wrap position
         my $pos = rindex($l, ')', $wraplen);
         $pos = rindex($l, ',', $wraplen) if $pos < $MINLEN;
         $pos = rindex($l, ' ', $wraplen) if $pos < $MINLEN;
         $pos = $wraplen - 1 if $pos < $MINLEN;

         # Don't split in a string
         # (not fail-proof method to determine whether we are in a string)
         # (this will work in most situations, though...)
         my $in_string  = 0;
         my $last_quote = -1;
         for (my $i = 0 ; $i < $pos ; $i++)
         {
            my $c = substr($l, $i, 1);
            if ($c eq "'" || $c eq '"')
            {
               $last_quote = $i;
               $in_string  = !$in_string;
            }
         }
         $pos = $last_quote - 1 if $in_string && ($last_quote > $MINLEN);

         # Split the actual line
         my $left = substr($l, 0, $pos + 1);
         $left =~ s/\s+$//;
         my $right = substr($l, $pos + 1, length($l));
         $right =~ s/^\s+//;
         my $continued = ($right ne '');

         # Store the left part; continue with the right part
         # If the right part is empty, don't continue after all
         my %newline = %$line;
         $newline{line}         = $left;
         $newline{continued}    = $continued;
         $newline{continuation} = $continuation;
         push(@lineinfo, \%newline);

         $continuation = 1;
         $l = $leadingspaces . (' ' x $CINDENT) . $right;
      }

      # Store short line or the last part of a wrapped line
      my %newline = %$line;
      $newline{line}         = $l;
      $newline{continued}    = 0;
      $newline{continuation} = $continuation;
      push(@lineinfo, \%newline);
   }

   # Handle each line
   my $first_commentline = $flags->{first_commentline};
   foreach my $line (@lineinfo) {
      my $l = $line->{line};
      $l =~ s/\s+$//;

      next unless ($l or $flags->{is_comment});

      # Print the actual line
      my $indent = ' ' x ($nindent * $DINDENT);
      my $printline = '';
      if ($l =~ m/EMPTY_LINE/) {
         $printline = "\n";
      } elsif (fixed_fortran()) {
         # Fixed format
         if ($label) {
            my $len = length($label);
            if ($len < 5) {
               $printline .= " $label" . ' ' x (5 - $len);
            } else {
               $printline .= "$label ";
            }
         } elsif ($flags->{is_comment}) {

            # Determine how many comments characters should be added in front
            # of the comment.

            $printline .= $CMTCHAR;

            if ($line->{to_description} and not $no_dblmarks) {
               $printline .= $CMTCHAR;
            } else {
               $printline .= ' ' if ($l);
            }

            if ($line->{guessed}) {
               $printline .= '?'
            } else {
               $printline .= ' ' if ($l);
            }

            $printline .= '   ' if ($l);
         } elsif ($line->{continuation}) {
            $printline .= ' ' x 5 . $CNTCHAR;
         } else {
            $printline .= ' ' x 6;
         }
         $printline .= $indent if $l;
         $l = uc($l)
           if ($force_upper and $l and not $flags->{no_force_upper} and
               not $flags->{is_comment});
         $printline .= "$l\n";

      } else {
         # Free format
         $printline .= $indent if ($flags->{is_comment} or $l);
         $printline .= "$label " if $label;
         if ($flags->{is_comment}) {
            $printline .= '!';
            $printline .= '!' if ($line->{to_description} and not $no_dblmarks);
            $printline .= '?' if $line->{guessed};
            $printline .= ' ' unless $l =~ m/^\s+/;
         };

         $l = uc($l) if $force_upper and $l and
                 not $flags->{no_force_upper} and not $flags->{is_comment};
         $printline .= $l;
         $printline .= ' &' if ($line->{continued} and not $flags->{is_comment});
         $printline .= "\n";

      }

      # Remove the dimension statement in some cases and move the dimension to
      # the end
      if ($less_dim and $l and $l !~ /\,\s*(?:pointer|allocatable)/i) {
         $printline =~ s/(.+)\,\s*dimension\s*(\(.+\))(.*)::(\s*)(\S+)(\s+)(.*)/$1$3::$4$5$2$6$7/i;
      }

      # Try to vertically align variable declarations if requested
      if ($valign and $l and  not $flags->{is_comment}) {
         # Try to align INTENT
         my $pos = 1 + index($printline, 'INTENT');
         if ($pos > 0 and $pos < $ALIGN_INTENT) {
            my $missing = ' ' x ($ALIGN_INTENT - $pos);
            $printline =~ s/INTENT/${missing}INTENT/;
         }

         # Try to align intent
         $pos = 1 + index($printline, 'intent');
         if ($pos > 0 and $pos < $ALIGN_INTENT) {
            my $missing = ' ' x ($ALIGN_INTENT - $pos);
            $printline =~ s/intent/${missing}intent/;
         }

         # Try to align non stand-alone PARAMETER
         $pos = 1 + index($printline, 'PARAMETER');
         if ($pos > 0 and $pos < $ALIGN_INTENT
                      and $printline =~ /\,\s*PARAMETER/) {
            my $missing = ' ' x ($ALIGN_INTENT - $pos);
            $printline =~ s/PARAMETER/${missing}PARAMETER/;
         }

         # Try to align non stand-alone parameter
         $pos = 1 + index($printline, 'parameter');
         if ($pos > 0 and
             $pos < $ALIGN_INTENT && $printline =~ /\,\s*parameter/) {
            my $missing = ' ' x ($ALIGN_INTENT - $pos);
            $printline =~ s/parameter/${missing}parameter/;
         }

         # Try to align ::
         $pos = 1 + index($printline, '::', $pos);
         if ($pos > 0 and $pos < $ALIGN_COLON) {
            my $missing = ' ' x ($ALIGN_COLON - $pos);
            $printline =~ s/\:\:/$missing\:\:/;
         }

         # In case of a parameter, try to align the assignment operator
         # Unless it's a stand-alone parameter statement
         $pos = 1 + index($printline, '=', $pos);
         if ($pos > 0 and $pos < $ALIGN_ASSIGN
                      and ($printline =~ /\,\s*parameter/i)) {
            my $missing = ' ' x ($ALIGN_ASSIGN - $pos);
            $printline =~ s/\=/${missing}\=/;
         }

         # If after alignment (except for end-of-line comments),
         # the actual line is too long for fixed format,
         # try to fix it by replacing multiple spaces with a single space
         if (fixed_fortran()) {
            my $shortline = $printline;
            $shortline =~ s/\!\!.*//;
            $shortline =~ s/\s*$//;
            my $linelen = length($shortline);
            $printline =~ s/(\S)\s{2,}(\S)/$1\ $2/g if ($linelen > 72);
         }

         # Try to align !!
         if ($no_dblmarks) { $pos = 1 + index($printline, '!' , $pos); }
         else              { $pos = 1 + index($printline, '!!', $pos); }
         if ($pos > 0 and $pos < $ALIGN_BANG) {
            my $missing = ' ' x ($ALIGN_BANG - $pos);
            if ($no_dblmarks) { $printline =~ s/\!/$missing\!/;     }
            else              { $printline =~ s/\!\!/$missing\!\!/; }
         }
      }

      print OUT $printline
         unless ($first_commentline and $l eq '\nEMPTY_LINE\n');
      $lastline_was_empty = ($l =~ /^\s*$/);
      $first_commentline = 0;
   }

   # Add empty line if requested
   if ($flags->{end_empty_line}) {
      print OUT "\n";
      $lastline_was_empty = 1;
   }
}

#-----------------------------------------------------------------------------

sub build_declaration($)
{

=head2 $decl = build_declaration($top)

  Return a declaration line for the given item $top

  INPUT VARIABLES
     $top   : struct-pointer with all info about the object
              see toplevel2header()
  RETURN VALUES
     #decl  : declaration line

=cut

   my $top  = shift;
   my $decl = '';

   # Attributes that come before the type
   $decl .= ($decl ? ' ' : '') . typing::type_to_f90($top->{rtype})
     if $top->{rtype};
   foreach my $flag ('recursive', 'elemental', 'pure') {
      $decl .= ($decl ? ' ' : '') . $flag if $top->{$flag};
   }

   # Type
   my $type  = $top->{type};
   my $ttype = $type;
   $ttype = typing::type_to_f90($top->{'vartype'}) if $type eq 'var';
   $ttype = 'module procedure' if $type eq 'mprocedure';
   $decl .= ($decl ? ' ' : '') . $ttype;

   # Additional attributes
   my $long_type = 0;    # Whether we want TYPE name (short) or TYPE, PUBLIC :: name (not short)
   if ($type !~ /$SFMPI/) {
      my $attr = join(', ', attriblist($top));
      $long_type = (lc($attr) ne 'public') if $type eq 'type';
      $decl .= lc(($decl ? ', ' : '') . $attr)
           if $attr and ($type ne 'type' or $long_type);
   }

   # Force upper if requested, but not the type in a type declaration
   if ($force_upper)
   {
      my @storage;
      while ($decl =~ s/type\s*\(([\w\s]+)\)/type\(\)/i) {
         push @storage, $1;
      }
      $decl = uc($decl);
      foreach my $stored (@storage) {
         $decl =~ s/TYPE\(\)/TYPE\ \($stored\)/;
      }
   }

   # Double colon and name
   my $name = $top->{displayname} ? $top->{displayname} : $top->{name};
   $decl .= ' ::' if $type eq 'var' || $long_type;
   $decl .= " $name";

   if ($type eq 'var') {
      # Initialization (if any)
      $decl .= " $top->{initop} " . typing::expr_to_f90($top->{initial})
        if $top->{initop} && $top->{initial};
   } elsif ($type =~ /$SF/) {

      # Arguments and return value
      $decl .= '(' . join(", ", @{$top->{'parms'}}) . ")";
      $decl .= " result ($top->{result})"
        if $top->{result} && !$top->{rtype};
   }

   $decl .= "\n";

   # In declarations with character and parameter,
   # move the parameter statement to the next line
   if ($decl =~ /character(.+)\,\s*parameter(.*)::(\s*)(.+)\s*=\s*(.+)/i) {
      if ($force_upper) {
         $decl = "CHARACTER$1$2::$3$4\nPARAMETER            ($4 = $5)\n";
      } else {
         $decl = "character$1$2::$3$4\nparameter            ($4 = $5)\n";
      }
   }

   return $decl;
}

#-----------------------------------------------------------------------------

sub do_header($;$)
{

=head2 do_header($top, $parent)

  Print a header for the given item

  INPUT VARIABLES
     $top    : struct-pointer with all info about the object
               see toplevel2header()
     $parent : parent of $top (if any)

=cut

   my $top    = shift;
   my $parent = shift;

   # Ignore function return values if they are already declared at the function
   return
     if $top->{retval}
        && $parent->{type}  eq 'function'
        && $parent->{rtype} eq $top->{vartype};

   # Handle 'contains' Contains is inserted as soon as the first subroutine or
   # function is encountered inside a module, subroutine, function or program
   if (   $parent  && $parent->{type} =~ /$SFMP/
                   && $top->{type}    =~ /$SF/
                   && !$parent->{contains_done})
   {
      $parent->{contains_done} = 1;
      writetext('contains', { begin_empty_line=>1,  end_empty_line=>1});
   }


   # Determine whether the description should be placed at end-of-line:
   #   this is for variable declarations when the associated comments are
   #   forced to be end-of-line comments
   my $description_to_eoln = ($var_eol_cmt and $top->{type} eq 'var');

   # Determine whether comments which were at end-of-line originally
   # should be placed at end-of-line again
   my $eoln_to_eoln        = ($top->{type} ne 'var');

   # Prepare declaration and comments
   my $decl = build_declaration($top);

   # For every line of comments, we decide whether we'll print it before the
   # statement, at end-of-line, or after the statement.
   my @befores= ([],[],[]);
   my @eolns  = ();
   my @afters = ();
   my $eoln_guessed     = 0;
   my $eoln_description = 0;
   my $eolns_found =0;
   foreach my $line (@{$top->{collected_comments}}) {

      if ($line->{after_the_line}) {
         # If the line was after the statement originally, we put it there again
         push(@afters,$line);
      } elsif ( ($line->{comment_is_eoln} and $eoln_to_eoln)    or
                ($line->{to_description}  and $description_to_eoln) ) {
         # If the line was at eoln and end-of-line comments should go there, OR
         #    the line is part of the description and descriptions should
         #    come at eoln,
         # the comment goes to end-of-line
         my $text = $line->{line};
         $text =~ s/[^!]*![!?]*\s*//;
         push(@eolns,$text);
         $eoln_guessed     = $line->{guessed};
         $eoln_description = $line->{to_description};
      } elsif ($line->{comment_is_eoln}) {
         # If comment is end-of-line, we place the comments before the
         # statement
         push(@{$befores[1]},$line)
            unless (@{$befores[1]}==0 and $line->{line} =~ /\\nEMPTY_LINE\\n/);
      } else {
         # In other cases, we place the comments before the statement
         if (@{$befores[0]}>0 or $line->{line} !~ /\\nEMPTY_LINE\\n/) {
            if ($line->{to_description} or not $line->{printed}) {
               push(@{$befores[0]},$line);
               $line->{printed} = 1;
            }
         }
      }
      $eolns_found = 1 if ($line->{comment_is_eoln});
   }

   # If a description was found in the dictionary, we add this to the
   # end-of-line stuff, or to the before-stuff (depending on user settings)
   if ( $top->{description}->{from_dictionary} or
        $top->{description}->{non_fordocu}
      ) {
      if ($description_to_eoln) {
         push(@eolns,$top->{description}->{line});
         $eoln_guessed     = 1;
         $eoln_description = 1;
      } else {
         my @lines = split('\n',$top->{description}->{line});
         while (@lines and $lines[0] =~ /^\s*$/) {shift(@lines);};
         foreach my $text (@lines) {
            push(@{$befores[2]},{ line => $text,
                            guessed => $top->{description}->{guessed},
                            to_description => 1
                          });
         }
      }
   }

   # Add eol-comments to the declaration line
   if (@eolns) {
      my $comments = join(' ',@eolns);

      # Combine all the explanation of the variable to one line
      $comments =~ s/!+$//;
      $comments =~ s/\n/\ /g;
      $comments =~ s/\ \ +/\ /g;

      # Add comments to the declaration line
      $decl =~ s/\n+$//;
      if ($eoln_description and not $no_dblmarks) {
         $decl .= ' !!';
      } else {
         $decl .= ' !';
      }

      if ($eoln_guessed) {
         $decl .= '? ';
      } else {
         $decl .= ' ';
      }

      $decl .= $comments;
   }

   # Print the comment lines before the statement
   my $neednewline =0;
   foreach my $before (@befores) {
      next if (@$before == 0);

      foreach my $comment (@$before) {
        chomp($comment->{line});
        $comment->{line} =~ s/^!//;
        $comment->{line} .= ' ';
        $comment->{line} =~ s/^\s*!([^!])/$1/;
        $comment->{line} =~ s/^\s*!!([^!])/$1/;
        $comment->{line} =~ s/^\s*[!\*c]\s//;
        $comment->{line} =~ s/^\s*[!\*c][!\*c]\s//;
      }

      $lastline_was_empty = 0;
      writetext( $before, { begin_empty_line => $neednewline, end_empty_line => 0,
                            no_wrap    => 1,  is_comment=>1
                          } );
      $neednewline = 1;
   }

   # Print the statement and the end-of-line comments
   writetext($decl,{no_force_upper =>1, no_wrap=>$description_to_eoln} ,
                    $top->{label});

   # Print the comment lines after the statement
   foreach my $comment (@afters) {
     chomp($comment->{line});
     $comment->{line} =~ s/^!//;
     $comment->{line} .= ' ';
     $comment->{line} =~ s/^\s*!([^!])/$1/;
     $comment->{line} =~ s/^\s*!!([^!])/$1/;
     $comment->{line} =~ s/^\s*[!\*c]\s//;
     $comment->{line} =~ s/^\s*[!\*c][!\*c]\s//;
   }
   writetext( \@afters, { begin_empty_line => 0, end_empty_line => 0,
                         no_wrap    => 1,   is_comment=>1}) if (@afters);

   # Print pseudocode (if any)
   if ($top->{pseudocode}) {
      writetext('', {is_comment=>1}) if $top->{comments};
      writetext('PSEUDOCODE:',
              { is_comment => 1, no_wrap =>1,
                begin_empty_line => $top->{description}->{line},
                end_empty_line => 1});
      writetext($top->{pseudocode}, {is_comment=>1});
   }
}

#-----------------------------------------------------------------------------

sub do_footer($)
{

=head2 do_footer($top)

  Print a footer for the given item.

  INPUT VARIABLES
     $top   : struct-pointer with all info about the object
              see toplevel2header()

=cut

   my $top = shift;

   my $type = $top->{type};

   # Some items do not close
   return if $type !~ /(?:module|subroutine|function|program|block\s*data|type|interface)/;

   my $name = $top->{displayname} ? $top->{displayname} : $top->{name};
   my $decl = "end $type ";
   $decl = uc($decl) if $force_upper;
   $decl .= $name;
   writetext("$decl", {no_force_upper =>1, end_empty_line=>1}, $top->{label_end});

   #   warn "LABEL END '$top->{label_end}' PRINTED IN LINE '$decl'\n" if $top->{label_end};
}

#-----------------------------------------------------------------------------

sub do_uses($)
{

=head2 do_uses($top)

  Print use statements

  INPUT VARIABLES
     $top : struct pointer with information about the object

=cut

   my $top = shift;

   foreach my $use (@{$top->{uses}}) {
      my ($module, $only) = split_use($use);
      my $line = "use $module";
      $line .=  ", $only" if  ($only);
      if ($force_upper) {
         $line =~ s/^use/USE/;
         $line =~ s/,\ only/,\ ONLY/;
      }
      writetext($line, {no_force_upper=>1});
   }
}

#-----------------------------------------------------------------------------

sub do_include($$)
{

=head2 do_include($top, $parent)

  Handle include statements

  INPUT VARIABLES
     $top    : struct pointer with information about the object
     $parent : parent of $top

=cut

   my $top    = shift;
   my $parent = shift;

   # Check whether the file was already included
   my $fname = $top->{filename};
   return if $parent->{includone} && $parent->{includone}->{$fname};
   $parent->{includone}->{$fname} = 1;

   my @stmts;
   foreach my $stmt (@{$parent->{ocontains}}) {
     push(@stmts, $stmt)
        if ($stmt->{filename} and ($stmt->{filename} eq $fname)
            and exists($stmt->{ilines}) and @{$stmt->{ilines}});
   }

   if (@stmts) {
      my $lines = "used from include file '$fname':";

      foreach my $stmt (@stmts) {
        if ($stmt->{type} eq "var") {
           $lines .= "\n  $stmt->{vartype}->{base} $stmt->{name}";
        } else {
           $lines .= "\n  $stmt->{type} $stmt->{name}";
        }
      }
      writetext($lines, {is_comment=>1, begin_empty_line=>1});
   }

   $fname = $top->{orgfilename} if $top->{orgfilename};
   writetext("include '$fname'", {end_empty_line=>1});
}

#-----------------------------------------------------------------------------

sub do_body($)
{

=head2 do_body($top)

  Copy body lines

  INPUT VARIABLES
     $top    : struct pointer with information about the object

=cut

   my $top = shift;

   # Print all data statements (if any)
   if ($top->{data}) {
      # Add an empty line
      print OUT "\n" unless $lastline_was_empty;
      $lastline_was_empty = 1;

      writetext('Initialization', {is_comment=>1});

      foreach my $data (@{$top->{data}}) {
         # Print the comment lines before the statement
         foreach my $comment (@{$data->{collected_comments}}) {
           chomp($comment->{line});
           $comment->{line} =~ s/^!//;
           $comment->{line} =~ s/^\s*[!\*c]+\s//;
           $comment->{line} =~ s/^\s*[!\*c]+\s*$//;
         }
         writetext( $data->{collected_comments},
                    { begin_empty_line => 0, end_empty_line => 0,
                      no_wrap    => 1,   is_comment=>1})
              if (@{$data->{collected_comments}});

         # Print the statement
         writetext("data $data->{contents}");
      }

      # Add an empty line
      print OUT "\n";
      $lastline_was_empty = 1;
   }

   # If no body to copy was specified, return
   return unless $top->{bodystart} && $top->{bodyend};

   #print "$top->{name} van $top->{bodystart} tot en met $top->{bodyend}\n";

   # Add an empty line
   print OUT "\n" unless $lastline_was_empty;
   $lastline_was_empty = 1;

   # Open source file
   open SOURCE, "<$top->{filename}"
     or my_die("Cannot open file '$top->{filename}' for reading");

   # Ignore lines before the body starts
   foreach my $i (1 .. $top->{bodystart} - 1) { my $dum = <SOURCE>; }

   # Make a literal copy of the source lines
   # not through writetext()
   foreach my $i ($top->{bodystart} .. $top->{bodyend}) {
      my $line = <SOURCE>;

      # If you get a warning here about Use of uninitialized value,
      # this is probably due to the value of $top->{bodyend}

      # Replace leading tabs with 6 spaces
      $line =~ s/^\t/\ \ \ \ \ \ /;

      # Replace trailing spaces and ^M with a single \n
      $line =~ s/\s*$/\n/;

      # Some fixed format fixes
      if (fixed_fortran()) {
         # Replace comment character with $CMTCHAR
         $line =~ s/^[^0-9\s]/$CMTCHAR/i;

         # Replace continuation character with $CNTCHAR
         $line =~ s/^\s\s\s\s\s[^\s]/\ \ \ \ \ $CNTCHAR/i;
      }

      # Remove and avoid double empty lines
      next if $lastline_was_empty && $line eq "\n";
      $lastline_was_empty = !$line;

      # Write the line
      print OUT $line;
   }
   close SOURCE;

   # Add an empty line
   print OUT "\n" unless $lastline_was_empty;
   $lastline_was_empty = 1;
}

#-----------------------------------------------------------------------------

sub do_contains($$)
{

=head2 do_contains($top,$place)

  Handle the items contained by $top that come
  either before or after the body.

  INPUT VARIABLES
     $top    : struct-pointer with all info about the object
              see toplevel2header()
     $place  : indicates whether 'before' or 'after' the body

=cut

   my $top   = shift;
   my $place = shift;

   foreach my $item (@{$top->{ocontains}}) {
      my $isSF = ($item->{type} =~ /$SF/);
      next
        unless ($place eq 'before' && !$isSF)
        || ($place eq 'after' && $isSF);

      if (   $item->{filename}
          && $top->{filename}
          && $top->{filename} ne $item->{filename}) {
         # Included items get special handling
         do_include($item, $top);
         next;
      }

      do_level($item, $top)
         unless ($item->{type} eq "implicit none" or
                 $item->{type} eq "use" or
                 $item->{type} eq "dimension");
   }
}

#-----------------------------------------------------------------------------

sub do_contained_scope($$)
{

=head2 do_contained_scope($top,$vis)

  List all contained subroutines and functions and their scope

  INPUT VARIABLES
     $top : struct-pointer with all info about the object
     $vis : scope to list 'public' or 'private'

=cut

   my $top = shift;
   my $vis = shift;

   # Collect all subroutines and functions with the given scope
   my @to_print;
   foreach my $item (@{$top->{ocontains}}) {
      push @to_print, $item
        if ( $item->{vis}  and ($item->{vis}  =~ /$vis/i) and
             ($item->{type} =~ /$SF/i) );
   }
   return unless @to_print;

   my $scope = $vis;
   substr($scope, 0, 1) = 'P';
   writetext("$scope subroutines and functions",
             {is_comment=> 1, begin_empty_line=>1});

   $scope = $force_upper ? uc($vis) : $vis;
   foreach my $item (@to_print) {
      my $name;
      if (defined $item->{displayname}) {
         $name = $item->{displayname}
      } else {
         $name = $item->{name}
      }
#      my $name = $item->{displayname} ? $item->{displayname} : $item->{name};
      writetext("$scope $name", {no_force_upper=>1});
   }
}

#-----------------------------------------------------------------------------

sub do_level($;$)
{

=head2 do_level($top,$parent)

  Recursively handle a level in the tree

  INPUT VARIABLES
     $top   : struct-pointer with all info about the object
              see toplevel2header()
     $parent: parent of $top (if any)

=cut

   my $top    = shift;
   my $parent = shift;

   # Extract type
   my $type = $top->{type};

   # Fixed format subroutines, functions, programs and modules get special
   # handling:
   #    in that case there is no indentation
   my $special = ( (fixed_fortran() or $no_modindent) and ($type =~ /$SFMP/) );

   # Write header
   do_header($top, $parent);
   $nindent++ unless $special;

   # Write uses, implicit none etc.
   do_uses($top) if $top->{uses};
   writetext('implicit none', {end_empty_line=>1})
     if $type =~ /$SFMP/;

   # Write private/sequence (types/interfaces)
   writetext('private')  if $top->{privatetype};
   writetext('sequence') if $top->{sequencetype};

   # Write all public and private procedure declarations
   do_contained_scope($top, 'public');
   do_contained_scope($top, 'private');

   # Write contained objects that come BEFORE the body
   $top->{contains_done} = 0;
   do_contains($top, 'before');

   # Write source body
   do_body($top);

   # Write contained objects that come AFTER the body
   do_contains($top, 'after');

   # Write footer
   $nindent-- unless $special;
   do_footer($top);
}

#-----------------------------------------------------------------------------

sub do_file($$$)
{

=head2 do_file($top,$action,$fname)

  Do the actual writing of the item specified in $top

  INPUT VARIABLES
     $top    : struct-pointer with all info about the object
     $action : either '>' or '>>'
     $fname  : file name

=cut

   my $top    = shift;
   my $action = shift;
   my $fname  = shift;

   # Prepare output directory
   if ($output_path) {
      # Add output directory to the filename
      $output_path =~ s/([^\\\/])$/$1\//;
      $fname = $output_path . $fname;
   }

   # Ensure the output directory exists
   my $odir = $fname;
   $odir =~ s/[\\\/][^\\\/]+$//;
   if ($odir && !-w $odir) {
      my @path = split /[\\\/]/, $odir;
      my $cpath = '';
      foreach my $dir (@path) {
         $cpath .= ($cpath ? '/' : '') . $dir;
         mkpath($cpath) unless ($cpath =~ /:$/) || (-w $cpath);
      }
   }

   # Open output file
   open OUT, "$action$fname"
       or my_die("Cannot open file '$fname' for writing");

   # Recurse through the tree
   do_level($top);

   # Close output file
   close OUT;
}

#-----------------------------------------------------------------------------

sub delayed_write()
{

=head2 delayed_write()

  If there are items stored in @topstore, write them to a single file.
  Then, clear @topstore. This function might fail if the top-level objects
  in @topstore have different filenames stored.

=cut

   return unless @topstore;
   return unless $headerstyle;
   return if     $do_split;

   # Initialize module-level variables
   $nindent            = 0;
   $lastline_was_empty = 1;    # Don't start file with empty line

   # Write
   my $append = 0;
   foreach my $top (@topstore) {
      # Choose a name for the output file if not given
      my $outfile = $top->{filename};

      # Adds .new. file extension: $outfile =~ s/\.(\w+)$/\.new\.$1/;

      do_file($top, ($append ? '>>' : '>'), $outfile);
      $append = 1;
   }

   # Clear storage
   @topstore = ();
}

#-----------------------------------------------------------------------------

sub toplevel2header($)
{

=head2 toplevel2header($top)

  This is the main calling point from fordocu.
  Takes a top-level objects: program, subroutine, function or module.
  Warns if given something else.

  If the split option is given, write immediately.
  Otherwise, store the data for later processing by delayed_write().

  INPUT VARIABLES
     $top   : struct-pointer with all info about the top-level object
              fields:
              type     -  'program', 'subroutine', 'function' or
                            'module'.
              name     -  name of the object
              uses     -  array of used modules
              calls    -  struct pointer to called subroutines
              ocontains-  struct-array containing types, variables
                            etc in the object
              comments -  comments in the Fortran code
              filename -  source file name

=cut

   return unless $headerstyle;

   my $top = shift;
   # Check type
   my $type = $top->{'type'};
   unless (   $type eq 'module'
           || $type eq 'subroutine'
           || $type eq 'function'
           || $type eq 'program'
           || $type eq 'block data') {
      warn "Warning: Unrecognized top-level object $type will " . "not be generated.\n";
      return;
   }

   # print_stmt($top);

   # Check name
   my_die("Cannot generate headers for non-top-level objects\n")
     if $top->{name} =~ /\w+::\w+/;

   # If $do_split is NOT set, combine multiple items
   # and write them with delayed_write() later.
   # Otherwise, we'll write this item to its own file.
   if (not $do_split) {
      push(@topstore, $top);
      return;
   }

   # Initialize module-level variables
   $nindent            = 0;
   $lastline_was_empty = 1;    # Don't start file with empty line

   # Choose a name for the output file if not given
   my $outfile = $top->{'name'};
   if (fixed_fortran()) {$outfile .= '.for'} else {$outfile .= '.f90'};

   # Write
   do_file($top, '>', $outfile);
}

1;
