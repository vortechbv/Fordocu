# Copyright (C) 2009-2010  Planbureau voor de Leefomgeving (PBL)
#
# full notice can be found in LICENSE

package add_info_to_stmt;

=head1 PACKAGE add_info_to_stmt

 This package adds information to a struct which describes a statement,
 after the essential information has been extracted by read_file (module
 stmts.pm).

=head1 CONTAINS

=cut

require 5.003;
use warnings;
use strict;

use stmts('print_stmt');
use dictionary ('store');
use f90fileio('code_and_comment', 'fixed_fortran');
use utils('my_die', 'filesep', 'backticks_without_stderr', 'print_hash' );
use tree2html( 'make_key', 'whatCalls');
use vars ('$VERSION', '@EXPORT_OK', '@ISA');
$VERSION = '1.0';
@ISA     = ('Exporter');

our @EXPORT_OK = ('set_add_info_to_stmt_option', 'add_info_to_top');

### PUBLIC GLOBALS
our $style                   = "";
our $style_package           = '';
our $svn_available           = 0;
our $svnlogoptions           = '';
#########################################################################
sub set_add_info_to_stmt_option($;$){
   my $option = shift;
   if (not @_)  {
      my_die("unknown option '$option'"); die;
   } else {
      if    ($option eq 'style'         ) {
            $style         = shift;
            $style_package = $style."_style";
            if (not eval{ require("$style_package.pm"); }) {
               my_die("unable to load style module $style_package.pm");
               die;
            }
      } elsif ($option eq 'svnlogoptions'       ) { $svnlogoptions=shift;}
      else  {my_die("unknown option '$option'"); die;}
   }
}

#########################################################################

sub XML_Version_history($) {
   use File::Basename;

=head2 @version_history = XML_Version_history($filename);

  If possible, create XML-description of version history

  INPUT VARIABLES
    filename - name of the file for which to make the version history

  OUTPUT VARIABLES
    version_history - XML-code with version history:
                      empty if version history cannot be generated.

=cut

   my $filename = shift;
   my @version_history;

   # No version history if there is no SVN
   return @version_history unless $svn_available;
   return @version_history if ($svnlogoptions =~ /^no[\_\- ]*svn$/i);

   # No version history if `svn info` returns no Repository
   my $svn_out =  backticks_without_stderr("svn info $filename");
   if ( not $svn_out =~ /Repository.*:/)
   {
      print "Version history not available for file '$filename'\n";
      return @version_history;
   }

   # Version history is formatted in XML format by SVN itself
   my $svn_log = backticks_without_stderr("svn log $svnlogoptions ". 
                                                   "--xml $filename");

   # Split output up into lines and remove first line
   # (we use our own header)
   @version_history = split("\n",$svn_log);
   shift(@version_history);

   return @version_history;
}

############################################################################

sub add_info_to_top($) {

=head2 add_info_to_top($top);

  Add information to the statement-struct $top.
  The following fields are added:
     displayname     :
     source          :
     version_history :
     intfc           :
     types           :
     funs            :
     parmstr         :
     header_vars     :
     include_vars    :
     common_vars     :
     local_vars      :
     callers         :

  INPUT/OUTPUT VARIABLES
     $top      : the top-level object to which information is added

=cut

   my $top = shift;

   # stmts::print_stmt($top);

   # Make a display name
   $top->{'displayname'} = $top->{'name'};
   $top->{'displayname'} =~ s/.*::(.+)$/$1/;

   if ($style_package) {
       if ( $top->{description}->{line} ) {
          $style_package->process_description($top);
       }
   }

   # Read the source
   open SOURCE, "<$top->{filename}"
     or my_die("cannot open file '$top->{filename}' for reading");

   #   print "$top->{type} $top->{name} starts at line $top->{firstline}\n";
   #   print "$top->{type} $top->{name} ends at line $top->{lastline}\n" if
   #   $top->{lastline};

   my @source;
   my @code;
   for (my $i = 1 ; ; $i++)
   {
      my $line = <SOURCE>;
      last unless $line;
      next if $top->{'firstline'} && $i < $top->{'firstline'};
      last if $top->{'lastline'} && $i > $top->{'lastline'};

      push(@source, $line);
      $line = code_and_comment($line);
      push(@code, $line);
   }
   close SOURCE;
   $top->{source} = \@source;

   # If available, make version history
   $top->{version_history} = join("\n",
                         XML_Version_history($top->{filename}));

   # Make sublists for
   #     types, variables, interfaces, subroutines, functions
   # defined in this object
   my @types;
   my @intfc;
   my @funs;
   my @vars;
   foreach my $stmt (@{$top->{'ocontains'}}) {
       my $typ = $stmt->{type};
       if ($typ eq "type") {
          push(@types,$stmt);
       } elsif ($typ eq "interface") {
          push(@intfc,$stmt);
       } elsif ( $typ eq "subroutine" or $typ eq "function" ) {
          push(@funs,$stmt);
       } elsif ( $typ eq "var" ) {
          push(@vars,$stmt);
       }
   }
   $top->{intfc} = \@intfc;
   $top->{types} = \@types;
   $top->{funs}  = \@funs;

   # Make sublists for
   #     parameters (function/subroutine arguments, common block variables)
   my @parmstr = ('()');
   $parmstr[0] = '( ' . join(", ", @{$top->{parms}}) . ")"
     if exists($top->{parms});
   foreach my $common (keys(%{$top->{commons}})) {
      push( @parmstr,
            '( ' . join(", ", @{$top->{commons}->{$common}->{vars}}) .  ")");
   }
   $top->{parmstr}  = \@parmstr;

   # Add the line numbers where the variables where referenced
   #   to the variable structs
   foreach my $var (@vars) {
      my @ilines = lines_used($var->{name}, \@code, $top->{firstline});
      $var->{ilines} = \@ilines;
   }

   # Add the line numbers where the types where referenced
   foreach my $type (@types) {
      my @ilines = lines_used($type->{name}, \@code, $top->{firstline});
      $type->{ilines} = \@ilines;
   }

   # For all variables that have no fordocu-style explanation,
   # look in the source code for a different style explanation.
   var_non_fordocu_comments(\@vars, \@source);

   # Make sub-lists of header, local and include variables
   my ($ha, $hv, $cv, $iv, $fv, $lv) =
        variable_categories(\@vars, \@parmstr, $top);
   $top->{header_args}  = $ha;
   $top->{header_vars}  = $hv;
   $top->{include_vars} = $iv;
   $top->{common_vars}  = $cv;
   $top->{local_vars}   = $lv;

   # If it's available, obtain the list of routines calling this one
   my $my_module = '';
   my $pos       = $top;
   while ($pos->{parent}) {
      $pos = $pos->{parent};
      if ($pos->{type} =~ /(?:module|subroutine|function|program)/) {
         $my_module .= ($my_module ? '::' : '') . $pos->{name};
      }
   }
   my $me = make_key($top->{type}, $top->{name}, $my_module);
   $top->{callers} = whatCalls($me);
}



# --------------------------------------------------------------------------
sub lines_used($$$)
{

=head2 @ilines = lines_used($name, \@code, $firstline);

  Return the line numbers in which the given $name was used

  INPUT VARIABLES
     $name - the name of the object looked for in the code
     @code - the Fortran-lines, stripped of comments
     $firstline - line number in the file for the first line
                  of this subroutine
  OUTPUT VARIABLES
     @ilines - line numbers where $name was mentioned

=cut

   my $name = shift;
   my @code = @{$_[0]};
   shift;
   my $firstline = shift;
   my @ilines    = ();

   if ($name eq 'c' and fixed_fortran()) {
      foreach my $iline (0 .. $#code) {
         if ($code[$iline] =~ /..*\b$name\b/) {
            my $jline = $iline + $firstline;
            push(@ilines, $jline);
         }
      }
   } else {
      foreach my $iline (0 .. $#code) {
         if ($code[$iline] =~ /\b$name\b/) {
            my $jline = $iline + $firstline;
            push(@ilines, $jline);
         }
      }
   }
   return @ilines;
}

# --------------------------------------------------------------------------
sub variable_categories($$$)
{

=head2  (\@header_args, \@header_vars,\%common_vars,\%include_vars,
         \@function_vars, \@local_vars) =
         variable_categories(\@vars,\@parmstr,$top);

   Categorize the variables and return the different categories

   INPUT VARIABLES
      @vars   - struct array with variable descriptions
      @parmstr- parameter lists for common blocks and
                for function/subroutine itself
      $top    - struct-pointer with all info about the top-level
                object

   OUTPUT VARIABLES
     @header_args  - struct array with header arguments in the proper order
     @header_vars  - struct array with header variables
     %common_vars  - struct arrays with common variables:
                     a field for every common block
     %include_vars - struct arrays with include variables:
                     a field for every include file
     @function_vars- struct array with function variables
     @local_vars   - struct array with local variables

=cut

   my @vars = @{$_[0]}; shift;
   my @parmstr = @{$_[0]}; shift;
   my $top = shift;

   my @header_vars;
   my %common_vars;
   my %include_vars;
   my @function_vars;
   my @local_vars;

   my $idebug = 0;

 VAR: foreach my $var (@vars) {
      my $name = $var->{name};
      my $include=0;
      my $function=0;
      my $common =0;
      my $header =0;
      my $local =0;

      # Variable with same name as function itself: header variable
      # (result of the function); other possibility: rtype flag
      if (lc($name) eq lc($top->{name}) or $var->{retval}) {
         push(@header_vars, $var);
         $header=1;
      } elsif ($var->{function} and $var->{function} eq 'yes') {
         push(@function_vars, $var);
         $function = 1;
      } else {
         # Header and common variables
         my $i = 0;
         foreach my $common ('"header"', keys(%{$top->{commons}})) {
            if ($parmstr[$i] =~ /[(,] *$name[,)]/i) {
               if ($i == 0) {
                  push(@header_vars, $var);
                  $header = 1;
                  last;
               } elsif (@{$var->{ilines}}) {
                  $common_vars{$common} = []
                    unless exists($common_vars{$common});
                  push(@{$common_vars{$common}}, $var);
                  $common=1;
                  last;
               }
            }
            $i++;
         }

         if ($var->{filename} ne $top->{filename}) {
            $include=1;
            if (@{$var->{ilines}}) {
               $include_vars{$var->{filename}} = []
                  unless exists($include_vars{$var->{filename}});
               push(@{$include_vars{$var->{filename}}}, $var);
            }
         } elsif (not $common and not $header) {
            push(@local_vars, $var);
            $local=1;
         }
      }

      if ($idebug) {
         warn "var $name is a local variable\n"  if ($local);
         warn "var $name is a common variable\n" if ($common);
         warn "var $name is a header variable\n" if ($header);
         warn "var $name is a function variable\n" if ($function);
         warn "var $name is an include variable\n" if ($include);
         warn "var $name is not even mentioned in $top->{filename}\n"
            if (@{$var->{ilines}}==0);
      }
   }

   # Sort header arguments in the proper order (IMPORTANT)
   my @header_args = split(/\s*[\,\(\)]\s*/, $parmstr[0]);
   if ($header_args[0]) {
      my_die($header_args[0]); die;
   }
   my @srt; 
   foreach my $hv (@header_vars) {
      if ($hv->{retval}) {
         $srt[0] = $hv; 
         next;
      } elsif ($hv->{within}->{type} eq "function" and
               uc($hv->{within}->{name}) eq uc($hv->{name})) {
         next;
      }

      foreach my $index (1 .. $#header_args) {
         if (uc($header_args[$index]) eq uc($hv->{name})) {
            $srt[$index] = $hv;
            last;
         }
         if ($index==$#header_args) {
            stmts::print_stmt($hv);
            my_die("header argument '$hv->{name}' not found\n");
         }
      }
   }

   
   foreach my $index (1 .. $#srt) {
      if (not defined($srt[$index])) {
        my $name = $header_args[$index];
        my $vartype = $typing::default_type{real};
        $vartype = $typing::default_type{integer} if ($name =~ /^[i-n]/);
        $srt[$index] = {
          type        => 'var',
          name        => $name,
          vartype     => $vartype,
          filename    => $top->{filename},
          orgfilename => '',
          function    => 'no',
          label       => '',
          collected_comments => [
                   {line => '!implicit declaration',
                    comment_is_eoln => 1,
                    guessed => 1
                   }
               ],
          macrodata   => {},
          description => {
                   'line'    => '',
                   'guessed' => 0,
                   'from_dictionary' => 0,
                   'after_the_line'   => 0,
                   'comment_is_eoln' => 0,
                  }
        };
        my_die("Implicit declaration of argument " . 
                "$index: '$header_args[$index]' " . 
               "\n     for $top->{type} '$top->{name}'\n     ");
      }
   }

   shift(@srt) if (not defined($srt[0]));
   @header_vars = @srt;
   
   return (\@header_args, \@header_vars, \%common_vars, \%include_vars,
           \@function_vars, \@local_vars);
}

############################################################################
sub var_non_fordocu_comments($$)
{

=head2 var_non_fordocu_comments(\@vars,\@source);

   For all variables that have no fordocu-style explanation,
   look in the source code for a different style explanation.

   INPUT VARIABLES
       @vars   - struct-array with variable descriptions
       @source - source lines of the routine

=cut

   # Nothing to do if no style has been specified
   return if ($style_package eq '');

   my $vars   = shift;
   my $source = shift;

   my $idebug=0;

   # Look for all variables' descriptions
   foreach my $var (@$vars) {
      my $var_source = $source;

      $var->{description} = {line=>'', guessed=>''}
           if (not exists($var->{description}));

      # Only if they are used in the code itself
      next if (@{$var->{ilines}}==0);

      my $name = $var->{name};

      # Open include-file if the variable was declared in an
      # include file
      if ( $var->{within}->{filename} ne $var->{filename}) {
         print "opening file $var->{filename} for $name\n" 
               if ($idebug>=1);
         open INCFILE,"<$var->{filename}" or next;
         my @var_source = <INCFILE>; close INCFILE;
         $var_source = \@var_source;
      }

      # Find the style-specific description
      my $descr = '';
      my $i     = 0;
      while (($descr eq '') and ($i < $#{@$var_source})) {
          ($i, $descr) = $style_package->line($i, $name, $var_source);
          $i++;
      }

      # If found, store it
      if ($descr ne "") {
         print "    found description '$descr' for variable '$name'\n"
            if ($idebug>=1);
         # Add it to variable's description
         $var->{description} = { line => $descr, guessed => 0,
                                 non_fordocu =>1
                               };

         # Add it to dictionary
         store($name, $descr);

         # Mark all comments 'not used in description' and remove guessed lines
         # from comments
         my @collected_comments = ();
         foreach my $line (@{$var->{collected_comments}}) {
            push(@collected_comments, $line) unless ($line->{guessed});
         }
         foreach my $line (@collected_comments) {
            $line->{to_description}=0;
         }
         $var->{collected_comments} = \@collected_comments;
      } else {
         print "    found no description for variable '$name'\n"
            if ($idebug>=1);

      }
   }
}


# INITIALIZATION
{

  # Run SVN to ask fir its version (error message will be returned in case
  # SVN does not exist.
  my $svn_version = backticks_without_stderr("svn --version");

  # See if SVN was there: its version description will have the word
  # 'Subversion' in it.
  $svn_available = ($svn_version =~ /Subversion/)
     if defined($svn_version);

  # Print the result
  my_die(
     "  SVN is not available on this computer\n" .
     "  this was tested using the command 'svn --version'\n" .
     "  Version histories will not be available in the documentation",
     "WARNING")
     if (not $svn_available);
}

1;
