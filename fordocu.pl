# Copyright (C) 2009-2010  Planbureau voor de Leefomgeving (PBL)
#
# full notice can be found in LICENSE

#!/usr/bin/env perl

# Start the script under PERL if it was started under any other kind of shell
eval 'exec perl $0 ${1+"$@"}'
  if 0;

=head1 PROGRAM fordocu
 This is the main function of fordocu.

=head1 CONTAINS

=cut

require 5.003;
use warnings;
use strict;

# Enable the next line for dprofpp profiling (wherever Devel::Profiler is installed)
#use Devel::Profiler package_filter => sub{return 0 if $_[0] =~ /^XML/; return 1; };

use FindBin ('$RealBin');
use File::DosGlob 'glob';
use File::Path('mkpath');
use lib $RealBin;
use Cwd ('getcwd');
use f90fileio ('reset_comments','clear_pseudocode', 'guessed_format',
              'fixed_fortran', 'set_fileiooption');
use stmts ('read_file','set_stmtsoption', 'print_stmt');
use tree2html ('write_treelog', 'close_treelog', 'set_treeoption',
               'prepareTrees');
use add_info_to_stmt ('set_add_info_to_stmt_option');
use htmling ('toplevel2html', 'set_htmloption', 'externals_to_htmldir',
             'clear_html_path');
use mkheader ('toplevel2header', 'delayed_write', 'set_headeroption',
              'clear_mkheader_path');
use dictionary ('handle_comments', 'readComments', 'writeComments');
use utils ('my_die', 'remove_files');

#--------------------------------------------------------------
# Module-level variables
my $dump_pseudocode = 0;
my $pseudo_path     = 'pseudocode';
my $errwarndir      = './';
my $tabsOK          = 0;
#--------------------------------------------------------------
sub print_usage() {

=head2 print_usage

  Print the usage of the script to the screen

=cut

   print <<END

Usage: fordocu [options] [--] path/file.f90 ...

Description: Generates HTML files corresponding to each module in the listed
   files, and stores them in the current directory.

Options:
         -fixed: fixed form style (like Fortran 77) \ these apply to all
         -free:  free form style (new to Fortran 90) / future files only
         -1:     consider ! to be !!
         -cp:    comments are considered to be preformatted (default)
         -cs:    comments are considered to be formatted "smartly"
         -ch:    comments are considered to be HTML
         -eol:   only accept end-of-line comments for variable declarations
         -nir:   hides the routines of an interface in the documentation
         -nic:   do not add interface 'calls' to the call tree
         -hide <name>: hide <name> in the call tree (including everything in it)
         -I <path>: colon-separated input path

         -g<flags>: generate graphviz input in addition to documentation
                    the <flags> can be combined, directly after the -g
                       c: include container information in the output (e.g. -gc)
                       j: join arrows that share a common end node

         -h<flags>: generate headers in addition to documentation
                     the <flags> can be combined, directly after the -h
                        !: generate headers, but no documentation (e.g. -hvU\$ad)
                        s: split files containing multiple program units
                        \$: all variable comments will be end-of-line
                        k: all numeric variable types are of form (kind=n)
                        a: all numeric variable types are of form *n
                        U: reserved words in variable declarations to upper case
                        v: try to vertically align variable declarations
                        d: restrict the dimension word to pointer or allocatable
                        1: suppress !!-marked comments in the generated code
                        m: do not indent MODULE, PROGRAM, SUBROUTINE and FUNCTION

         -pseudo: generate separate files containing any marked pseudo code;
                  the pseudo code consists of comments marked with \@p

         -O <dir>: documentation output directory name (default: html)
         -H <dir>: header output directory name (default: header)
         -P <dir>: pseudo code output directory name (default: pseudocode)
         -keepL    keeps generated ouotput from previous runs

Note: Files are only affected by options listed before them.

END

   #disabled: -o <filename>: override documentation filename for next input file
}


sub do_dump_pseudocode($$) {

=head2 do_dump_pseudocode($file, $code)

   Write pseudo code found to the given file.

 INPUT VARIABLES

   $file - file to write the pseudocode to
   $code - pseudocode

=cut

   my $file = shift;
   my $code = shift;

   # Ensure $pseudo_path exists
   if ($pseudo_path) {
      mkpath($pseudo_path) unless ( -w $pseudo_path );
      $pseudo_path =~ s/([^\\\/])$/$1\//;
   }

   # Alter filename
   $file .= '.pseudocode';

   # Write pseudo code
   print "Generating $file...\n";
   $file = $pseudo_path . $file;
   open PSC, ">$file"
     or my_die("cannot open file '$file' for writing");

   print PSC $code;
   close PSC;
}

#--------------------------------------------------------------
sub process_file($$$) {

=head2 process_file($infile,$outfile,$runs_to_do);

 Create the HTML-file $outfile with documentation about Fortran
 file $infile.

 INPUT VARIABLES

   $infile   name of the input file
   $outfile  name of the output file

=cut

   my $infile = shift;
   my $outfile = shift;
   my $runs_to_do = shift;

   print STDERR "Processing $infile...\n";

   # Compare the user-specified format ('free' or 'fixed') to what
   # fordocu can guess.
   (my $guessformat, my $ifree, my $free_line) = guessed_format($infile);
   my $specformat  = 'free'; $specformat = 'fixed' if fixed_fortran();
   if ( $specformat ne $guessformat) {
      if ( $guessformat ne 'fixed') {
         if ($free_line =~ /\s*\t/ and not $tabsOK ) {
           my_die("Tabs are used in line $ifree of fixed format file '$infile'." ,
                  'WARNING');
         } else {
            my_die("Option -fixed given, but I think file '$infile' is " .
                       "in $guessformat format\n","WARNING");
            # "The offending line was line $ifree:\n$free_line",'WARNING');
         }
      } elsif ($guessformat ne 'free') {
         my_die("Option -free given, but I think file '$infile' is " .
                       "in $guessformat format",'WARNING');
      }
   }

   reset_comments();
   clear_pseudocode();

   # Process all the top-level program units in the input file
   foreach my $top ( read_file( $infile ) ) {

      # Print a line for tree2html
      write_treelog( "FILE $top->{fullpath} CONTAINS "
                              . uc( $top->{type} )
                              . " $top->{name}\n" );

      # Handle comments in the whole tree
      handle_comments($top);

      # Dump pseudo code if any (and when requested)
      if ( $dump_pseudocode && $top->{pseudocode} ) {
         do_dump_pseudocode( $infile, $top->{pseudocode} );
      }

      if ($runs_to_do==1 or 1){
         # Do the actual processing (only last time)
         toplevel2html( $top, $outfile );
         toplevel2header($top);
      }

   }

   # If there are stored top-levels to be combined, do so now
   delayed_write();
}

#--------------------------------------------------------------
sub main () {

=head2 main

 Main routine.

=cut

   if ( !@ARGV ) {
      print_usage();
      exit;
   }

   # Initialize the settings
   reset_comments();
   $dump_pseudocode                  = 0;
   $pseudo_path                      = 'pseudocode';

   # Initializations:
   my $catch_args  = 1;        # interpret arguments starting with '-'
                               # as options
   my $next_output = undef;    # name of output file to be determined
                               # from input file
   my $keep_output = 0;        # delete all generated ouput from previous run
   my $deleted_out = 0;        # if deleted --> 1

   # Initially run doctools three times!
   my $runs_to_do = 3;

   # Buffer items to be written to the tree.log, because
   # we do not know yet whether they have to be written...
   my $treelog_buffer = '';

   my $preread_done = 0;
   my $trees_read   = 0;
   my $current_run  = 0;

   while ( $runs_to_do > 0 ) {

      $current_run += 1;
      if ($preread_done) {
         unless ($trees_read) {
            $treelog_buffer = '';

            # Preread data generated during previous run(s)
            readComments();
            $trees_read = prepareTrees(1);
         }
      }

      my $files_processed = 0;
      my @arg_copy = @ARGV;
      while (my $arg = shift(@arg_copy)) {
         if ( $arg eq "--" ) {
         # Option '--': from here on, all arguments are file names
            $catch_args = 0;
         } elsif ( $catch_args and substr( $arg, 0, 1 ) eq "-" ) {
         # argument is an option: set option variable(s)
            if ( $arg eq '-$' ) {
               set_stmtsoption('wordchar','[\w\$]');
               set_stmtsoption('letterchar','a-zA-Z\$');
            } elsif ( $arg =~ /^-fixed_linelen$/ ) {
               set_fileiooption('fixed_linelen',shift(@arg_copy));
            } elsif ( $arg =~ /^-ddir$/ ) {
               $dictionary::COMMENTS = shift(@arg_copy) . "/comments.xml";
            } elsif ( $arg =~ /^-wdir$/ ) {
               $errwarndir = shift(@arg_copy);
               $utils::errwarndir = $errwarndir;
            } elsif ( $arg =~ /^-cp$/ ) {
               set_htmloption('comments_type', "preformatted");
            } elsif ( $arg =~ /^-cs$/ ) {
               set_htmloption('comments_type', "smart");
            } elsif ( $arg =~ /^-ch$/ ) {
               set_htmloption('comments_type', "html");
            } elsif ( $arg =~ /^-eol$/ ) {
               set_fileiooption('comments_eol');
            } elsif ( $arg =~ /^-1$/ ) {
               set_fileiooption('!');
            } elsif ( $arg =~ /^-style$/ ) {
               set_add_info_to_stmt_option('style',shift(@arg_copy));
            } elsif ( $arg =~ /^-svnlogoptions$/ ) {
               set_add_info_to_stmt_option('svnlogoptions',shift(@arg_copy));
            } elsif ( $arg =~ /^-fixed$/ ) {
               set_fileiooption('fixed');
            } elsif ( $arg =~ /^-free$/ ) {
               set_fileiooption('free');
            } elsif ( $arg =~ /^-nir$/ ) {
              set_htmloption('hide_interface_routines');
            } elsif ( $arg =~ /^-interface_only$/ ) {
              set_htmloption('interface_only');
            } elsif ( $arg =~ /^-nic$/ ) {
               $treelog_buffer .= "OPTION NO INTERFACE CALL\n";
            } elsif ( $arg =~ /^-hide$/ ) {
               $treelog_buffer .= "\n!! OPTION HIDE " . shift(@arg_copy) . "\n";
            } elsif ( $arg =~ /^-g([cj]*)$/ ) {
               my $flags = $1;
               my $text  = 'OPTION GRAPHVIZ';
               $text .= ' CONTAINER' if $flags =~ /c/;
               $text .= ' JOIN'      if $flags =~ /j/;
               $treelog_buffer .= "$text\n";
            } elsif ( $arg =~ /^-h/) {
               my $flags = $arg; $flags =~ s/^-h//;

               set_headeroption('headerstyle');
               foreach my $flag ( split('', $flags) )
               {
                  if    ($flag eq '!') { set_htmloption('no_html');       }
                  elsif ($flag eq 's') { set_headeroption('do_split');    }
                  elsif ($flag eq 'k') { set_headeroption('force_kind');  }
                  elsif ($flag eq 'a') { set_headeroption('force_star');  }
                  elsif ($flag eq '$') { set_headeroption('var_eol_cmt'); }
                  elsif ($flag eq 'U') { set_headeroption('force_upper'); }
                  elsif ($flag eq 'v') { set_headeroption('valign');      }
                  elsif ($flag eq 'd') { set_headeroption('less_dim');    }
                  elsif ($flag eq '1') { set_headeroption('no_dblmarks'); }
                  elsif ($flag eq 'm') { set_headeroption('no_modindent');}
                  else
                  {
                     my_die("Illegal header lay-out option '$flag'");
                  }
               }
            } elsif ( $arg =~ /^-pseudo$/ ) {
               $dump_pseudocode = 1;
            } elsif ( $arg =~ /^-tabsOK$/ ) {
               $tabsOK = 1;
            } elsif ( $arg =~ /^-tabsNotOK$/ ) {
               $tabsOK = 0;
            } elsif ( $arg =~ /^-I/ ) {
               set_fileiooption('add_path', shift(@arg_copy) );
            } elsif ( $arg =~ /^-O/ ) {
               my $outdir = shift(@arg_copy);
               set_htmloption('output_path',$outdir);
               set_treeoption('output_path',$outdir);
               $trees_read  = prepareTrees(0);
            } elsif ( $arg =~ /^-H/ ) {
               my $new_path = shift(@arg_copy);
               set_headeroption('output_path',$new_path);
            } elsif ( $arg =~ /^-P/ ) {
               $pseudo_path = shift(@arg_copy);
            } elsif ( $arg =~ /^-keep/ ) {
               $keep_output = 1;
            } elsif ( $arg =~ /^-welcome/ ) {
               set_treeoption('welcome',shift(@arg_copy));
            } elsif ( $arg =~ /^-skip_unknown/ ) {
               set_treeoption('skip_unknown');
            } elsif ( $arg =~ /^-debug:nolog$/ ) {

               # Hidden option for debugging: do not update the tree.log file.
               # Usable for single runs where we want to keep the "long" tree
               set_treeoption('dont_update_treelog');
            } else {
               my_die "Unrecognized option `$arg'";
            }
         } else {
         # argument is a file name: read the file and create output.

            # If old output must not be kept --> delete it
            if (!$keep_output && $current_run == 1 && $deleted_out == 0) {
               clear_html_path();
               clear_mkheader_path();
               remove_files($pseudo_path);
               $deleted_out = 1;
            }

            # First time the argument is a file. Now we know the correct paths
            # to do a pre-read.
            if (!$preread_done) {
               # Do a pre_read to check if an error occured in previous run or
               # if there is output from the last run which can be used!
               ($trees_read) = preread( $pseudo_path, $trees_read );
               $preread_done = 1;
               $runs_to_do -- if ($trees_read); # if tree existed already, one
                                                # run less is needed
            }
            my $g = $arg;
            $g = "\"$g\"" if $g =~ /\ /;
            my @filelist = glob($g);

            # Process the file(s)
            foreach my $file (@filelist) {
               process_file( $file, $next_output, $runs_to_do );
               $files_processed++;
               $next_output = undef;
            }
         }
      }

      if ($files_processed==0) {
         my_die("WARNING: No files processed");
         die;
      }

      writeComments();
      write_treelog($treelog_buffer) if $treelog_buffer;
      close_treelog();

      $runs_to_do--;
   }

   externals_to_htmldir();
}


sub preread($$)
{
   my $pseudo_path                 = shift;
   my $trees_read                  = shift;

   # If the last run had an error, then delete all the generated output and
   # start from scratch.
   if (-f "$errwarndir/fordocu.warn") {
      unlink("$errwarndir/fordocu.warn");
   }
   if (-f "$errwarndir/fordocu.err") {
      clear_html_path();
      clear_mkheader_path();
      remove_files($pseudo_path);

      unlink("$errwarndir/fordocu.err");
      print STDERR "The last run ended with an error. All existing " .
                   "output will be deleted and will be generated again.\n";
   }

   #Preread data generated during previous run(s)
   readComments();
   $trees_read = prepareTrees(1);

   return ($trees_read);
}


# Call the main routine...
main();
