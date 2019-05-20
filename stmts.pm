# Copyright (C) 2009-2010  Planbureau voor de Leefomgeving (PBL)
#
# full notice can be found in LICENSE

package stmts;

=head1 PACKAGE stmts

 This package contains functions to interpret Fortran statements.

=head1 CONTAINS

=cut

require 5.003;
use warnings;
use strict;
use tree2html('make_key', 'calledBy', 'split_key', 'tryToFindFunction');

use vars ('$VERSION', '@EXPORT_OK', '@ISA');
$VERSION = '1.0';
@ISA     = ('Exporter');

our @EXPORT_OK = ('read_file', 'set_stmtsoption', 'print_stmt');

use File::Spec;
use Cwd ('abs_path');
use typing ('parse_character_arguments', 'make_character_type', 'make_type');
use expr_parse ('parse_expr');
use f90fileio ('return_strings', 'open_file', 'read_line', 'currently_reading',
               'get_string', 'reset_comments', 'hashed_comments',
              'line_number', 'get_pseudocode', 'after_comments');
use utils ('balsplit', 'trim', 'my_die');


#########################################################################
# PUBLIC GLOBALS

# Set to a reference to a routine to return accumulated comments if !!
# comments are caught.  You should reset them after each time you call
# read_line or read_stmt. Also store the starting line number and
# whether the current (stored) comment is an end-of-line comment.

our $wordchar   = '\w';
our $letterchar = 'a-zA-Z';

# List of built-in statements and functions
# This list is also used for syntax highlighting in htmling
# Salford extensions: edate
# GNU extensions
our @builtin_statements = qw(abort
  abs access achar acos action
  ad adjustl adjustr advance aimag aint alarm algama all
  allocatable allocate allocated alog alog10 amax0
  amax1 amin0 amin1 amod and anint any asin assign
  assignment associated atan atan2 backspace besj0
  besj1 besjn besy0 besy1 besyn bit_size
  blank block blockdata btest cabs call case ccos
  cdabs cdcos cdexp cdlog cdsin cdsqrt ceiling cexp
  char character chdir chmod clog close cmplx common complex
  conjg contained contains continue cos cosh count
  cpu_time cqabs cqcos cqexp cqlog cqsin cqsqrt cshift
  csin csqrt ctime cycle dabs dacos dasin data datan datan2
  date date_and_time dbesj0 dbesj1 dbesjn dbesy0 dbesy1 dbesyn
  dble dcmplx dconjg dcos dcosh
  ddim deallocate default delim derf derfc dexp dfloat
  dgamma digits dim dimag dimension dint direct dlgama
  dlog dlog10 dmax1 dmin1 dmod dnint do dot_product
  double doublecomplex doubleprecision dprod dsign
  dsin dsinh dsqrt dtan dtanh dtime edate elemental else elseif
  elsewhere end enddo endfile endforall endfunction
  endif endinterface endmodule endprogram endselect
  endsubroutine endtype endwhere eor eoshift epsilon
  .eq. equivalence eqv erf erfc errsns etime exist exit exp
  exponent external .false. fdate fget fgetc file fixme float
  floor flush fmt fnum
  forall form format formatted fput fputc fraction free fseek
  fstat ftell function gamma .ge. gerror get_command
  get_command_argument
  get_environment_variable getarg getcwd getenv getgid getlog
  getpid getuid gmtime .gt. hostnm huge iabs iachar
  iand iargc ibclr ibits ibset ichar idate idim idint idnint
  ieor ierrno if ifix imag imagpart implicit in include
  index inout inquire
  int int2 int8 integer intent interface inum ior iostat iqint
  irand isatty ishft ishftc ishift isign itime kill
  kind lbound .le. len len_trim lge lgt link lle
  llt lnblnk loc log log10 logical long .lt. lshift lstat
  ltime matmul max max0 max1
  maxexponent maxloc maxval mclock mclock8
  merge min min0 min1
  minexponent minloc minval mm_prefetch mod module
  modulo move_alloc mvbits name named namelist .ne.
  nearest nextrec nint nml none .not. not nullify number
  only
  open opened operator optional .or. out pack parameter
  pause perror pointer position precision present print private
  procedure product program public pure qabs qacos qasin
  qatan qatan2 qcmplx qconjg qcos qcosh qdim qerf qerfc
  qexp qgamma qimag qlgama qlog qlog10 qmax1 qmin1 qmod
  qnint qsign qsin qsinh qsqrt qtan qtanh radix rand
  random_number random_seed randu range read readwrite
  real realpart rec recl recursive rename repeat reshape
  result return
  rewind rrspacing rshift save scale scan second
  select selectcase
  selected_int_kind selected_real_kind sequence sequential
  set_exponent shape short sign signal
  sin sinh size sleep sngl spacing
  spread sqrt srand stat status stop
  subroutine sum symlnk system system_clock tan
  tanh target then time time8 tiny to todo transfer transpose
  trim .true. ttynam type ubound umask unformatted
  unit unlink unpack use verify where while write
  xor zabs zcos zexp zlog zsin zsqrt
  );

#########################################################################
# PRIVATE GLOBALS

#
# Nesting:
#
#   Code which is being read may be 'inside' a Fortran construction.
#
#   The things which code may be inside are:
#       modules, programs, routines, functions, types, structures,
#       block datas, interfaces.
#
#   Fortran constructions may, in turn, be inside other Fortran
#   constructions:
#       subroutines and functions may be inside interfaces;
#       other Fortran constructions may only be inside
#             subroutines, functions, modules and programs.
#
#   FOR INSTANCE: If the current line is inside a type definition which
#   is inside a subroutine inside a module, this is administrated
#   in the array @nesting, where
#       $nesting[0]->{type} = 'module'
#       $nesting[1]->{type} = 'subroutine'
#       $nesting[2]->{type} = 'type'
#
#   Always, we have
#       $topnest = $nesting[$#nesting],  ($topnest is the last item in @nesting)
#   so $topnest is the thing that the current line is inside directly.
#
#   The struct %nesting_by is used to detect improper nesting, but I
#   have not yet figured out what that means.
#
#   The administration array @nesting consists of a number of structs, each
#   struct being a part of the preceding struct. These structs keep track
#   of their contents in two seperate ways:
#      1. field $struct->{contains}, in which each item which is inside the
#         struct is represented by  $struct->{contains}->{$name}->{$type};
#      2. field $struct->{ocontains}, which is an array of items
#         inside the struct.
#
#   EXAMPLE: If the subroutine 'do_stuff' is represented by the struct
#            (reference)
#            $struc1, and it has an integer variable 'i', represented by the
#            struct (reference) $struc2,
#         then
#            $struc1->{contains}->{i}->{var} == $struc2;
#         and
#            ${$struc1->{ocontains}}[$j] == $struc2; (for some index $j).
#         Moreover, the subroutine can also be found from the variable definition,
#         because
#            $struc2->{within} == $struc1.
#
#  The double administration of contained items is useful, because it allows quick
#  searching via $struct->{contains}, while the original order of appearance is
#  maintained in $struct->{ocontains}.
#
my @nesting = ();
my $topnest = undef;

# List of structure pointers that we're currently nested in, but for a
# specified type.
my %nesting_by = ();

# Define a constant regular expression which enumerates
#    the possible variable types
my $vartypes = 'integer|real|double\s*precision|character|complex|logical|type';

#########################################################################
#--------------------------------------------------------------


sub process_module_procedure($$$);
sub process_module_or_program($$$$);
sub process_end($$$$$);
sub process_routine_or_function($$$$$$$);
sub process_type($$$$);
sub process_structure($$$);
sub process_block_data($$$);
sub process_interface($$$);
sub process_contains($$);
sub process_public_private_or_sequence($$$$);
sub process_optional($$$$);
sub process_var($$$);
sub process_save($$$);
sub process_parameter($$$);
sub process_data($$$);
sub process_use($$$$);
sub process_common($$$$$);
sub process_dimension($$$$);
sub process_external($$$);
sub process_implicit_none($$);
sub process_body($$$);
sub process_call($$$$$);

sub set_stmtsoption($;$) {
   my $option = shift;
   if (not @_)  {
      my_die("unknown option '$option'"); die;
   } else {
      if    ($option eq 'letterchar'    ) { $letterchar = shift;}
      if    ($option eq 'wordchar'      ) { $wordchar = shift;}
      else          {my_die("unknown option '$option'"); die;}
   }
}
#-----------------------------------------------------------------------
sub print_stmt($;$);
sub print_stmt($;$) {
   my $top = shift;
   my $level=0; if (@_) {$level = shift;}

   my $margin = '   ' x $level;
   print "$margin+ $top->{type} '$top->{name}'\n";

   if (defined($top->{collected_comments}) and  @{$top->{collected_comments}}) {
      print "   $margin+ collected_comments :\n" ;
      foreach my $comment (@{$top->{collected_comments}}) {
          print "         $margin+ '$comment->{line}'";
          print " (eoln)" if ($comment->{comment_is_eoln});
          print " (after)" if ($comment->{after_the_line});
          print "\n";
      }
   }

   if (defined($top->{include_vars})) {
      print "   $margin+ include_vars:\n" ;
      foreach my $key (keys(%{$top->{include_vars}})) {
         print "      $margin+ $key:\n" ;
         foreach my $item (@{$top->{include_vars}->{$key}}) {
            print_stmt($item,$level+2);
         }
      }
   }

   foreach my $key (keys(%$top)) {
     print "   $margin+ $key\n"
          if ($key eq "within" or $key eq "contains" or
              $key eq "source"); # or $key eq "parent");
     next if ($key eq "name" or $key eq "type" or $key eq "within" or
              $key eq "collected_comments" or $key eq "ocontains" or
              $key eq "contains" or $key eq "include_vars" or
              $key eq "source" ); #  or $key eq "parent");
     my $ref = ref($top->{$key});
     if (not defined($top->{$key})) {
       print "   $margin+ $key = 'undef'\n" ;
     } elsif ($key eq "types") {
       print "   $margin+ $key :\n";
       foreach my $type (@{$top->{$key}}) {
          print_stmt($type,$level+2);
       }
     } elsif ($ref eq "HASH") {

       print "   $margin+ $key :\n" if (keys(%{$top->{$key}}));
       foreach my $key1 (keys(%{$top->{$key}})) {
          if (defined($top->{$key}->{$key1})) {
            print "      $margin+ $key1 = '$top->{$key}->{$key1}'\n" ;
          } else {
            print "      $margin+ $key1 = 'undef'\n" ;
          }
       }
     } elsif ($ref eq "ARRAY") {
       print "   $margin+ $key :\n" if (@{$top->{$key}});
       foreach my $item (@{$top->{$key}}) {
          print "      $margin+ '$item'\n";
       }
     } else {
       print "   $margin+ $key = '$top->{$key}'\n" ;
     }
   }

   if (defined($top->{ocontains}) and  @{$top->{ocontains}}) {
      print "   $margin+ ocontains :\n" ;
      foreach my $item (@{$top->{ocontains}}) {
         print_stmt($item,$level+2);
      }
   }

}
#-----------------------------------------------------------------------

sub read_file($) {

=head2 @top = read_file ($infile)

  Reads an entire file, and returns all the top-level structures found.
  If specified, a given function will be called after every statement
  (usually this is for resetting !! comments and such).

  INPUT VARIABLES
     $infile      - name of the Fortran source file

  OUTPUT VARIABLES
     @top         - array with a struct-pointer for every top level
                  - object in - the source file

=cut

   my $filename = shift;
   my @top = ();
   my $idebug=0;

   # Open the file
   open_file($filename);

   my ($prev_stmt, $prev_struct);    # Previous values
   my ($stmt, $struct) = read_stmt($prev_stmt, $prev_struct);

   while ($stmt) {

      if ($idebug>=1) {
         # Dit kan worden verwijderd als cod eklaar is.
         print "\tSTART DEBUGOUTPUT\n\n";
         print "\tProcessing statement '$stmt'\n";
         print "\tProcessing struct '$struct->{name}:$struct->{type}'\n"
            if (ref $struct);
         print "\tPrevious struct is " .
               "'$prev_struct->{name}:$prev_struct->{type}'\n"
            if (ref $prev_struct);
         print "\tENDED DEBUGOUTPUT\n\n";
      }

      # Add the new structure declared in this statement
      #    If the statement contains a reference (to a hash)
      #    And it is not nested in something else
      if (!defined $topnest && ref $struct) {
         $struct->{filename} = $filename;
         $struct->{fullpath} = clean_path($filename);
         push @top, $struct;
         reset_comments();
      }

      # Update previous values
      ($prev_stmt, $prev_struct) = ($stmt, $struct);
      ($stmt, $struct) = read_stmt($prev_stmt, $prev_struct);
   }


   if ($idebug >=1 ) {
      print "The top-level items in file '$filename' are:\n";
      foreach my $a_top (@top) { print_stmt($a_top,1); }
   }

   return @top;
}

sub find_suspects($);    # Recursive

sub find_suspects($)
{

=head2 @suspects = find_suspects($line)

  find possible function calls in the given line

  INPUT VARIABLES
     $line - Line to search for possible function calls

  OUTPUT VARIABLES
     @suspects - array with names of possible function calls

=cut

   my $line      = shift;
   my $varnamexp = "\b[$letterchar]$wordchar*";
   $line =~ s/($varnamexp)\.([$letterchar])/$1%$2/g;

   my @suspects = ();
   while ($line =~ s/(call|)\ *\b([\%]?\ *[A-Za-z_]\w*)\ *(\(.*\))//i) {
      my $type = lc($1);
      my $name = lc($2);
      my $args = $3;

      # If call is found, it's a subroutine
      next if $type eq 'call';

      # If the name starts with a %, it's a type member,
      # so it cannot be a function
      next if $name =~ /^\%/;

      # Check whether the argument contains a : outside brackets
      # Do not count the initial and the last bracket
      my $ac = $args;
      $ac =~ s/^\((.*)\)$/$1/;
      while ($ac =~ s/(.*)\(.*\)(.*)/$1 $2/) { }
      next if $ac =~ /\:/;

      # If the arguments contain brackets, handle arguments
      if ($args =~ /.+\(.*\)/) {
         no warnings 'recursion';
         my @fs = find_suspects($args);
         push(@suspects, @fs);
      }

      push(@suspects, $name) unless $type;
   }
   return @suspects;
}



sub process_module_procedure($$$) {

  my $iline   = shift;
  my $label   = shift;
  my $detail1 = shift;
  my ($jline, $filename, $orgfilename) = currently_reading();

  # MODULE PROCEDURE

  # Check correct nesting situation
  #  (must be before module, inside interface block)
  my_die("module procedure outside of interface block")
    unless defined $topnest
       and $topnest->{'type'} eq "interface"
       and $topnest->{'name'} ne "";

  # Split the names of the module procedures
  my @list = split(/\s*,\s*/, trim($detail1));

  # Administrate a new struct for each module procedure declared
  my @structs;
  foreach my $p (@list) {
     my_die("Invalid module procedure `$p'")
       unless $p =~ /^\w+$/;

     my $struct = {
                 'type'      => "mprocedure",
                 'name'      => $p,
                 'scalars'   => [],
                 'functions' => [],
                 'label'     => $label,
                 hashed_comments()
     };

     new_struct( $struct);
     push(@structs,$struct);
  }

  # Done
  return ("mprocedure", @structs);
}

sub process_module_or_program($$$$) {

=head2 ($type, \%struct) = process_module_or_program(
                               $iline, $label, $detail1, $detail2)

  Process a line which contains a module or a program definition

  INPUT VARIABLES
      $iline    - line number where this statement started
      $label    - label number, in case this statement has one.
      $detail1  - first detail about this call, determined by
                  classify_line:
                     'program' or 'module'
      $detail2  - second detail about this call, determined by
                  classify_line:
                     name of program or module

  OUTPUT VARIABLES
      $type   - type of the structure (e.g. 'program')
                NB: this output variable will be removed later,
                     because it is identical to $struct->{type}
      %struct - struct describing the statement, its type, name
                and all other relevant details.

=cut

   my $iline    = shift;
   my $label    = shift;
   my $detail1  = shift;
   my $detail2  = shift;

   my ($jline, $filename, $orgfilename) = currently_reading();

   # MODULE/PROGRAM
   # A module or program must not be nested
   my_die("$detail1 begun not at top level")
          if defined $topnest;

   # Determine first line
   my $firstline = line_number('comment_start');

   # Administrate a new top level and return
   my ($type,$struct) = new_nest( {
               'type'        => lc $detail1,
               'name'        => (defined $detail2 ? $detail2 : ''),
               'firstline'   => $firstline,
               'filename'    => $filename,
               'orgfilename' => $orgfilename,
               'scalars'     => [],
               'functions'   => [],
               'label'       => $label,
               hashed_comments()
   });

   return ($type,$struct)
}

sub process_end($$$$$) {

=head2 ($type, \%struct) = process_end(
                               $iline, $label, $detail1, $detail2, $line)

  Process a line in which something is being ended

  INPUT VARIABLES
      $iline    - line number where this statement started
      $label    - label number, in case this statement has one.
      $detail1  - first detail about this call, determined by
                  classify_line:
                     the type of thing which is being ended
      $detail2  - second detail about this call, determined by
                  classify_line:
                     name of the thing which is being ended
      $line     - the line of fortran code

  OUTPUT VARIABLES
      $type   - type of the structure (e.g. 'program')
                NB: this output variable will be removed later.
                    Currently, $type is something like 'end subroutine'.
                    However, $struct->{type} is 'subroutine'.
                    Hence, $type and $struct->{type} are not the same.
                    We must make it possible to derive the fact that the
                    statement ended something, for example by setting a
                    flag 'ended' in the struct.
      %struct - struct describing the statement, its type, name
                and all other relevant details.

=cut

   my $iline    = shift;
   my $label    = shift;
   my $detail1  = shift;
   my $detail2  = shift;
   my $line     = shift;

   my ($jline, $filename, $orgfilename) = currently_reading();


   # END MODULE/SUBROUTINE/FUNCTION/PROGRAM/TYPE/INTERFACE/STUCTURE/BLOCK DATA,
   #     or general END
   my_die("END statement outside of any nesting")
     unless defined $topnest;

   my $top       = $topnest;
   my $ends_what = $detail1 ? lc($detail1) : $top->{type};
   my $ends_who  = $detail2 ? lc($detail2) : $top->{name};

   $ends_what = 'type' if ($ends_what eq "structure");

   my_die("$line cannot end $top->{type} $top->{name}")
     if $ends_what ne $top->{'type'};

   # We do some special "fixing up" for modules, which resolves named
   # references (module procedures) and computes publicity.
   #
   # Note that end_nest will ensure that the type of thing ended matches
   # the thing the user says it is ending, so we don't have to worry about
   # that.
   fix_module_end() if ($top->{'type'} eq "module");

   my ($type, $struct) = end_nest($ends_what, $ends_who);

   # Register last line in the routine
   $top->{lastline} = $iline;

   # store pseudocode for subroutines, functions and programs
   if ($top->{'type'} =~ /(?:subroutine|function|program)/) {
      my $pseudocode = get_pseudocode();
      $top->{'pseudocode'} = $pseudocode if ($pseudocode);
   }

   # warn and clear pseudocode for modules
   if ($top->{'type'} eq 'module') {
      my $pseudocode = get_pseudocode();
      warn("Pseudocode $pseudocode leaked into module $top->{'name'}\n")
           if ($pseudocode =~ /\w/);
   }

   # Store label (if any)
   $top->{label_end} = $label;

   warn "$top->{type} $top->{'name'} ends in another file than it starts.\n"
     . "start in: $top->{filename}\n"
     . "ends  in: $filename\n"
     if ($top->{filename} ne $filename);

#   new_struct($struct);
   return ($type,$struct);
}


sub process_routine_or_function($$$$$$$) {

=head2 ($type, \%struct) = process_routine_or_function
                               $iline, $label, $detail1, .. $detail5)

  Process a line which contains a module or a program definition

  INPUT VARIABLES
      $iline    - line number where this statement started
      $label    - label number, in case this statement has one.
      $detail1  - first detail about this call, determined by
                  classify_line:
                     variable type of the function, if this is a
                     function.
      $detail2  - second detail about this call, determined by
                  classify_line:
                     'subroutine' or 'function'
      $detail3  - third detail about this call, determined by
                  classify_line:
                     name of program or module
      $detail4  - third detail about this call, determined by
                  classify_line:
                     parameter list of function or subroutine
                     (the stuff between parentheses)
      $detail5  - third detail about this call, determined by
                  classify_line:
                     name of the result, if this is a function.

  OUTPUT VARIABLES
      $type   - type of the structure (e.g. 'function')
                NB: this output variable will be removed later,
                     because it is identical to $struct->{type}
      %struct - struct describing the statement, its type, name
                and all other relevant details.

=cut

   my $iline    = shift;
   my $label    = shift;
   my $detail1  = shift;
   my $detail2  = shift;
   my $detail3  = shift;
   my $detail4  = shift;
   my $detail5  = shift;

   my ($jline, $filename, $orgfilename) = currently_reading();

   # SUBROUTINE/FUNCTION
   # Get all the parts from the line
   my ($type, $name, $parmstr, $rtype, $result) =
      (lc $detail2, $detail3, $detail4, $detail1, $detail5);
   $parmstr = "()" unless defined $parmstr;

   # Check nesting
   my_die("Start of $type $name before `contains' section " .
                 "of $topnest->{'type'} $topnest->{'name'}")
     if defined $topnest
        and not $topnest->{'incontains'}
        and $topnest->{'type'} ne "interface";

   # Check improper nesting
   if (   exists $nesting_by{'subroutine'} or exists $nesting_by{'function'}) {
      my $n = 0;
      $n += scalar @{$nesting_by{'subroutine'}}
        if exists $nesting_by{'subroutine'};
      $n += scalar @{$nesting_by{'function'}}
        if exists $nesting_by{'function'};
      my_die("Routine nested in routine nested in routine")
        if $n > 1;
   }

   # Split the parameter string into parameters
   my @parms = split_parameters($parmstr);

   # Determine first line
   my $firstline = line_number('comment_start');

   # Put the information found so far into a struct
   my $struct = {
                 'type'        => $type,
                 'name'        => $name,
                 'parms'       => \@parms,
                 'firstline'   => $firstline,
                 'filename'    => $filename,
                 'orgfilename' => $orgfilename,
                 'scalars'     => [],
                 'functions'   => [],
                 'label'       => $label,
                 hashed_comments()
                };
   new_nest($struct);

   $struct->{'result'} = $result if defined $result;

   # Strip the words 'recursive', 'pure', 'elemental'
   # from the data type, and set flags for the directives found
   $rtype = "" unless defined $rtype;
   while (   $rtype =~ /(?:^|\s+)(recursive|pure|elemental)$/i
          or $rtype =~ /^(recursive|pure|elemental)(?:\s+|$)/i) {
      $rtype = $` . $';       # actually whichever is not blank
      $struct->{lc $1} = 1;
   }

   # Set the data type in the form of a structure (after parsing)
   if ($rtype ne '') {
      $struct->{'rtype'} = parse_type($rtype, $vartypes);
      new_struct( {
                  'type'        => 'var',
                  'retval'      => 1,
                  'name'        => (defined $result ? $result : $name),
                  'vartype'     => $struct->{'rtype'},
                  'filename'    => $filename,
                  'orgfilename' => $orgfilename,
                  'label'       => $label,
                  'comments'    => ''
      });
   }

   return ($type, $struct);
}


sub process_type($$$$) {

   my $iline    = shift;
   my $label    = shift;
   my $detail1  = shift;
   my $detail2  = shift;

   my ($jline, $filename, $orgfilename) = currently_reading();

   # TYPE definition (must go before variable declarations)

   # Determine first line
   my $firstline = line_number('comment_start');

   my ($type,$struct) = new_nest({
       'type'        => 'type',
       'name'        => $detail2,
       'filename'    => $filename,
       'orgfilename' => $orgfilename,
       'label'       => $label,
       'firstline'   => $firstline,
       hashed_comments()
   });

   if (defined $detail1) {
      my $attrib = trim(substr($detail1, 1));
      if ($attrib =~ /^(public|private)$/i) {
         $struct->{'vis'} = lc $attrib;
      } elsif ($attrib) {
         warn "Invalid attribute `$attrib' for derived-type " .
              "declaration--should be just public or private";
      }
   }
   return ($type,$struct);
}

sub process_structure($$$) {
   my $iline    = shift;
   my $label    = shift;
   my $detail1  = shift;

   my ($jline, $filename, $orgfilename) = currently_reading();

   # TYPE definition (must go before variable declarations)
   my ($type,$struct) = new_nest({
       'type'        => 'type',
       'name'        => $detail1,
       'filename'    => $filename,
       'orgfilename' => $orgfilename,
       'label'       => $label,
       hashed_comments()
   });

   return ($type,$struct);
}


sub process_block_data($$$) {
   my $iline    = shift;
   my $label    = shift;
   my $detail1  = shift;

   my ($jline, $filename, $orgfilename) = currently_reading();

   # BLOCK DATA definition

   # Determine first line
   my $firstline = line_number('comment_start');

   my ($type,$struct) = new_nest({
     'type'        => 'block data',
     'name'        => $detail1,
     'filename'    => $filename,
     'orgfilename' => $orgfilename,
     'label'       => $label,
     'firstline'   => $firstline,
     'scalars'     => [],
     'functions'   => [],
     'uses'        => [],
     hashed_comments()
   });

   return ($type,$struct);
}

sub process_interface($$$) {
   my $iline    = shift;
   my $label    = shift;
   my $detail1  = shift;

   my ($jline, $filename, $orgfilename) = currently_reading();

   # INTERFACE block (for overloading) or statement
   #   (for definition of external)

   # Determine first line
   my $firstline = line_number('comment_start');

   my ($type,$struct) = new_nest({
     'type'        => 'interface',
     'name'        => (defined $detail1 ? $detail1 : ""),
     'filename'    => $filename,
     'orgfilename' => $orgfilename,
     'label'       => $label,
     'firstline'   => $firstline,
     hashed_comments()
   });

   return ($type,$struct);
}

sub process_contains($$) {

#
# Deze moet nog even goed gemaakt worden want ik weet niet wat contains
# eigenlijk precies doet.
#

   my $iline    = shift;
   my $label    = shift;

   my ($jline, $filename, $orgfilename) = currently_reading();

   # CONTAINS

   my_die("`contains' found at top level")
     unless defined $topnest;
   my_die("`contains' found in $topnest->{'type'} " . "$topnest->{'name'}")
     unless exists $topnest->{'incontains'};
   my_die("Multiple `contains' found in same scope")
     if $topnest->{'incontains'};
   my_die("`contains' found in interface definition")
     if $topnest->{'interface'};

   $topnest->{'incontains'} = 1;

   return ("contains", $topnest);
}


sub process_public_private_or_sequence($$$$) {
#
# Deze spuugt soms alleen zijn type uit en soms zijn type
# plus een lijst.  Dat moet nog netjes in een struct gestopt worden.
#
   my $iline    = shift;
   my $label    = shift;
   my $detail1  = shift;
   my $rest     = shift;

   my ($jline, $filename, $orgfilename) = currently_reading();


   # PUBLIC/PRIVATE/SEQUENCE
   (my $type, $rest) = (lc $detail1, $rest);

   if (defined $topnest and $topnest->{'type'} eq "type") {
      my_die("public statement not allowed in a type declaration")
        if $type eq 'public';
      my_die("$detail1 cannot be qualified inside type declaration")
        if $rest;
      $topnest->{$type . 'type'} = 1;
      return ($type, $topnest);
   } else {
      my_die("sequence statement only allowed " .
             "immediately inside type declaration")
        if $detail1 eq 'sequence';

      my_die("$detail1 statement not immediately inside a " .
             "module or type declaration")
        unless defined $topnest and $topnest->{'type'} eq "module";

      if ($rest eq "") {
         # Unqualified
         my_die("Unqualified $type in addition to \"unqualified\" " .
                $topnest->{'defaultvis'})
           if exists $topnest->{'defaultvis'};

         $topnest->{'defaultvis'} = $type;
         return ($type, $topnest);
      } else {
        # Qualified
         my @namelist = map {
            my_die("Invalid name `$_' specified in $type statement")
              unless /^\s*(\w+)(?:\s*(\([^()]+\)))?\s*$/i;
            $1 . (defined $2 ? $2 : "");
         } (split ',', $rest);

         push @{$topnest->{"${type}list"}}, @namelist;

         return ($type, $topnest);
      }
   }
}


sub process_optional($$$$) {
#
# Deze spuugt alleen een lijst terug. Dat moet nog netjes in een struct gestopt
# worden.
#
   my $iline    = shift;
   my $label    = shift;
   my $detail1  = shift;
   my $detail2  = shift;

   my ($jline, $filename, $orgfilename) = currently_reading();

   # OPTIONAL
   my @namelist = split(/\s*,\s*/, trim($detail2));
   foreach my $name (@namelist) {
      do_attrib($name, "optional", 1, "optional attribute");
   }
   return ('optional', $topnest);
}

sub rephrase_allocatable($$$) {
#
#  TODO: verplaatsen naar beneden? Niet tussen process_sub dingen???
#
   my $type = shift;
   my $vars = shift;
   my $dim  = shift;

   my $line;
   if ($type =~ /type/) {
      $vars =~ s/(\(.*\))//;
      $type .= $1;
   } elsif ($vars =~ /^\*/) {
      $vars =~ s/^(\*\([^\(]*\))//;
      $type .= $1;
      $vars =~ s/^(\*\s*\w*)//;
      $type .= $1;
   }
   if ($vars =~ /::/) {
      $line = "$type, dimension ($dim), allocatable, $vars";
   } else {
      $line = "$type, dimension ($dim), allocatable :: $vars";
   }
   return $line
}


sub process_var($$$) {

   my $iline    = shift;
   my $label    = shift;
   my $line     = shift;

   my ($jline, $filename, $orgfilename) = currently_reading();

   my $idebug = 0;

   # VARIABLE DECLARATIONS
   # Interpret the variable type and convert to a variable type-struct
   my ($vartype, $rest) = parse_part_as_type($line, $vartypes);

   my (@attribs, @right);
   if ($rest =~ /^(.*)\:\:(.*)/) {

      # Modern declaration with :: : split into attributes and
      #                              the actual variables ($right)
      my ($a, $b) = ($1, $2);
      @attribs = map ((trim($_)), balsplit(",", $a));
      @right   = map ((trim($_)), balsplit(",", $b));
   } else {
      # Oldfashioned declaration without :: : split into only variables
      @attribs = ();
      @right =
        map ((&trim($_)), balsplit(",", $rest));
   }


   my @structs;
   foreach my $r (@right) {

      # Make copies of variable type properties.
      # These may be overruled for specific variables
      my @attribs_copy = @attribs;
      my $vartype_copy = $vartype;

      # Obtain the initialization part from the variable
      my ($rl, $rassign) = &balsplit("=", $r);

      # Obtain the character length from the variable (obviously,
      # only allowed in case of character variables
      my ($rll, $starpart) = &balsplit("*", $rl);
      if ($starpart) {

         # (Re)definition of character string length
         my_die("Incorrect variable declaration")
           unless $vartype->{base} eq "character";

         # Remove unnecessary brackets
         $starpart =~ s/^[ (]*//;
         $starpart =~ s/[ )]*$//;

         # Create a variable type with the correct string length
         my $star = 1;
         my ($len, $kind) = typing::parse_character_arguments($star, $starpart);
         $vartype_copy = typing::make_character_type($kind, $len);
         $vartype_copy->{'sub'} = $vartype->{'sub'};
      }

      # First part of the declaration (stuff before '=')
      # must be  $name ($dimension)
      $rll =~ /^ ($wordchar+) (\s* \(.*\))? \s* $/x
        or my_die("Invalid variable declaration `$rll'");

      my ($name, $dimension) = ($1, $2);
      push @attribs_copy, "dimension$dimension" if defined $dimension;

      # Interpret the assignment after the declaration
      my ($initop, $initial);
      if (defined $rassign) {
         # implicit lead =
         $rassign =~ /^ (>?) \s* (.*) $/x
           or my_die("Invalid variable initialization `= " . "$rassign'");
         ($initop, $initial) = ("=" . $1, $2);
      }

      # Put all the collected information in a struct
      if ($idebug>=1) { print "Making var '$name'\n";}
      my $struct = {
         'type'        => 'var',
         'name'        => $name,
         'vartype'     => $vartype_copy,
         'filename'    => $filename,
         'orgfilename' => $orgfilename,
         'function'    => 'no',
         'label'       => $label,
         hashed_comments()
      };

      # Add the attributes
      my @tempattribs;
      my $scalar = 1;
      foreach my $attrib (@attribs_copy) {
         if ($attrib =~ /^(?:public|private)$/i) {
            $attrib = lc $attrib;
            $struct->{'vis'} = $attrib;
         } elsif ($attrib =~ /^(?:optional|parameter|save|external|intrinsic)$/i) {
            $attrib = lc $attrib;
            $struct->{$attrib} = 1;
         } elsif ($attrib =~ /^dimension\s*\(/i) {
            push @tempattribs, $attrib;
            $scalar = 0;
         } elsif ($attrib) {
            push @tempattribs, $attrib;
         }
      }

      $struct->{'tempattribs'} = \@tempattribs;

      # Add the initializations
      if (defined $initial) {
         $struct->{'initop'}  = $initop;
         $struct->{'initial'} = parse_expr($initial);

         #warn "Variable $name initialized but no save (or parameter) declared\n"
         #   unless $struct->{save} || $struct->{parameter} || $initop eq '>';
      }

      # Add variable decription struct to the list of scalars if this
      # variable seems to be a scalar (it may still be a (statement)
      # function.
      push(@{$topnest->{scalars}}, $struct) if $scalar;

      # Put the new struct in the administration
      new_struct($struct);
      push @structs, $struct;
   }

   return ('var', @structs);
}


sub process_save($$$) {
   my $iline    = shift;
   my $label    = shift;
   my $detail1  = shift;

   my ($jline, $filename, $orgfilename) = currently_reading();

   my $varstring = lc($detail1);
   my @savars    = split(/\s*,\s*/, $varstring);
   my $found     = 0;
   foreach my $savar (@savars) {

      # Find variable
      foreach my $var (@{$topnest->{ocontains}}) {
         next if $var->{type} ne 'var';
         my $name = lc($var->{name});
         if ($name eq $savar) {
            $var->{save} = 1;
            $found = 1;
            last;
         }
      }

      if (not $found) {
         foreach my $common (keys(%{$topnest->{commons}})) {
            if ($savar =~ /\/\s*$common\s*\//i ) { $found = 1; last }
         }
      }
      my_die("Cannot find save variable or common " . "block '$savar'")
        unless $found;
   }

   my $struct = {
      type => "save",
   };

   return ('save', $struct);
}


sub process_parameter($$$) {
   my $iline    = shift;
   my $label    = shift;
   my $detail1  = shift;

   my ($jline, $filename, $orgfilename) = currently_reading();


   my $inistring = $detail1;
   my @initializers = split(/\s*,\s*/, $inistring);
   foreach my $ini (@initializers) {
      if ($ini =~ /(\w+)\s*=(>?)\s*(.+)/) {
         my $varname = lc($1);
         my $varrow  = $2;
         my $value   = $3;

         # Find variable
         my $found = 0;
         foreach my $var (@{$topnest->{ocontains}}) {
            next if $var->{type} ne 'var';
            my $name = lc($var->{name});
            if ($name eq $varname) {
               my_die("Variable $name: double initialization")
                 if $var->{initial};
               $var->{parameter} = 1;
               $var->{initop}    = "=$varrow";
               $var->{initial}   = parse_expr($value);
               $found            = 1;
               last;
            }
         }
         my_die("Cannot find parameter variable '$varname'")
           unless $found;
         next;
      }
      my_die("Initializer '$ini' not in format " . "<variable> = <value>");
   }
   my $struct = {
      type => "parameter",
   };
   return ('parameter', $struct);
}


sub process_data($$$) {
   my $iline    = shift;
   my $label    = shift;
   my $detail1  = shift;

   my ($jline, $filename, $orgfilename) = currently_reading();

   my $contents = $detail1;

   # Line below must be replaced with a call to hashed_comments.
   push (@{$topnest->{data}}, {
          contents => return_strings($contents),
          hashed_comments()});


   my $struct = {
      type => "data",
   };
   return ('data', $struct);
}

sub process_use($$$$) {
#
# Hier worden 3 dingen terug gegeven en hier moet dus nog even naar gekeken
# worden.
#

   my $iline    = shift;
   my $label    = shift;
   my $detail1  = shift;
   my $rest     = shift;

   # USE
   my_die("`use' found at top level")
     unless defined $topnest;
   my_die("`use' found in $topnest->{'type'} " . "$topnest->{'name'}")
     unless exists $topnest->{'uses'};

   my $extra = undef; $extra = $rest if $rest;
   my $module = $detail1;

   $extra =~ s/\ *,([^\ ])/,\ $1/g if $extra;
   $extra =~ s/\ \ +/\ /g          if $extra;
   push @{$topnest->{'uses'}}, [$module, $extra];

   my $struct = {
               'type'      => "use",
               'name'      => $module,
               'extra'     => $extra,
               hashed_comments()
   };

   new_struct($struct);
   return ('use', $struct);
}

sub process_common($$$$$) {
#
# Ik vermoed dat $name niet het goede is dat teruggegeven dient de worden
#
   my $iline    = shift;
   my $label    = shift;
   my $detail1  = shift;
   my $detail2  = shift;
   my $line     = shift;

   my ($jline, $filename, $orgfilename) = currently_reading();

   # COMMON

   # Retrieve the common block name and variables
   my $name = lc($detail1);
   my @vars = split_comma_sep_list($detail2, $line);

   # (Re)dimension the variables whose dimensions are
   # given in the common block definition
   foreach my $i (0 .. $#vars) {
      next unless $vars[$i];
      if ($vars[$i] =~ /(\w+) *(\(.*\))/) {

         # The variable has brackets: (re)dimension
         my $name = $1;
         my $dims = $2;

         redimension_var($name, $dims);
      }
   }

   # Check that the common block is not yet known
   my $commons = $topnest->{commons};
   my_die("Common block $name defined for the second time")
     if (exists($commons->{$name}));

#MARKER

   # Create the common block struct
   my $struct = {
      type        => "common",
      name        => $name,
      vars        => \@vars,
      filename    => $filename,
      orgfilename => $orgfilename,
      label       => $label,
      hashed_comments()
   };

   new_struct($struct);

   $commons->{$name} = $struct;

   # Return the results
   return ('common', $struct);
}


sub process_dimension($$$$) {
   my $iline    = shift;
   my $label    = shift;
   my $detail1  = shift;
   my $line     = shift;

   my ($jline, $filename, $orgfilename) = currently_reading();

   # DIMENSION

   # Retrieve dimensions declared
   my @vars = split_comma_sep_list($detail1, $line);

   # (Re)dimension all the variables mentioned
   my %comments = hashed_comments();
   foreach my $i (0 .. @vars) {
      if ($vars[$i] && ($vars[$i] =~ /(\w+) *(\(.*\))/)) {
         my $name = $1;
         my $dims = $2;

         redimension_var($name, $dims);
         add_comments_to_var($name,\%comments);
      }
   }

   my $struct = {
      type => "dimension",
   };
   return ('dimension', $struct);
}


sub process_external($$$) {

   my $iline    = shift;
   my $label    = shift;
   my $detail1  = shift;

   my ($jline, $filename, $orgfilename) = currently_reading();

   # EXTERNAL

   # Split the names of the external procedures
   my @names = split(/\s*,\s*/, trim($detail1));
   my $calls = $topnest->{calls};
   my $struct = {
      type => "external",
      name => '',
      calls => [],
   };

   my %comments = hashed_comments();
   foreach my $name (@names) {
      $calls->{$name} = {
          lines       => [],
          filename    => $filename,
          orgfilename => $orgfilename,
          args        => [],
          label       => $label,
          %comments
       }
       unless exists($calls->{$name});

       push(@{$struct->{calls}}, $name);

       push(@{$calls->{$name}->{lines}}, $iline);

       warn "$name called in include-file.\n" . "main file: " . main_file() .
            "\n" . "called in: $filename\n"
            if ($calls->{$name}->{filename} ne $filename);
   }

   return ('external', $struct);
}


sub process_implicit_none($$) {
   my $iline    = shift;
   my $label    = shift;

   my $struct = {
      name => "nn",
      type => "implicit none",
      hashed_comments()
   };
   new_struct($struct);

   # Recognize, but ignore implicit none
   return ('implicit none', $struct);
}

sub process_body($$$) {
#
# Hier moet echt nog e.e.a. aan gebeuren!!!
#
   my $iline    = shift;
   my $label    = shift;
   my $line     = shift;

   my ($jline, $filename, $orgfilename) = currently_reading();

   # Update first and last body line number
   if ($filename eq $topnest->{filename}) {
      if ( not $topnest->{bodystart} and  $line) {
         $topnest->{bodystart} = line_number('comment_start');
      }
      $topnest->{bodyend} = line_number('end');
   }

   # Make a list of possible function calls 'suspects'
   my $line_copy = $line;

   my %suspects;
   map { $suspects{$_} = 'unknown' } find_suspects($line);

   # Check whether it is one of the items contained in this subroutine/function
   foreach my $item (@{$topnest->{ocontains}}) {
      my $name = lc($item->{name});
      $suspects{$name} = $item->{type} if $suspects{$name};
   }

   # Check whether it is one of the items contained in this subroutine/function
   if (defined $topnest->{parent} and $topnest->{parent}->{type} eq "module") {
      foreach my $item (@{$topnest->{parent}->{ocontains}}) {
         my $name = lc($item->{name});
         if ($suspects{$name}) {
            next unless ($suspects{$name} eq 'unknown');
            $suspects{$name} = $item->{type};
         }
      }
   }

   # Check whether it's one of the built-in statements
   foreach my $name (@builtin_statements) {
      $suspects{$name} = 'builtin' if $suspects{$name} && $suspects{$name} eq 'unknown';
   }

   # Determine the module name (if any)
   my $modulename = '';
   if ($topnest->{type} eq 'module'){
      $modulename = $topnest->{name};
   }

   my $toppos = $topnest;
   while ($toppos->{parent}) {
      $toppos = $toppos->{parent};
      if ($toppos->{type} =~ /(?:module|subroutine|function|program)/) {
         $modulename .= ($modulename ? '::' : '') . $toppos->{name};
      }
   }

   # Check whether we already know what it is (from a previous run)
   my $parent_key = make_key($topnest->{type}, $topnest->{name}, $modulename);
   my $called_by  = calledBy($parent_key);
   my %suspect_source;
   foreach my $name (keys %suspects) {
      next unless ($suspects{$name} eq 'unknown' or $suspects{$name} eq 'var');

      # First, check whether we already know a call
      foreach my $called (@$called_by) {
         my ($t, $n) = split_key($called);
         if (($t eq 'interface' or $t eq 'function') and $n =~ /.*::$name\b/) {
            $suspects{$name}       = $t;
            $suspect_source{$name} = $called;
            last;
         }
      }

      # Then, check whether we know what it is
      my $found = tryToFindFunction($name);
      if ($found) {
         my ($t, $n) = split_key($found);
         if ($t eq 'interface' or $t eq 'function') {
            $suspects{$name}       = $t;
            $suspect_source{$name} = $found;
            last;
         }
      }
   }

   # If a variable is now found out to be a function (or interface),
   # change it from 'scalar' to 'function'
   my $i = 0;
   while ($topnest->{scalars} and $i < @{$topnest->{scalars}}) {
      my $var  = ${$topnest->{scalars}}[$i];
      my $name = lc($var->{name});
      if ($suspects{$name} and $suspects{$name} ne 'variable') {
         splice(@{$topnest->{scalars}}, $i, 1);
         if ($suspects{$name} and $suspects{$name} =~ /(?:unknown|function|interface)/i) {
            $var->{function} = 'yes';
            push(@{$topnest->{functions}}, $var);
            $suspects{$name} = "function";
         }
      }
      $i++;
   }

   # For each function used in this subroutine,
   # check if it is a statement function.
   foreach my $var (@{$topnest->{functions}}) {
      my $name = $var->{name};

      if ($line =~ /^$name\s*(\(.*\))\s*=\s*{^=](.*)/i) {

         # It is indeed a statement function
         $var->{function} = 'statement function';
         last;
      }
   }

   # For each function used in this subroutine,
   # check if it called in this line
   foreach my $var (@{$topnest->{functions}}) {
      my $name      = $var->{name};
      my $line_copy = $line;

      # The loop below is necessary because the same function
      # may be called multiple times in one line
      while ($line_copy =~ /\b$name\s*(\(.*)/i) {

         # Remove everything until the argument list
         # (The bracket after the function name remains)
         $line_copy = $1;

         # Retrieve the arguments from the rest of the line
         # (It starts with a bracket)
         my @args = get_args_from_line($line_copy, $line);

         # Now store the call
         my $calls = $topnest->{calls};
         $calls->{$name} = {
                            type        => $var->{function},
                            var         => $var,
                            lines       => [],
                            filename    => $filename,
                            orgfilename => $orgfilename,
                            args        => []
                           }
           unless exists($calls->{$name});
         push(@{$calls->{$name}->{lines}}, $iline);
         push(@{$calls->{$name}->{args}},  \@args);
      }
   }

   # Make (tentative) function calls out of the suspects remaining
   foreach my $name (keys %suspects) {
      next unless $suspects{$name} =~ /(?:unknown|function|interface)/i;

      # Generate comments to indicate the source
      my $comments = '';
      my $source   = '';
      my $guessed  = 1;
      if ($suspect_source{$name}) {
         my $module = $suspect_source{$name};
         $module =~ s/(?:.+)\/\/(.+)::(?:.+)/$1/g;
         $guessed = 0;
      } else {

         # Check 'only' statements
         foreach my $use (@{$topnest->{uses}}) {
            my $module = "";
            my $only   = "";
            foreach my $part (@{$use}) {
               last unless ($part);

               if ($module) {
                  $source   = 'only';
                  $comments = "from module $module"
                    if ($part && ($name =~ /\b$part\b/i));
                  last;
               } else {
                  $module = $part;
                  $comments .= ($comments ? ', ' : '') . $module;
                  $source = ($source ? 'uses' : 'use');
               }
            }
            last if $source;
         }
      }
      $comments .= " ($source)" if $source;
      $comments = "from module " . $comments if ($source eq 'use');
      $comments = "from one of the following modules: " . $comments
        if ($source eq 'uses');

      # Put all the collected information in a struct
      my $calls = $topnest->{calls};
      $calls->{$name} = {
        'type' => $suspect_source{$name} ? 'yes' : 'possible function',
        'name' => $name,
        'filename'         => $filename,
        'orgfilename'      => $orgfilename,
        'function'         => 'yes',
        'firstline'        => $iline,
        'lastline'         => $iline,
        'comments'         => $comments,
        'guessed_comments' => $guessed,
        'uses'             => [],
        'args'             => []
      } unless exists($calls->{$name});

      push(@{$calls->{$name}->{lines}}, $iline);
   }
   return ('?',{ name => 'nn', type => 'body', 'line' => $line});
}


sub process_call($$$$$) {
#
# Array moet een struct worden
#
   my $iline    = shift;
   my $label    = shift;
   my $detail1  = shift;
   my $detail2  = shift;
   my $line     = shift;

   my ($jline, $filename, $orgfilename) = currently_reading();

   process_body($iline,$label,$line);

   # CALL or IF (...) CALL [hack--xxx]
   my_die("`call' found at top level")
     unless defined $topnest;
   my_die("`call' found in $topnest->{'type'} " . "$topnest->{'name'}")
     unless exists $topnest->{'calls'};

   my $name = $detail1;
   my @args = ();
   @args = split_comma_sep_list($detail2, $line) if defined $detail2;

   # Ignore calls to built-in subroutines
   return ('?', $line) if grep(/\b$name\b/i, @builtin_statements);

   my $calls = $topnest->{calls};
   $calls->{$name} = {
      type        => 'subroutine',
      comments    => '',
      lines       => [],
      filename    => $filename,
      orgfilename => $orgfilename,
      args        => []
   } unless exists($calls->{$name});

   $calls->{$name}->{type} = 'subroutine';
   push(@{$calls->{$name}->{lines}}, $iline);
   push(@{$calls->{$name}->{args}},  \@args);

   return('call', { name=>'nn', type => 'call'} );
}


sub classify_line($) {
   my $line = shift;

   if ($line =~ /^module\s+procedure\s+(\w.*)$/i) {
      return( 'mprocedure', \&process_module_procedure, $1);
   }

   if ($line =~ /^(module|program)(?:\s+(\w+))?$/i) {
      return ( lc($1), \&process_module_or_program, $1, $2);
   }

   my $may_be_ended = 'module|subroutine|function|program|type|interface|structure|block\s*data';
   if ($line =~ /^end\s*(?:($may_be_ended)(?:\s+($wordchar+))?)?\s*$/i) {
      return('end',\&process_end, $1, $2, $line);
   }

   # Regular expression for function or subroutine declaration
   my $rout_regexp = '^' .                   # start-of-line
     '(?:(.+?)\s+)?' .                       # $1: optional: data type of
                                             # function
     '(subroutine|function)' .               # $2: 'subroutine' or 'function'
     '\s+(' . $wordchar . '+)\s*' .          # $3: function/routine name
     '(\([^()]*\))?' .                       # $4: optional: arguments (stuff
                                             # between brackets)
     '(?:\s*result\s*\(\s*(\w+)\s*\))?' .    # $5: result ($result)
     '$';                                    # end-of-line
   if ($line =~ /$rout_regexp/i) {
      return(lc($2), \&process_routine_or_function, $1, $2, $3, $4, $5);
   }

   if ($line =~ /^type(?:\s+|\s*(,.*)?::\s*)(\w+)$/i) {
      return('type', \&process_type, $1, $2);
   }

   if ($line =~ /^structure\s*\/(.+)\/\s*$/i) {
      return('type', \&process_structure, $1);
   }

   if ($line =~ /^block\s*data\s*(\w*)/i) {
      return('block data', \&process_block_data,$1);
   }

   if ($line =~ /^interface(?:\s+(\S.+))?$/i) {
      return('interface',\&process_interface,$1);
   }

   if ($line =~ /^contains$/i) {
      return('contains',\&process_contains);
   }

   if ($line =~ /^(public|private|sequence)(?=\s+[^=(]|::|$)(\s*::\s*)?/i) {
      return (lc $1, \&process_public_private_or_sequence, $1, $');
   }

   if ($line =~ /^optional(\s+|\s*::\s*)((\w|\s|,)+)$/i) {
      return('optional',\&process_optional,$1,$2);
   }

   # Replace RECORD /name/ - declaration by
   #         TYPE(name)    - declaration
   $line =~ s/^record\s*\/(.*)\//type($1)/i;

   # Replace '[ALLOCATABLE] (:)' by 'dimension (:), allocatable ::'
   if ($line =~ /^($vartypes)(.*)\[ALLOCATABLE\] *\(([\s:,]*)\) *$/i) {
      $line = rephrase_allocatable($1, $2, $3);
   }

   if ($line =~ /^($vartypes)\s*(\(|\s\w|[:,*])/i) {
      return('var',\&process_var,$line);
   }

   if ($line =~ /^save(?:\s*::\s*|\s+)(.+)/i) {
      return ('save', \&process_save,$1);
   }

   if ($line =~ /^parameter\s*\((.+)\)/i) {
      return('parameter',\&process_parameter,$1);
   }

   if ($line =~ /^data\s*(.*\/.+\/.*)$/i) {
      return('data',\&process_data,$1);
   }

   if ($line =~ /^use\s+(\w+)($|,\s*)/i) {
      return('use',\&process_use,$1,$');
   }

   if ($line =~ /^common\s*\/\s*(\w+)\s*\/\s*(\w.*)\s*$/i) {
      return('common',\&process_common,$1,$2,$line);
   }

   if ($line =~ /^dimension\s*(.*)\s*$/i) {
      return('dimension',\&process_dimension,$1,$line);
   }

   if ($line =~ /^external\s+(\w.*)$/i) {
      return('external',\&process_external,$1);
   }

   if ($line =~ /^implicit\s*none/i) {
      return ('implicit none', \&process_implicit_none);
   }

   # Until here, the lines interpreted were part of the routine header.
   # From here on, the lines are part of the body.
   if ($line =~ /^(?:if\s*\(.*\)\s*)?call\s+(\w+)\s*(?:\(\s*(.*?)\s*\))?$/i) {
      return('call',\&process_call,$1,$2,$line);
   }

   # Unrecognized statement
   return ('?', \&process_body, $line);
}

sub read_stmt ($$) {

=head2 ($stmt, @results) = read_stmt ($prev_stmt, \%prev_stmt)

  Reads a Fortran 90 statement from the current input.
  Checks for proper nesting, etc., and keeps tracks of what's in what.

  OUTPUT VARIABLES:
     Possible values for @results:
     ("",              "")             when the Fortran file is done
     ('?',             $the_line)
     ('program',       \%structure)
     ('endprogram',    \%structure)
     ('module',        \%structure)
     ('endmodule',     \%structure)
     ('subroutine',    \%structure)
     ('endsubroutine', \%structure)
     ('function',      \%structure)
     ('endfunction',   \%structure)
     ('program',       \%structure)
     ('endprogram',    \%structure)
     ('type',          \%structure)
     ('endtype',       \%structure)
     ('interface',     \%structure)
     ('endinterface',  \%structure)
     ('var',           \%struct1, \%struct2, ...)
     ('contains',      \%parent)
     ('mprocedure', $name1, $name2, ...)
     ('public',     $name1, $name2, ...)        empty means global default
     ('private',    $name1, $name2, ...)        empty means global default
     ('optional',   $name1, $name2, ...)
     ('call', $arg1, $arg2, ...)              currently args are unparsed

=cut

   my $prev_stmt = shift;
   my $prev_struct = shift;

   my $idebug = 0;

   # Read the new line; return empty outputs when file is done
   my ($line, $iline, $label) = read_line();


   # Return empty outputs when file is done
   if (!$line) {
      my_die("File ended while still nested") if @nesting;
      return ("", "");
   }

   # Interpret the line in order to see how it must be processed
   my ($type,$process_sub,@details) = classify_line($line);


   if (ref $prev_struct
       and ($prev_stmt eq 'module'   or $prev_stmt eq 'subroutine' or
            $prev_stmt eq 'function' or $prev_stmt eq 'program')
      ) {
   # The line that has been just read, is the first statement of a
   #   module, subroutine, function or program.
   # Therefore, the comments which have been collected before this
   # statement may well refer to the module, subroutine, function or
   # program and not to whatever it is in this first statemet.

      $prev_struct->{collected_comments} = []
         if (not exists($prev_struct->{collected_comments}));

      my $com = after_comments($type);
      push(@{$prev_struct->{collected_comments}}, @$com);
   }

   if ($idebug>2)
   {
      print "\t*********************\n";
      print "\tLINE    : '$line'\n";
      print "\tTYPE    : '$type'\n";
      foreach my $item(@details)
      {
         print"\tDETAILS : '$item'\n" if $item;
      }
      print "\t*********************\n";
   }

   # Process the line
   my ($stmt,$struct) =  &$process_sub($iline,$label,@details);

   # Clear the comments
   reset_comments();

   return ($stmt,$struct);
}


#----------------------------------------------------------------------
sub split_parameters($)
{

=head2 @parms = split_parmaters($parmstr)

     return the individual parameter names

     INPUT VARIABLES
       $parmstr - string which has all the parameter names,
                  separated by commas and enclosed by brackets.
     OUTPUT VARIABLES
       @parms   - names of individual parameters

=cut

   my $parmstr = shift;
   my @parms;

   # Remove brackets from parameters
   $parmstr = trim(substr($parmstr, 1, length($parmstr) - 2));

   if ($parmstr) {
      @parms = split(/\s*,\s*/, $parmstr);
      my ($parm);
      foreach $parm (@parms) {
         my_die("Parameter `$parm' is not just a word or *")
           unless $parm =~ /^\w+|\*$/;
         ## * as a final argument allows the calling to specify a
         ## statement to jump as an alternative return address.
         ## (Legacy Fortran!)
         ## Thanks to Art Olin for this info.
      }
   }
   return @parms;
}


#----------------------------------------------------------------------
sub fix_module_end()
{

=head2 fix_module_end ()

 We do some special "fixing up" for modules, which resolves named
 references (module procedures) and computes publicity.

 Note that end_nest will ensure that the type of thing ended matches
 the thing the user says it is ending, so we don't have to worry about
 that.

=cut

   my $top = $topnest;

   # Set publicity (visibility) of objects within the module.

   # First, the explicitly set ones.
   foreach my $name (@{$top->{'publiclist'}}) {
      do_attrib($name, "vis", 'public', "visibility");
   }
   foreach my $name (@{$top->{'privatelist'}}) {
      do_attrib($name, "vis", 'private', "visibility");
   }

   # Second, the globally set ones (those obeying the default).
   $top->{'defaultvis'} = "public" unless exists $top->{'defaultvis'};
   foreach my $obj (@{$top->{'ocontains'}}) {
      $obj->{'vis'} = $top->{'defaultvis'} unless exists $obj->{'vis'};
   }

   # Traverse (arbitrarily deeply) nested structures.
   sub traverse
   {
      my $node = shift;
      my $top  = $topnest;

      # Graduate nested MODULE PROCEDURE (mprocedure) to point to the
      # appropriate thing (either a function or a subroutine with that
      # name).
      if ($node->{'type'} eq "mprocedure") {
         my_die("Couldn't find module procedure $node->{'name'} " .
                "(nothing with that name in module $top->{'name'})")
                unless exists $top->{'contains'}->{lc $node->{'name'}};

         my ($possibles) = $top->{'contains'}->{lc $node->{'name'}};
         my_die("Couldn't find module procedure $node->{'name'} " .
                "in module $top->{'name'} (wrong type)")
                unless (   exists $possibles->{'subroutine'}
                        or exists $possibles->{'function'});

         my_die( "Found both a subroutine and function to match " .
                 "module procedure $node->{'name'} in module $top->{'name'}")
                if (    exists $possibles->{'subroutine'}
                    and exists $possibles->{'function'});

         if (exists $possibles->{'subroutine'}) {
            $node->{'bind'} = $possibles->{'subroutine'};
         } else {
            $node->{'bind'} = $possibles->{'function'};
         }
      }

      # Recurse.
      map { traverse($_) } @{$node->{'ocontains'}}
        if exists $node->{'ocontains'};
   }
   map { traverse($_) } @{$top->{'ocontains'}};
}

#------------------------------------------------------------------------
sub new_struct ($)
{

=head2 new_struct(\%struct);

  Makes note of a new structure.  Called by new_nest, for example.

  INPUT VARIABLES
     %struct - a hash describing a new structure

=cut

   my $struct = shift;

   my_die("Basic structure must be found at a nesting level")
     unless defined $topnest;

   my $type = $struct->{'type'};
   my $name = lc($struct->{'name'});
   if (exists($topnest->{'contains'}->{$name})) {
      # the parent object already has a structure of this name:
      if ($type eq "use" and exists($topnest->{'contains'}->{$name}->{$type})) {
      # You may repeat a use statement if you specify 'only:' each time.

         my $oldstruct = $topnest->{'contains'}->{$name}->{$type};
         if (not $oldstruct->{extra} or not $struct->{extra}) {
            $oldstruct->{extra} = undef;
         } else {
            my $isok = 1;
            my $only1; my $only2;
            if ($struct->{extra} =~ /^ *only *: *(.*)/i) {
               $only1 = $1;
            } else { $isok = 0;}
            if ($oldstruct->{extra} =~ /^ *only *: *(.*)/i) {
               $only2 = $1;
            } else { $isok = 0;}

            if (not $isok) {
              my_die("Redefinition of 'use' '$struct->{name}' is only OK " .
                     "if you have 'only:' specified in all use-statements");
            } else {
               $oldstruct->{extra} = "only: " . join(',',$only1,$only2);
            }
         }
      } else {
         # Check that the existing structure has a different type
            my_die("Redefinition of $type $struct->{'name'} in " .
                   "$topnest->{'type'} $topnest->{'name'}")
                   if exists($topnest->{'contains'}->{$name}->{$type});

         # Add the new structure to the contains-part of the parent
         # object
         $topnest->{'contains'}->{$name}->{$type} = $struct;
      }
   } else {
      # Structure name is new:
      # Add the new structure to the contains-part of the parent
      # object
      $topnest->{'contains'}->{$name} = {$type => $struct};
   }

   # Also, add the new structure to the 'ocontains' part of the
   # parent object
   push @{$topnest->{'ocontains'}}, $struct;

   # Administrate what the new struct belongs to
   $struct->{'within'} = $topnest;
}

#------------------------------------------------------------------------
sub new_nest
{

=head2 ($type, \%struct) = new_nest(\%struct)

  Starts a new nesting level represented by the given structure.

  INPUT/OUTPUT VARIABLES
      %struct - structure describing the new nesting level. This
                hash must define the 'type' and 'name' entries.
                You should not define the 'contains' or 'defaultvis'
                entry.
                On exit, a lot more fields are filled

  OUTPUT VARIABLES
      $type   - type of the structure (e.g. 'program')

=cut

   my $struct = shift;

   my ($type) = $struct->{'type'};

   $struct->{'contains'}  = {};
   $struct->{'ocontains'} = [];

   # Program unit
   if (   $type eq "subroutine" or $type eq "function"
       or $type eq "module"     or $type eq "program") {
      $struct->{'incontains'} = 0;
      $struct->{'uses'}       = [];
      $struct->{'interface'}  = 0
        if $type eq "subroutine" || $type eq "function";
   }

   # Program unit with code
   if (   $type eq "subroutine" or $type eq "function"
       or $type eq "program") {

      # Initialize lists of called subroutines and common blocks
      $struct->{'calls'}   = {};
      $struct->{'commons'} = {};
   }

   # Check whether current structure is part of an interface
   if (defined $topnest) {
      $struct->{'parent'} = $topnest;

      my $toptype = $topnest->{'type'};
      if ( $toptype eq "interface"
          and (   $struct->{'type'} eq "subroutine"
               or $struct->{'type'} eq "function")  ) {

         # The function or subroutine is part of the interface
         $struct->{'interface'} = 1;
      } else {
         my_die("Nesting in $toptype not allowed")
           unless $toptype eq "subroutine" or $toptype eq "function"
               or $toptype eq "module"     or $toptype eq "program";
      }

      # Administrate the structure unless it is nameless
      new_struct($struct)
        unless $struct->{'name'} eq "";
   }

   # Administrate the new structure in nesting administration
   push @nesting, $struct;

   $nesting_by{$type} = [] unless (exists($nesting_by{$type}));
   push @{$nesting_by{$type}}, $struct;

   $topnest = $struct;
   my_die('ik kap') if ($struct->{name} eq 'LACTIV');
   return ($type, $struct);
}

#####
# Ends the current nesting level.  Optionally, you can pass the 'type' that
# it's supposed to be as the first argument.  Optionally, you can pass the
# 'name' it should have after that (as the second argument).
#####
#------------------------------------------------------------------------
sub end_nest
{
   my ($type, $name) = @_;
   $type = lc $type if defined $type;
   unless (defined $topnest) {
      if (defined $name && defined $type) {
         my_die("Ended $type $name at top level");
      } elsif (defined $type) {
         my_die("Ended unnamed $type at top level");
      } else {
         my_die("END statement at top level");
      }
   }
   my ($struct) = pop @nesting;
   my_die("Ended $type while in " . "$struct->{'type'} $struct->{'name'}")
     if defined $type && $type ne $struct->{'type'};
   my_die("Ended $name while in " . "$struct->{'type'} $struct->{'name'}")
     if defined $name && $name !~ /^\Q$struct->{'name'}\E$/i;
   if (@nesting) {
      $topnest = $nesting[$#nesting];
   } else {
      $topnest = undef;
   }
   pop @{$nesting_by{$struct->{'type'}}};
   return ("end" . (defined $type ? $type : ''), $struct);
}

#------------------------------------------------------------------------
sub parse_part_as_type ($$)
{

=head2 ($vartype, $rest) = parse_part_as_type ($str,$vartypes);

  Parses the basic type that prefixes the given string.

  INPUT VARIABLES
       $str     - a line of input, with variable declarations
  OUTOUT VARIABLES
       $vartype - parsed type
       $rest    - string portion remaining

=cut

   my $str      = shift;
   my $vartypes = shift;

   # Get the basic variable type from the line
   $str =~ /^$vartypes/i
     or my_die("Invalid input `$str'");
   my ($base, $rest) = ($&, $');

   my $level = 0;

   # Wait till we are outside of all parentheses and see a letter, colon,
   #   or comma.
   # The construction below is new for me. It does not loop as long
   # as $rest has any of the characters in it: this would be forever
   # because $rest is not changed. Matching using m//g is apparently
   # intended for while loops to process all occurrences.
   # It is a very complicated affair, but it seems to work flawlessly.
   while ($rest =~ /[()_:,$letterchar]/g) {
      if ($& eq '(') {
         $level++;
      } elsif ($& eq ')') {
         $level--;
         my_die("Unbalanced parentheses (too many )'s)")
           if $level < 0;
      } elsif ($level == 0) {
         return (parse_type("$base$`", $vartypes), "$&$'");
      }
   }

   my_die("Couldn't split into type and rest for `$str'");

}

#------------------------------------------------------------------------
sub parse_type ($$)
{

=head2 $base = parse_type ($str,$vartypes)

  Parses a basic type, creating a type structure for it:
      integer [( [kind=] kind_val )]
      real [( [kind=] kind_val )]
      double precision                  (no kind is allowed)
      complex [( [kind=] kind_val )]
      character [( char_stuff )]
      logical [( [kind=] kind_val )]
      type (type_name)

  integer*number, real*number, complex*number, and logical*number are also
  supported as nonstandard Fortran extensions for kind specification.
  "number" can either be a direct integer or an expression in parentheses.

  char_stuff is empty or (stuff), where stuff is one of:
      len_val [, [kind=] kind_val]
      kind=kind_val [, [len=] len_val]
      len=len_val [, kind=kind_val]
  kind_val and len_val are expressions; len_val can also be just `*'.

  The length can also be specified using the nonstandard Fortran extension
  character*number.  If number is `*', it must be in parentheses (indeed,
  any expression other than a number must be in parentheses).

=cut

   my $str      = shift;
   my $vartypes = shift;

   # print "Parsing type: $str\n";

   my $reg_args = '(?:' . '\((.*)\)' . '|' .    # $1: type = $base ($1)
     '\*\s*(\d+|\(.*\))' .                      # $2: type = $base*$2, with $2 a number
                                                # $3: type = $base*($3)
     ')';

   # Split the string into a base-type and arguments
   $str = trim($str);
   $str =~ /^($vartypes)\s*$reg_args?$/i
     or my_die("Invalid type `$str'");

   my $base = lc $1;
   my $star = defined $3;
   my $args = trim($star ? $3 : $2);
   $base =~ s/ //g;

   # Return default type if the type is not specified
   unless ($args) {
      my_die("type without (type-name) after it")
        if $base eq 'type';

      my_die("No default type for `$base'")
        unless exists $typing::default_type{$base};

      return $typing::default_type{$base};
   }

   # double precision: arguments not allowed
   my_die("double precision cannot have kind specification")
     if ($base eq 'doubleprecision');

   # Return type for type-declarations
   if ($base eq 'type') {
      my_die("type$args invalid--use type($args)") if $star;
      my_die("type(w) for non-word w")
        unless $args =~ /^$wordchar+$/;
      return typing::make_type($base, $args);
   }

   # Return type for all but character declarations
   if ($base ne 'character') {
      my $kind = 0;
      $kind = ($args =~ s/^kind\s*=\s*//i) unless $star;
      return typing::make_type($base, parse_expr($args), 0, $star, $kind);
   }

   my ($len, $kind) = typing::parse_character_arguments($star, $args);

   return typing::make_character_type($kind, $len, $star);
}

#------------------------------------------------------------------------
sub do_attrib($$$$)
{

=head2 do_attrib($name, $attrib, $val, $attribname);

   Change the attributes for all structs that belong to $name

   INPUT ARGUMENTS
      $name   - name of the variable (?)
      $attrib - the attribute: 'vis' or 'optional'
      $val    - the value of the attribute (1 for 'optional' and
                'public'/'private' for 'vis'
      $attribname- a longer version of $attrib: 'visibility' or
                'optional attribute'

=cut

   my $name       = shift;
   my $attrib     = shift;
   my $val        = shift;
   my $attribname = shift;

   my ($struct);
   foreach $struct (values %{$topnest->{'contains'}->{lc $name}}) {
      my_die("Redefining $attribname of $struct->{'type'} " .
             "$name from $struct->{$attrib} to $val")
             if exists $struct->{$attrib};
      $struct->{$attrib} = $val;
   }
}

#------------------------------------------------------------------------
sub split_comma_sep_list($$)
{

=head2 @list = split_comma_sep_list($csl,$line)

  Split a comma separated list, taking into account that
  commas may also occur inside brackets

  INPUT VARIABLES
    $csl  - comma separated list
    $line - the line that the $csl was taken from
  OUTPUT VARIABLES
    @list items in the $csl

=cut

   my $csl  = shift;
   my $line = shift;
   my @list = get_args_from_line("($csl)", $line, 1);

   return @list;
}

#------------------------------------------------------------------------
sub get_args_from_line($$;$)
{

=head2 @list = get_args_from_line($args,$line,[$match_all])

  Split the comma separated list at the start of the line, taking into
  account that commas may also occur inside brackets

  INPUT VARIABLES
    $args      - line fragment that starts with a comma separated
                 list between brackets
    $line      - the line from which $args was taken
    $match_all - the comma separated list must be the only thing
                 in $args

  OUTPUT VARIABLES
    @list  items in the comma separated list

=cut

   my $args      = shift;
   my $line      = shift;
   my $match_all = shift;
   my @list;

   # Replace bracketed expressions () by {<n>} and
   # remember the contents
   my @brackets;
   my $nbrack = 0;
   while ($args =~ s/(\([^\(\)]*\))/{$nbrack}/) {
      push @brackets, $1;
      $nbrack++;
   }

   # The arguments are the first part of the line fragment
   if ($args =~ /^\{([0-9]*)\}\s*(.*)/) {
      $args = $brackets[$1];

      my_die("Stuff '$2' after arguments")
         if (defined $match_all and $2 ne '');

   } else {
      my_die("Cannot understand line");
   }

   # Remove the remaining brackets at the start and end of the argument
   # list
   $args =~ s/^ *\(//;
   $args =~ s/\) *$//;

   # Now split the list (no more commas in the brackets)
   @list = split(/\s*,\s*/, $args);

   # Replace the coded bracket contents by the original
   # contents
   foreach my $i (0 .. @list) {
      while ($list[$i] && $list[$i] =~ /\{([0-9]*)\}/) {
         my $j = $1;
         $list[$i] =~ s/\{[0-9]*\}/$brackets[$j]/;
         $list[$i] =~ s/  */ /g;
      }
   }

   foreach my $i (0 .. @list) {
      my $listi = $list[$i];
      next unless ($listi && $listi =~ /'([0-9]*)'/);

      my $ok = '';

      while ($listi =~ /([^']*)'([0-9]*)'(.*)/) {
         $ok .= $1 . get_string($2);
         $listi = $3;
      }
      $list[$i] = $ok . $listi;
   }
   return @list;
}

#------------------------------------------------------------------------
sub add_comments_to_var($$)
{

=head2 add_comments_to_var($name,$hashed_comments)

   Add extra information to the comments of a variable

   INPUT VARIABLES
     $name            - name of the variable
     $hashed_comments - comments to be added

=cut

   my $name = shift; $name = lc($name);
   my $hashed_comments = shift;

   my @collected_comments = @{$hashed_comments->{collected_comments}};

   my $var = $topnest->{contains}->{$name}->{var};

   my_die("Adding comments to unknown variable $name")
     unless ref($var);

   push(@{$var->{collected_comments}}, @collected_comments);
}
#------------------------------------------------------------------------
sub redimension_var($$)
{

=head2 redimension_var($name,$dims)

   change the dimension of a variable
   INPUT VARIABLES
     $name - name of the variable
     $dims - new dimension of the variable

=cut

   my $name = shift; $name = lc($name);
   my $dims = shift;

   my $var = $topnest->{contains}->{$name}->{var};
   my_die("Dimensioning unknown variable $name")
     unless ref($var);

   # Check: it must not yet have a dimension
   foreach my $attrib (@{$var->{tempattribs}}) {
      my_die("Redimensioning $name")
        if ($attrib =~ /dimension/i);
   }

   # Add the correct dimension to the attributes
   push(@{$var->{tempattribs}}, "dimension $dims");

   # Remove the variable from the list of scalars
   foreach my $j (0 .. @{$topnest->{scalars}}) {
      if (${$topnest->{scalars}}[$j]->{name} =~ /^ *$name *$/i) {
         splice(@{$topnest->{scalars}}, $j, 1);
         last;
      }
   }
}

sub clean_path($)
{

=head2 $pout = clean_path($pin)

  Tries to remove relative parts from path names to
  make pathnames pretty to the reader.

  INPUT VARIABLES
     $pin  - path name to clean

  OUTPUT VARIABLES
     $pout - path name cleaned

=cut

   return( File::Spec->abs2rel(abs_path(shift )));
}

1;
