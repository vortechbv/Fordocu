# Copyright (C) 2009-2010  Planbureau voor de Leefomgeving (PBL)
#
# full notice can be found in LICENSE

package htmling;

=head1 PACKAGE htmling

 This package contains functions to generate HTML output files.

=head1 CONTAINS

=cut

require 5.003;
use warnings;
use strict;
use diagnostics;


use File::Copy;
use File::Path('mkpath');
use FindBin('$Bin');

use add_info_to_stmt('add_info_to_top');
use stmts('print_stmt');
use f90fileio('code_and_comment');
use utils('my_die', 'remove_files');
use typing('type_to_f90');
use tree2html('write_treelog', 'make_key', 'calledBy', 'tree2html');
use vars ('$VERSION', '@EXPORT_OK', '@ISA');
$VERSION = '1.0';
@ISA     = ('Exporter');

our @EXPORT_OK = ('toplevel2html', 'attriblist', 'split_use', 'set_htmloption',
                  'externals_to_htmldir', 'clear_html_path');

### CONSTANTS
my $dblspace       = "  ";
my $indentspace    = $dblspace x 2;
my $comment_indent = $indentspace x 2;

my $tag_header_text = "headerText";
my $tag_header_vars = "headerVar";
my $tag_index       = "index";
my $tag_name        = "name";
my $tag_description = "description";

### PUBLIC GLOBALS
our $comments_type           = "preformatted";
our $hide_interface_routines = 0;

### MODULE_LEVEL VARIABLES
# (see also push_context/pop_context)
my $currentfile = "";
my $htmlfile    = "";
my $indent      = 0;
my @headerargs  = ();  # ! this global variable is not needed, because
                       #   it is also stored in $top. We leave it like
                       #   this for now.
my @stack       = ();

# Output directory
our $html_output_path = 'html';
our $do_html = 1;
our $interface_only=0;
#########################################################################
sub clear_html_path() { remove_files($html_output_path); }
sub set_htmloption($;$){
   my $option = shift;
   if (not @_)  {
      if    ($option eq 'no_html'                 ) { $do_html        = 0;}
      elsif ($option eq 'interface_only'          ) { $interface_only = 1;}
      elsif ($option eq 'show_interface_routines' ) { $hide_interface_routines = 0;}
      elsif ($option eq 'hide_interface_routines' ) { $hide_interface_routines = 1;}
      else          {my_die("unknown option '$option'"); die;}
   } else {
      if    ($option eq 'output_path'   ) { $html_output_path= shift;}
      elsif ($option eq 'comments_type' ) { $comments_type   = shift;}
      else          {my_die("unknown option '$option'"); die;}
   }
}


#########################################################################
sub check_output_path()
{

=head2 check_output_path();

  Check (en ensure) whether output+path exists.

=cut

   if ($html_output_path) {
      mkpath($html_output_path) unless (-w $html_output_path);
      $html_output_path =~ s/([^\\\/])$/$1\//;
      return;
   }
   $html_output_path = '';
}

############################################################################
sub push_context()
{

=head2 push_context();

  Put all module-level variables on this module's stack.

=cut

   my %box;
   $box{'currentfile'} = $currentfile;
   $box{'htmlfile'}    = $htmlfile;
   $box{'indent'}      = $indent;
   $box{'headerargs'}  = \@{\@headerargs};
   push(@stack, \%box);

   close OUT;
}
############################################################################
sub pop_context()
{

=head2 pop_context();

  Get module-level variables from this module's stack.

=cut

   my $box;
   $box         = pop(@stack);
   $currentfile = $box->{'currentfile'};
   $htmlfile    = $box->{'htmlfile'};
   $indent      = $box->{'indent'};
   @headerargs  = @{$box->{'headerargs'}};

   if($currentfile)
   {
      open OUT, ">>$currentfile"
         or my_die("could not open file '$currentfile' for appending");
   }

}
############################################################################
sub html_filename($)
{

=head2 $outfile = html_filename ($name);

  Return the name of the HTML file for the specified PROGRAM or MODULE

  INPUT VARIABLES
     $name    - name of the program or module
  OUTPUT VARIABLES
     $outfile - name of the HTML-file

=cut

   my $name = shift; 

   $name = lc $name;
   $name =~ s/::/_mp_/g;
   $name .= ".html" unless ($name =~ /\.html/);
   return $name;
}


# --------------------------------------------------------------------------
sub add_js()
{
   print OUT "<script type='text/javascript'>\n" . "<!--\n";

   # Function openURL
   # Returns an xmlhttp object (or null in case of failure)
   print OUT "function openURL(url) {\n"
     . "   try {\n"
     . "      var xmlhttp = null;\n"
     . "      try {\n"
     . "         if (window.ActiveXObject) {\n"
     . "            try {\n"
     . "               xmlhttp = new ActiveXObject('MSXML2.XMLHTTP');\n"
     . "            }\n"
     . "            catch(err) {\n"
     . "               xmlhttp = new ActiveXObject('Microsoft.XMLHTTP');\n"
     . "            }\n"
     . "         }\n"
     . "      }\n"
     . "      catch(err) {}\n"
     . "      if ((!xmlhttp) && window.XMLHttpRequest) {\n"
     . "         xmlhttp = new XMLHttpRequest();\n"
     . "      }\n"
     . "      if (xmlhttp) {\n"
     . "         xmlhttp.open('GET', url, false);\n"
     . "         try {xmlhttp.overrideMimeType('text/plain');} catch(err) {}\n"
     . "         xmlhttp.send(null);\n"
     . "         if (xmlhttp.status < 300) {\n"
     . "            return xmlhttp;\n"
     . "         }\n"
     . "      }\n"
     . "   }\n"
     . "   catch(err) {}\n"
     . "   return null;\n" . "}\n\n";

   # Function getURL
   # Returns an URL if the file is available, the specified name otherwise
   print OUT "function getURL(name,url,xmlhttp) {\n"
     . "   try {\n"
     . "      if (!xmlhttp) {\n"
     . "         var xmlhttp = openURL(url);\n"
     . "      }\n"
     . "      if (xmlhttp) {\n"
     . "         return '<a href=\"' + url +'\" name=\"' + name + '\">' + name + '</a>';\n"
     . "      }\n"
     . "   }\n"
     . "   catch(err) {}\n"
     . "   return name;\n" . "}\n\n";

   # Function getHeaderText
   # Retrieves header description (or an empty string)
   print OUT "function getHeaderText(xmlhttp, name) {\n"
     . "   var regexp = new RegExp('<$tag_header_text><$tag_name>' + name + '</$tag_name><$tag_description>([^(].*)</$tag_description></$tag_header_text>');\n"
     . "   var match = regexp.exec(xmlhttp.responseText);\n"
     . "   if ((! match) || match.length < 2) return \"\";\n"
     . "   return match[1];\n" . "}\n";

   # Function getNamedArgument
   # Retrieves a specific argument description
   print OUT "function getNamedArgument(xmlhttp,name) {\n"
     . "   var regexp = new RegExp('<$tag_header_vars>"
     . "<$tag_index>(.*)</$tag_index>"
     . "<$tag_name>' + name + '</$tag_name>"
     . "<$tag_description>(.*)</$tag_description>');\n"
     . "   var match = regexp.exec(xmlhttp.responseText);\n"
     . "   if ((! match) || match.length < 3) return '';\n"
     . "   return match[2];\n" . "}\n";

   # Function printNamedCallRows
   # Calls getNamedArgument() and prints the result in a table
   print OUT "function printNamedCallRows(xmlhttp,names) {\n"
     . "   for (var i=0; i<names.length; i++) {\n"
     . "      document.write('<tr valign=\"top\">"
     . "<td class=\"indexkey\"><a ref=\"' + names[i] + '\">' + names[i] + '</a></td>"
     . "<td class=\"indexvalue\">' + "
     . "getNamedArgument(xmlhttp,names[i]) + "
     . "'</td></tr>');\n"
     . "   }\n" . "}\n";

   # Function getArguments
   # Retrieves arguments and their description
   print OUT "function getArguments(xmlhttp) {\n"
     . "   var args = new Object();\n"
     . "   args.length      = 0;\n"
     . "   args.name        = new Array();\n"
     . "   args.description = new Array();\n\n"
     . "   for (;;) {\n"
     . "      var regexp = new RegExp('<$tag_header_vars>"
     . "<$tag_index>' + args.length + '</$tag_index>"
     . "<$tag_name>(.*)</$tag_name>"
     . "<$tag_description>(.*)</$tag_description>');\n"
     . "      var match = regexp.exec(xmlhttp.responseText);\n"
     . "      if ((! match) || match.length < 3) break;\n"
     . "      args.name[args.length] = match[1];\n"
     . "      args.description[args.length] = match[2];\n"
     . "      args.length++\n"
     . "   }\n"
     . "   return args;\n" . "}\n";

   # Function printCallRows
   # Calls getArguments() and prints the result in a table
   print OUT "function printCallRows(xmlhttp,locargs) {\n"
     . "   var remargs = getArguments(xmlhttp);\n"
     . "   for (var i=0; i<locargs.length; i++) {\n"
     . "      document.write('<tr valign=\"top\">"
     . "<td class=\"indexvalue\">' + locargs[i] + '</td>"
     . "<td class=\"indexvalue\">' + "
     . "(i<remargs.length ? remargs.name[i] : \"\") + "
     . "'</td><td class=\"indexvalue\">' + "
     . "(i<remargs.length ? remargs.description[i] : \"\") + "
     . "'</td></tr>');\n"
     . "   }\n" . "}\n";

   print OUT "-->\n" . "</script>\n";
}

sub categorize_calls($) {

=head2 categorize_calls

     ($subroutine_calls, $function_calls, $undefined_calls) = 
     categorize_calls($top)

     Return the calls, each in its own category

     INPUT ARGUMENT
        $top      : the top-level object whose calls are 
                    being processed

     OUTPUT ARGUMENTS
        $subroutine_calls : struct pointer, with a field for each 
                            subroutine call
        $function_calls : struct pointer, with a field for each 
                            function call
        $undefined_calls : struct pointer, with a field for each 
                            call to something of which the type is 
                            (yet) unknown: possibly a function?

=cut

  my $top = shift;

  # Chapter: used subroutines
  my $subroutine_calls = {};
  my $function_calls   = {};
  my $undefined_calls  = {};
  foreach my $call (keys(%{$top->{calls}})) {
     my $ctype = $top->{calls}->{$call}->{type};
     if ($ctype && $ctype eq 'subroutine') {
        $subroutine_calls->{$call} = $top->{calls}->{$call};
     } elsif ($ctype && $ctype eq 'yes') {
        $function_calls->{$call} = $top->{calls}->{$call};
     } elsif ($ctype && $ctype eq 'statement function') {
        # $stfunction_calls->{$call} = $top->{calls}->{$call};
     } else {
        $undefined_calls->{$call} = $top->{calls}->{$call};
     }
  }
  return($subroutine_calls, $function_calls, $undefined_calls);
}
# --------------------------------------------------------------------------
sub make_tab_page($$$$) {

=head2 make_tab_page($top, $tab, \@tabs, $htmlfile);

  Write a html-page for one of the tabs, describing an aspect of the top-level
  object 'top'

  INPUT VARIABLES
     $top      : the top-level object about which the tab page is being written
     $tab      : the name of the tab written
     @tabs     : the names of all the tabs written about the top-level object
     $htmlfile : name of the html file in which the first tab for $top is
                 written (subsequent tabs have extended file names)

=cut


  my $top      = shift;
  my $tab      = shift;
  my @tabs     = @{$_[0]}; shift;
  my $htmlfile = shift;
  my @parmstr  =  @{$top->{parmstr}};
  my $type = $top->{'type'};
  my $mainfile;
  if ($htmlfile and $html_output_path) {
     $mainfile = $html_output_path . $htmlfile;
  } else {
     $mainfile = $htmlfile;
  }

  #
  # Open the output file for this tab:
  #   $htmlfile_$tab.html  for all tabs except 'Header'
  # and
  #   $htmlfile.html       for 'Header'
  # This way, the file without the prefix still exists.
  #
  {
     my $lctab = lc($tab);
     $currentfile = $mainfile;
     $currentfile =~ s/\.html/_$lctab.html/ if ($tab ne $tabs[0]);
     $currentfile =~ s/ /_/g;
     # Open the output file
     open OUT, ">$currentfile"
       or my_die("cannot open file '$currentfile' for writing");
  }

  # Create HTML file header
  open TABS, "<$Bin/figs/tabs.html"
    or my_die("cannot open file '$Bin/figs/tabs.html' " .
                     "for reading");

  # Add title
  while (my $line = <TABS>)
  {
     $line =~ s/TITLE/$type $top->{'displayname'}/;
     print OUT $line;
  }
  close TABS;

  # Add our own Javascript functions
  add_js();

  # Create tabs:
  print OUT "<div class=\"tabs\">\n" . "  <ul>\n";

  foreach my $tab0 (@tabs)
  {
     my $file   = $htmlfile;
     my $lctab0 = lc($tab0);
     $file =~ s/\.html/_$lctab0.html/ if ($tab0 ne $tabs[0]);
     $file =~ s/ /_/g;
     my $href = $file;
     if ($tab0 eq $tab) {
        print OUT "      <li class=\"current\">";
     } else {
        print OUT "      <li>";
     }
     print OUT "<a href=\"$file\">" . "<span>$tab0</span></a></li>\n";
  }
  print OUT "  </ul>\n" . "</div>\n";

  # Print the name of the subroutine
  print OUT "<h1>" . ucfirst($type) . " $top->{'displayname'}</h1>";

  # Print only the information that applies to this tab
  if ($tab eq "Header") {
     if ($top->{'name'} =~ /(.+)::.+/) {
        my $file = "$1.html";
        print OUT "$top->{'displayname'} is contained by "
          . "<script type='text/javascript'>"
          . "document.write(getURL('$1','$file'));</script>"
          . ".<br><br>\n";
     }
     use Cwd;
     my $pwd = getcwd();
     my $cp  = $top->{'fullpath'};
     print OUT "$top->{'displayname'} is defined in file "
       . "<script type='text/javascript'>"
       . "document.write(getURL('$cp','file:///$pwd/$cp',1));</script>"
       . ".<br><br>\n" unless $interface_only;

     print OUT "<STRONG>HEADER</STRONG><br>\n";
     print OUT "<TABLE><tr valign=\"top\"><TD><A>\n";
     print OUT ucfirst($type) . " $top->{'displayname'}$parmstr[0]\n";
     print OUT "</A></TD></TR></TABLE>\n";

     # Process the comments
     #   (If macrodata is defined, use that information)
     my $description = $top->{description}->{line};
     my $guessed     = $top->{description}->{guessed};
     my $macrodata   = $top->{macrodata};
     my %mackeyval;
     if ($macrodata->{_order}) {
        foreach my $key (@{$macrodata->{_order}}) {
           next if $key =~ /^_/;    # Skip "macros" starting with _
           next if '' eq $macrodata->{$key};    # skip empty values
           $key = lc($key);

           if ($key eq 'description') {

              # Special handling for "description"
              $description = $macrodata->{$key};
              $guessed     = 0;
           } else {
              # Add all other key/value pairs that have to be displayed to
              # %mackeyval
              $mackeyval{$key} = $macrodata->{$key};
              $mackeyval{$key} = txt2html($mackeyval{$key})
                  unless $comments_type eq 'html';
           }
        }
     }
     $description = txt2html($description)
        unless $comments_type eq 'html';

     if ($description || %mackeyval) {
        print OUT "\n<P><STRONG>COMMENTS</STRONG>\n";
        print OUT "<TABLE>\n";
        if ($description) {
           print OUT "<tr valign=\"top\"><td class='indexkey'>".
                     "description</td><td class=\"indexvalue\">";
           do_comments($top->{name}, $description, $guessed,
                       $tag_header_text);
           print OUT "</td></tr>\n";
        }
        foreach my $key (@{$macrodata->{_order}}) {
           next unless $mackeyval{$key};
           print OUT "<tr valign=\"top\"><td class='indexkey'>".
                     "$key</td><td class=\"indexvalue\">";
           do_comments($top->{name}, $mackeyval{$key});
           print OUT "</td></tr>\n";
        }
        print OUT "</TABLE>\n";
     }

     # Process pseudocode (if any)
     if ($top->{'pseudocode'}) {
        print OUT "\n<P><STRONG>PSEUDOCODE</STRONG>\n";
        print OUT "<TABLE>\n";
        print OUT "<tr valign=\"top\"><td class=\"indexvalue\">";
        do_comments($top->{name}, $top->{pseudocode});
        print OUT "</td></tr>\n";
        print OUT "</TABLE>\n";
     }

     # Print table listing the header variables
     if (@{$top->{header_vars}}) {
        print OUT "\n<P><STRONG>ARGUMENTS</STRONG>\n";
        do_varshtml($top, $top->{header_vars}, $tag_header_vars);
     }

     # Chapter: used modules
     if ($top->{uses} && @{$top->{uses}} and not $interface_only) {
        print OUT "\n<P><STRONG>USE STATEMENTS</STRONG>\n";
        list_uses($top);
     }

     # Print table listing the common variables
     print OUT "\n<P><STRONG>COMMON BLOCKS</STRONG>\n"
       if (keys(%{$top->{common_vars}}));
     foreach my $common (keys(%{$top->{common_vars}})) {
       print OUT "<br>Common Block $common\n";
       do_varshtml($top, $top->{common_vars}->{$common});
     }
  } elsif ($tab eq "Version history") {
     print OUT "\n<HR><H2>VERSION HISTORY</H2>\n";
     print OUT "$top->{version_history}\n";
  } elsif ($tab eq "Subroutines called") {

     # Chapter: used subroutines
     my ($subroutine_calls, $function_calls, $undefined_calls) = 
        categorize_calls($top);
     list_calls($top, 'SUBROUTINE', $subroutine_calls);
     list_calls($top, 'FUNCTION', $function_calls);
     list_calls($top, 'POSSIBLE FUNCTION', $undefined_calls);

     # Count non-interface subroutine and function calls
     my $countsub = 0;
     foreach my $key (keys %$subroutine_calls) {
        $countsub++
          unless $subroutine_calls->{$key}->{remote_type} and
                 $subroutine_calls->{$key}->{remote_type} eq 'interface';
     }
     my $countfun = 0;
     foreach my $key (keys %$function_calls) {
        $countfun++
          unless $function_calls->{$key}->{remote_type} and
                 $function_calls->{$key}->{remote_type} eq 'interface';
     }

     print OUT "<HR><H2>CALL DETAILS</H2>\n" if ($countsub || $countfun);

     list_call_info($subroutine_calls, $top)
       if $countsub;
     list_call_info($function_calls, $top)
       if $countfun;
  } elsif ($tab eq "Types") {
     print OUT "\n<HR><H2>TYPES</H2>\n";
     do_types(@{$top->{types}});
  } elsif ($tab eq "Includes") {
     print OUT "\n<HR><H2>INCLUDE FILES</H2>\n";
     foreach my $incfile (keys(%{$top->{include_vars}})) {
        print OUT "\n<br><H3> Include file $incfile</H3>\n";
        do_varshtml($top, $top->{include_vars}->{$incfile});
     }
  } elsif ($tab eq "Variables") {
     print OUT "\n<HR><H2>VARIABLES</H2>\n";
     do_varshtml($top, $top->{local_vars});
  } elsif ($tab eq "Interfaces") {
     print OUT "\n<HR><H2>INTERFACES</H2>\n";
     do_interfaces($top, $top->{intfc}, $top->{funs});
  } elsif ($tab eq "Contained") {
     do_moduleprocedures($top, $top->{funs});
  } elsif ($tab eq "Called by") {
     do_called_by($top, $top->{callers});
  } elsif ($tab eq "Source") {

     # Tab Sources: pretty-print the source
     # List of all common block variables
     my @all_common_vars;

     foreach my $common (keys(%{$top->{common_vars}})) {

        #print "Pushing common block $common\n";
        push(@all_common_vars, @{$top->{common_vars}->{$common}});
     }
     do_source($top->{source}, $top->{header_vars}, \@all_common_vars,
               $top->{local_vars}, $top->{types}, $top->{intfc},
               [keys(%{$top->{calls}})], $top->{firstline});
  }

  print OUT "</BODY></HTML>\n";
  close OUT;
}


############################################################################
sub toplevel2html($$)
{

=head2 toplevel2html($top, $outfile)

  This is the main calling point from fordocu.
  Takes a top-level objects: program, subroutine, function or module.
  Warns if given something else.

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

     $outfile: output file (possibly empty, in which case a file name
               will be chosen)

=cut

   return unless ($do_html);
   my $top     = shift;
   my $outfile = shift;

   my $type = $top->{'type'};
   if ($type ne 'module'   and $type ne 'subroutine' and
       $type ne 'function' and $type ne 'program'    and
       $type ne 'block data') {
      warn "Warning: Unrecognized top-level object $type will " .
           "not be documented.\n";
      return;
   }

   push_context();

   # Choose a name for the output file if not given
   if (!defined $outfile)
   {
      $outfile = $top->{'name'};
      $outfile = $top->{'type'} if ($outfile eq '');

      $outfile = html_filename($outfile);
   }

   $htmlfile = $outfile;

   # Add some info to the object
   add_info_to_top($top); @headerargs = $top->{header_args};

   #stmts::print_stmt($top,0);

   # Check for all possible tabs whether they should be made
   my @tabs = ('Header');
   if (not $interface_only) {
      push(@tabs, 'Version history')    if ($top->{version_history});
      push(@tabs, 'Types')              if (@{$top->{types}});
      push(@tabs, 'Subroutines called') if (keys(%{$top->{calls}}));
      push(@tabs, 'Variables')          if (@{$top->{local_vars}});
      push(@tabs, 'Includes')           if (%{$top->{include_vars}});
   }
   push(@tabs, 'Interfaces')         if (@{$top->{intfc}});
   if (not $interface_only) {
      push(@tabs, 'Contained')          if (@{$top->{funs}});
      push(@tabs, 'Called by')          if (@{$top->{callers}});
      push(@tabs, 'Source');
   }

   # Print human-readable line
   print "   Generating $htmlfile...\n";

   # Print line for tree2html:
   write_treelog(
     "HTMLPAGE $htmlfile DESCRIBES " . uc($top->{type}) . " $top->{name}\n");

   # Check output directory
   my $mainfile = $htmlfile;
   if ($mainfile and $html_output_path) {
      check_output_path();
   }

   foreach my $tab (@tabs) {
      make_tab_page($top, $tab, \@tabs, $htmlfile);
   }

   if ($interface_only) {
     my ($subroutine_calls, $function_calls, $undefined_calls) = 
        categorize_calls($top);
     calls_to_tree($top, 'SUBROUTINE', $subroutine_calls);
     calls_to_tree($top, 'FUNCTION', $function_calls);
     calls_to_tree($top, 'POSSIBLE FUNCTION', $undefined_calls);
   }
   pop_context();
}
#
############################################################################
#
sub split_use($)
{
   my $use = shift;

   my $module = "";
   my $only   = "";
   foreach my $part (@{$use}) {
      if ($module) {
         $only .= $part if $part;
      } else {
         $module = $part;
      }
   }
   return ($module, $only);
}

# --------------------------------------------------------------------------
sub list_uses($)
{
   my $top  = shift;
   my @uses = @{$top->{uses}};

   my $caller = $htmlfile;
   $caller =~ s/\.html$//;

   print OUT "<TABLE>\n";

   foreach my $use (@uses) {
      my $comments = "";
      my ($module, $only) = split_use($use);

      # Print for tree2html
      write_treelog(uc($top->{type}) . " $top->{name} USES MODULE $module\n");

      # Print to HTML
      my $file = lc("$module.html");
      print OUT "<tr valign=\"top\"><td class=\"indexkey\">"
        . "<script type='text/javascript'>"
        . "document.write(getURL('$module','$file'));</script></td>";
      print OUT "<td class=\"indexvalue\">$only</td>\n";
   }

   print OUT "</TABLE>\n";
}

sub calls_to_tree($$$) {

=head2 calls_to_tree($top,$type_called,$calls)

  Write the calls given in the input to the tree-file, so it will be
  processed properly into the call tree.

  INPUT VARIABLES
     $top
     $type_called
     $calls

=cut

   my $top         = shift;
   my $type_called = shift;
   my $calls       = shift;

   return unless (%$calls);

   # Remove word possible from $type_called and replace it by
   # a question mark (POSSIBLE FUNCTION BECOMES ?FUNCTION)
   $type_called =~ s/POSSIBLE\ /\?/i;

   # For the construction of the calling tree, print the calls to tree.log
   my @names = sort { 
       $calls->{$a}->{lines}[0] <=> $calls->{$b}->{lines}[0]  
       } keys(%$calls);
   foreach my $called (@names) {
      write_treelog(uc($top->{type}) . " $top->{name} CALLS $type_called $called\n");
   }
}

# --------------------------------------------------------------------------
sub list_calls ($$$)
{

=head2 list_calls($top,$type_called,$calls)

  Print the calls given in the input.
`
  INPUT VARIABLES
     $top
     $type_called
     $calls

=cut

   my $top         = shift;
   my $type_called = shift;
   my $calls       = shift;

   return unless (%$calls);

   print OUT "\n<HR><H2>${type_called}S CALLED</H2>\n";

   calls_to_tree($top,$type_called,$calls);
   my @names = sort { 
       $calls->{$a}->{lines}[0] <=> $calls->{$b}->{lines}[0]  
       } keys(%$calls);

   # Find the comments in the code if they have been filled
   # in an alternative style
   foreach my $name (@names) {
      next if (!$calls->{$name}->{type});
      next if $calls->{$name}->{type} eq "subroutine";
      next if $calls->{$name}->{type} eq "program";
      $calls->{$name}->{description} = $calls->{$name}->{var}->{description}
        unless $calls->{$name}->{description};
   }

   # If the origin of the called routine is a module, determine which module
   my $parent_key = make_key($top->{type}, $top->{name});
   my $called_by  = calledBy($parent_key);
   foreach my $name (@names) {
      foreach my $called (@$called_by) {
         if ($called =~ /(.+):\/\/(.+)::$name\b/i) {
            $calls->{$name}->{remote_type} = $1;
            $calls->{$name}->{module}      = $2;
            last;
         }
      }
   }

   # Now create an HTML-table.
   print OUT "<TABLE>\n";
   foreach my $name (@names) {
      my $file = $htmlfile;
      $file =~ s/\.html/_source.html/;
      my @ilines;
      foreach my $jline (@{$calls->{$name}->{lines}}) {
         my $href = "<A HREF=\"$file#$jline\">$jline</A>";
         push(@ilines, $href);
      }

      # Now, determine and store the URL
      if ($calls->{$name}->{module}) {
         if ($calls->{$name}->{remote_type} eq 'interface') {
            $file = lc($calls->{$name}->{module}) .
                    '_interfaces.html#interface_' . lc($name);
         } else {
            $file = lc($calls->{$name}->{module}) . '_mp_' .
                    lc("$name.html");
         }
      } else {
         $file = lc("$name.html");
      }
      $calls->{$name}->{url} = $file;

      # Finally, print the table row
      print OUT "   <tr valign=\"top\">\n"
        . "      <td class='indexkey'><script type='text/javascript'>"
        . "document.write(getURL('$name','$file'));</script></td>\n"
        . "      <td class=\"indexvalue\" width=\"40%\">";
      do_comments($name, $calls->{$name}->{description}->{line},
                  $calls->{$name}->{description}->{guessed},
                  $tag_header_text, $file);

      print OUT "</td>\n" . "      <td class=\"indexvalue\" width=\"20%\">" .
                join(', ', @ilines) . "</td>\n" . "   </tr>\n";
   }
   print OUT "</TABLE>\n";
}

# --------------------------------------------------------------------------
sub list_call_info($$)
{

=head2 list_call_info($calls, $top)

  Print extra information about calls given in the input.

  INPUT VARIABLES
     $calls
     $the calling procedure

=cut

   my $calls = shift;
   my $top   = shift;

   return unless (%$calls);

   my $locname = $top->{'displayname'};

   my @names = keys(%$calls);
   my $lfile = $htmlfile;
   $lfile =~ s/\.html/_source.html/;

   # Now create many HTML-tables.
   foreach my $name (@names) {
      next if $calls->{$name}->{remote_type} and
              $calls->{$name}->{remote_type} eq 'interface';

      my $rfile = lc("$name.html");
      $rfile = $calls->{$name}->{url} if $calls->{$name}->{url};

      print OUT "<script type='text/javascript'>\n" .
                "xmlhttp = openURL('$rfile')\n" . "if (xmlhttp) {\n";

      foreach my $iline (1 .. @{$calls->{$name}->{lines}}) {

         # Collect line number
         my $jline = @{$calls->{$name}->{lines}}[$iline - 1];
         my $href  = "<A HREF=\"$lfile#$jline\">$jline</A>";

         # Collect local arguments for this specific call
         my $icall = @{$calls->{$name}->{args}}[$iline - 1];
         next if (!$icall);
         my @locargs = ();
         foreach my $j (1 .. @$icall) {
            my $arg = ${$icall}[$j - 1];
            $arg =~ s/([\'\\\/\*\.\ \"])/\\$1/g;
            push(@locargs, "'" . $arg . "'");
         }
         next if (!@locargs);

         print OUT "   var remname = getURL('$name','$rfile', xmlhttp);\n"
           . "   document.write('<P>Call to ' + remname +"
           . "' on line $href');\n"
           . "   document.write('<TABLE>')\n"
           . "   document.write('<tr valign=\"top\"><td class=\"indexkey\">$locname</td>"
           . "<td class=\"indexkey\">$name</td>"
           . "<td class=\"indexkey\">description</td></tr>');\n"
           . "   var locargs = new Array("
           . join(",", @locargs) . ");\n"
           . "   printCallRows(xmlhttp,locargs);\n"
           . "   document.write('</TABLE></P>');\n";
      }

      print OUT "}\n" . "</script>\n\n";
   }
}

# --------------------------------------------------------------------------
sub list_html
{

=head2

=cut

   my $title = shift;
   my @items = @_;
   if (@items) {
      print OUT "\n<B>$title</B>\n";

      # Determine optional columns for variable display
      my %optcol;
      foreach my $struct (@items) {
         next unless $struct->{'type'} eq "var";
         update_optcol($struct, \%optcol);
      }

      foreach my $struct (@items) {
         my ($name, $type) = (txt2html($struct->{'name'}), $struct->{'type'});
         my ($href) = "<A HREF=\"${htmlfile}#${type}_" . lc($name) . "\">$name</A>";
         print OUT $indentspace;
         if ($type eq "var") {
            print OUT var2cols($struct, $href, \%optcol) . "\n";
         } elsif ($type eq "subroutine" or $type eq "function") {
            print OUT lc(join("<br>", attriblist($struct), ""));
            print OUT typing::type_to_f90($struct->{'rtype'}) . " "
              if exists $struct->{'rtype'};
            my $flag;
            for $flag ('recursive', 'elemental', 'pure') {
               print OUT "$flag " if $struct->{$flag};
            }
            print OUT "$type $href";
            print OUT " (" . join(", ", @{$struct->{'parms'}}) . ")";
            print OUT " result ($struct->{'result'})"
              if exists $struct->{'result'} && !exists $struct->{'rtype'};
            print OUT "\n";
         } else {
            print OUT lc(join("<br>", attriblist($struct), ""));
            print OUT "$type $href\n";
         }
      }
   }
}

# --------------------------------------------------------------------------
sub do_varrow($$$;$$)
{

=head2 do_varrow($$$;$$)

   Print a table row with variable data in the format
      variable | line numbers | description

   INPUT VARIABLES
      $var       - hash containing the variable data
      $withlines - include a line number column (yes/no)
      \%optcol   - information on optional columns to include
      $index     - index value of the row to print
      $reftag    - tag for later reference (optional)

=cut

   my $var       = shift;
   my $withlines = shift;
   my $optcol    = shift;
   my $index     = shift;
   my $reftag    = shift;

   return unless $var;

   # Convert name and type of the variable
   my $name = txt2html($var->{'name'});
   my $type = txt2html($var->{'type'});

   # Determine line numbers
   my @ilines;
   my $file = $htmlfile;
   $file =~ s/\.html/_source.html/;
   foreach my $jline (@{$var->{ilines}}) {
      my $href = "<A HREF=\"$file#$jline\">$jline</A>";
      push(@ilines, $href);
   }

   # Write reference line to the html files
   my $cmt = $var->{description}->{line};
   if ($reftag) {
      $cmt =~ s/\n/<br>/g;     # Replace \n by <br>
      $cmt =~ s/[\r\t]/ /g;    # Replace other special characters by spaces
      $cmt =~ s/\ {2,}/ /g;    # Replace multiple spaces by a single spaces

      my $cmt2;
      if ($cmt and $var->{description}->{guessed}) {
         $cmt2 = "? $cmt";
      } else {
         $cmt2 =  $cmt;
      }

      print OUT "<!-- <$reftag><$tag_index>$index</$tag_index>"
        . "<$tag_name>$name</$tag_name>"
        . "<$tag_description>$cmt2</$tag_description>"
        . "</$reftag> -->\n";
   }

   # Print table row
   print OUT "<tr valign=\"top\"><td class=\"indexkey\">" .
             "<A NAME=\"$name\">" . var2cols($var, '', $optcol) . "</A></td>";
   print OUT "<td class=\"indexvalue\">";
   do_comments($name, $cmt, $var->{description}->{guessed});
   print OUT "</td><td class=\"indexvalue\">" . join(', ', @ilines)
     if $withlines;
   print OUT "</td></tr>\n";
}

# --------------------------------------------------------------------------
sub do_varshtml($$;$)
{

=head2 do_varshtml($top, \@vars,$reftag)

   Print the information about the structs given in pretty HTML
   format

   INPUT VARIABLES
      $top       - struct representing a fortran structure which contains
                   variables.
      @vars      - an array of structures to be printed
                   these structs describe variables
      $reftag    - tag for later reference (optional)

=cut

   my $top  = shift;
   my @vars = @{$_[0]}; shift;
   my $reftag = shift;

   return unless (@vars);

   print OUT "<TABLE>\n";

   # Determine optional columns for variable display
   my %optcol;
   foreach my $var (@vars) {
      update_optcol($var, \%optcol);
   }

   my $index = 0;
   foreach my $var (@vars) {
      if ($var->{vis} and $var->{vis} eq 'public') {
         # Export public variables
         write_treelog(uc($top->{type}) . " $top->{name} ".
                       "EXPORTS VARIABLE $top->{name}::$var->{name}\n");
      }

      do_varrow($var, !$interface_only, \%optcol, $index, $reftag);
      $index++;
   }
   print OUT "</TABLE>\n";
}

# --------------------------------------------------------------------------
sub do_types(@)
{

=head2 do_types(@structs)

   Print the information about the types given in pretty HTML
   format

   INPUT VARIABLES
      @structs - an array of structures to be printed

=cut

   my @structs = @_;

   return unless (@structs);

   foreach my $struct (@structs) {

      # Convert name and type of the structure
      my $name = txt2html($struct->{'name'});
      my $type = txt2html($struct->{'type'});

      my @ilines;
      my $file = $htmlfile;
      $file =~ s/\.html/_source.html/;
      foreach my $jline (@{$struct->{ilines}}) {
         my $href = "<A HREF=\"$file#$jline\">$jline</A>";
         push(@ilines, $href);
      }

      # Determine number of columns needed for contents
      my %optcol;
      foreach my $var (@{$struct->{'ocontains'}}) {
         update_optcol($var, \%optcol);
      }
      my $width = 1;
      foreach my $key (keys %optcol) {
         $width += $optcol{$key};
      }

      # Start table
      my $height = 2 + $#{$struct->{ocontains}};
      my $attribs = lc(
             join("<br>",
                  attriblist($struct),
                  (exists $struct->{'sequencetype'} ? 'sequence' : ''),
                  (exists $struct->{'privatetype'}  ? 'private'  : ''))
      );

      print OUT "<p><table>\n"
        . "<tr valign='top'>"
        . "<td class='indexkey' rowspan='$height'>"
        . "<A NAME='type_" . lc($name) . "'>"
        . "$name</A></td><td class='indexvalue'>$attribs</td>"
        . "<td class='indexvalue' colspan='$width'>"
        . join(', ', @ilines)
        . "<td class='indexvalue'>";
      do_comments( $struct->{name}, $struct->{description}->{line},
                   $struct->{description}->{guessed});
      print OUT "</td></tr>\n";

      # Print contents
      foreach my $var (@{$struct->{'ocontains'}}) {
         do_varrow($var, 0, \%optcol);
      }

      # End table
      print OUT "</table></p>\n\n";
   }
}

# --------------------------------------------------------------------------
sub do_interfaces($$;$)
{

=head2 do_interfaces($top, \%intf, \%funs)

   Print the information about the interfaces given in pretty HTML
   format

   INPUT VARIABLES
      $top   - parent
      \%intf - interface structs
      \%funs - function structs (optional, for comment retrieval)

=cut

   my $top  = shift;
   my $intf = shift;
   my $funs = shift;

   my @structs = @$intf;
   return unless (@structs);

   foreach my $struct (@structs) {

      # Convert name and type of the structure
      my $type = txt2html($struct->{'type'});
      my $name = txt2html($struct->{'name'});

      # Escape special characters used in operators
      $name =~ s/\(/\\(/;
      $name =~ s/\)/\\)/;
      $name =~ s/\*/\\*/;
      $name =~ s/\+/\\+/;

      # Write contains information for tree2html
      my $interfacefile = $htmlfile;
      $interfacefile =~ s/.html/_interfaces.html/i;
      write_treelog("HTMLPAGE $interfacefile#interface_" . lc($name) .
                    " DESCRIBES INTERFACE $top->{'name'}::$name\n");
      write_treelog(
           uc($top->{'type'}) . " $top->{'name'} "
           . ($struct->{'vis'} eq 'public' ? "EXPORTS " : "CONTAINS ")
           . uc($type) . " $top->{'name'}::$name\n");

      my @ilines;
      my $file = $htmlfile;
      $file =~ s/\.html/_source.html/;
      foreach my $jline (@{$struct->{ilines}}) {
         my $href = "<A HREF=\"$file#$jline\">$jline</A>";
         push(@ilines, $href);
      }

      # Write reference line to the html files
      my $cmt = $struct->{description}->{line};
      $cmt = "? $cmt" if ($cmt and $struct->{description}->{guessed});
      $cmt =~ s/\n/<br>/g;     # Replace \n by <br>
      $cmt =~ s/[\r\t]/ /g;    # Replace other special characters by spaces
      $cmt =~ s/\ {2,}/ /g;    # Replace multiple spaces by a single spaces

      my $shortname = $struct->{name};
      $shortname =~ s/.+:://g;
      print OUT "<!-- <$tag_header_text>"
        . "<$tag_name>$shortname</$tag_name>"
        . "<$tag_description>$cmt</$tag_description>"
        . "</$tag_header_text> -->\n";

      # Start table
      my $height = 2 + $#{$struct->{ocontains}};
      my $attribs = lc(join("<br>", attriblist($struct)));
      $attribs =~ s/public//gi;
      $attribs =~ s/<br><br>/<br>/g;
      print OUT "<p><table>\n"
        . "<tr valign='top'>"
        . "<td rowspan='$height' class='indexkey'>"
        . "<A NAME='interface_" . lc($name) . "'>" . "$name</A></td>"
        . ($hide_interface_routines ? '' : "<td class='indexvalue'>$attribs</td>")
        . "<td class='indexvalue'>";
      do_comments($struct->{name}, $struct->{description}->{line},
                  $struct->{description}->{guessed});
      print OUT "</td></tr>\n";

      # Print contents
      foreach my $var (@{$struct->{'ocontains'}}) {
         unless ($hide_interface_routines) {
            my $cname = $var->{name};
            my $cfile = lc("$top->{'name'}_mp_$cname.html");
            $cname = "<script type='text/javascript'>" .
                     "document.write(getURL('$cname','$cfile'));" .
                     "</script>";
            print OUT "<tr valign='top'>"
              . "<td class='indexkey'><a name='"
              . $var->{name} . "'>"
              . "$cname</a></td><td class='indexvalue'>";

            # Use the comments given; in case there aren't,
            # try to retrieve comments from routines in the module
            my $comments = $var->{description}->{line};
            if ($funs && !$comments) {
               foreach my $fun (@$funs) {
                  if ($fun->{'name'} eq $var->{name}) {
                     $comments = $fun->{description}->{line};
                     last;
                  }
               }
            }
            do_comments($var->{name}, $comments, $var->{description}->{guessed});
            print OUT "</td></tr>\n";
         }

         # Print information for tree2html
         write_treelog("INTERFACE $top->{'name'}::$name CALLS " .
                       uc($var->{type}) . " $var->{name}\n");
      }

      # End table
      print OUT "</table></p>\n\n";
   }
}

# --------------------------------------------------------------------------
sub list_routines ($$$)
{

=head2 list_routines($top,$type_name,$routines)

  Print the contained routine information given in the input.
  Depending on the input $big, this is done...
`
  INPUT VARIABLES
     $top
     $type_name
     $routines

=cut

   my $top       = shift;
   my $type_name = shift;
   my $routines  = shift;

   return unless (%$routines);

   print OUT "\n<HR><H2>${type_name}S CONTAINED</H2>\n";

   # For the construction of the calling tree, print the routines to tree.log
   # Also, generate a file for each routine
   my @names = keys(%$routines);
   foreach my $name (@names) {
      my $tree_line = uc($top->{type}) . " $top->{name} ";
      if ( $routines->{$name}->{'vis'} and
           $routines->{$name}->{'vis'} eq 'public') {
         $tree_line .= 'EXPORTS'
      } else {
         $tree_line .= 'CONTAINS'
      }
      $tree_line .= " $type_name $top->{name}::$name\n";
      write_treelog($tree_line);

      # Recurse to generate files for contained routines
      $routines->{$name}->{'name'}     = $top->{'name'} . "::$name";
      $routines->{$name}->{'fullpath'} = $top->{'fullpath'};
      toplevel2html($routines->{$name}, html_filename("$top->{name}_mp_$name.html"));
   }

   # Find the comments in the code if they have been filled
   # in an alternative style
   foreach my $name (@names) {
      next if (!$routines->{$name}->{type});
      next if $routines->{$name}->{type} eq "subroutine";
      next if $routines->{$name}->{type} eq "program";
      $routines->{$name}->{description} = $routines->{$name}->{var}->{description};
   }

   # Now create an HTML-table.
   foreach my $name (@names) {
      my $file = lc("$top->{'name'}_mp_$name.html");

      # Generate HTML
      my $typename = lc($type_name);
      print OUT "<P><h3>$typename "
        . "<script type='text/javascript'>\n"
        . "   var xmlhttp = openURL('$file');\n"
        . "   document.write(getURL('$name','$file',xmlhttp));"
        . "</script></h3><TABLE>\n"
        . "   <tr valign=\"top\"><td class=\"indexkey\">argument</td>"
        . "<td class=\"indexkey\">description</td></tr>\n"
        . "<script type='text/javascript'>\n"
        . "   var names = new Array('"
        . join("','", @{$routines->{$name}->{'parms'}}) . "');\n"
        . "   printNamedCallRows(xmlhttp,names);\n"
        . "</script></TABLE></P>\n";
   }
}

# --------------------------------------------------------------------------
sub do_moduleprocedures($$)
{

=head2 do_moduleprocedures($top,$routines)

   Print the information about the routines given in pretty HTML
   format

   INPUT VARIABLES
      $top      - container struct
      $routines - an array of structures to be printed

=cut

   my $top      = shift;
   my $routines = shift;

   return unless ($routines);

   my $module = $top->{'name'};

   # Collect module procedures, subroutines and function from @funs
   my %data_per;
   foreach my $routine (@$routines) {

      # Convert name and type of the structure
      my $name = txt2html($routine->{'name'});
      my $type = txt2html($routine->{'type'});

      if (   $type eq "subroutine" or $type eq "function"
          or $type eq "mprocedure") {

         my_die("bare module procedure $routine->{'name'}".
                " (no enclosing module)")
           unless ($type ne "mprocedure") || (exists $routine->{'bind'});

         my_die("$type $name already defined in module $module")
           if defined $data_per{$type}->{$name};
         $data_per{$type}->{$name} = $routine;
      }
   }

   # Write results
   list_routines($top, 'SUBROUTINE', $data_per{"subroutine"})
     if $data_per{"subroutine"};
   list_routines($top, 'FUNCTION', $data_per{"function"})
     if $data_per{"function"};
   list_routines($top, 'MODULE PROCEDURE', $data_per{"mprocedure"})
     if $data_per{"mprocedure"};
}

# --------------------------------------------------------------------------
sub do_called_by($$)
{

=head2 do_called_by($top,\@my_callers)

   Print the information about the calling routines
   in pretty HTML format

   INPUT VARIABLES
      $top         - container struct
      \@my_callers - an array with the tree2html keys of the callers

=cut

   my $top        = shift;
   my $my_callers = shift;

   return unless $top && $my_callers;

   print OUT "\n<hr><h2>CALLED BY...</h2>\n";

   # Now create an HTML-table.
   print OUT "<table>\n";
   foreach my $caller (@$my_callers) {

      # Determine the URL
      my $file = $caller;
      $file =~ s/(.+):\/\///;
      my $type = $1;
      $file =~ s/::/_mp_/g;
      my $name = $file;
      $name =~ s/_mp_(.+)$/$1/;
      if ($type eq 'interface') {
         $file =~ s/_mp_(.+)$/_interfaces.html#/;
         $file .= lc($1);
      } else {
         $file .= '.html';
      }

      print OUT "<tr valign='top'>\n"
        . "   <td class='indexkey'>$type</td>\n"
        . "   <td class='indexkey'><script type='text/javascript'>"
        . "var xmlhttp=openURL('$file');"
        . "document.write(getURL('$name','$file',xmlhttp));"
        . "document.write('</td><td class=\"indexvalue\">');"
        . "document.write(getHeaderText(xmlhttp,'$name'));"
        . "document.write('</td>');"
        . "</script>\n"
        . "</tr>\n";

   }
   print OUT "</table>\n";

}

# --------------------------------------------------------------------------
sub do_comments($$;$$$)
{

=head2 do_comments($name, $comments, [$guessed, $reftag, $altsrc])

  Pass comments.

  If $reftag is specified and $altsrc isn't comments are written as
  an XML comment for later reference.

  If both $reftag and $altsrc are specified and $comments is empty,
  and attempt will be made to retrieve comments from $altsrc

  INPUT VARIABLES
     $name       - name of the item to be described
     $comments   - the comments
     $guessed    - flag indicating whether the comments are guessed or not
                   (optional)
     $reftag     - tag used for later reference (optional)
     $altsrc     - html source file to obtain the comment at $reftag (optional)

=cut

   my ($name, $comments, $guessed, $reftag, $altsrc) = @_;
   $comments = "" if (not defined($comments));
   # If $comments is an array, join them
   $comments = join("\n", @{$comments}) if ref($comments) eq 'ARRAY';

   # Keep only last paragraph of explanation
   $comments =~ s/\n/<br>/g;
   while ($comments =~ s/<br>\s*$//) {};
   while ($comments =~ s/^<br>//) {};
   $comments =~ s/.*<br>\\nEMPTY_LINE\\n<br>//;
   $comments =~ s/.*\\nEMPTY_LINE\\n<br>//;
   if ($comments !~ /<br>/) {$comments =~ s/^\s*//;};
   $comments =~ s/^\s*//g;
   $comments =~ s/<br>\s*/<br>/g;
   $comments =~ s/<br>/\n/g;

   # if comments aren't specified as HTML, replace < and >
   $comments =~ s/<br>/\n/g;                      # Replace <br> by \n
   $comments = txt2html($comments) unless ($comments_type eq 'html');

   $comments =~ s/\n/<br>/g;                      # Replace \n by <br>
   $comments =~ s/<br>\:\s*/<br>/g;               # Remove leading : at begin of line in comments
   $comments =~ s/(<br>)*$//g;                    # Remove empty lines at the end of comments

   # if $reftag is specified and $altsrc isn't write the comments a comment
   if ($reftag && !$altsrc) {
      my $shortname = $name;
      $shortname =~ s/.+:://g;

      my $cmt = $comments;
      $cmt =~ s/[\r\t]/ /g;                     # Replace special characters by spaces
      $cmt =~ s/\ {2,}/ /g;                     # Replace multiple spaces by a single spaces
      $cmt =~ s/<h.>.*<\/h.>//gi;               # Remove headers (including text)
      $cmt =~ s/<strong>.*<\/strong>//gi;       # Remove subheaders (including text)
      $cmt =~ s/^(?:<br>)+//gi;                 # Remove leading <br> tags
      $cmt =~ s/(?:<br>)+$//gi;                 # Remove trailing <br> tags
      $cmt =~ s/^(?:[^A-za-z0-9]*<br>)+//gi;    # Remove leading <br> tags, including non-characters
      $cmt =~ s/(?:<br>[^A-za-z0-9]*)+$//gi;    # Remove trailing <br> tags, including non-characters
      $cmt =~ s/(<ul>)|(<\/ul>)//gi
        if !($cmt =~ /<li>/);                   # Remove <ul> without <li>
      $cmt =~ s/^\s+//;                         # Remove leading spaces
      $cmt =~ s/\s+$//;                         # Remove trailing spaces
      print OUT "<!-- <$reftag><$tag_name>$shortname</$tag_name>".
                "<$tag_description>$cmt</$tag_description></$reftag> -->\n";
   }

   # if $altsrc specified and $comments is empty, try to fill the
   # comments using $altsrc
   if ($reftag && $altsrc && !$comments)
   {
      $comments =
          "<script type='text/javascript'>"
        . "var xmlhttp = openURL('$altsrc');"
        . "if (xmlhttp) {"
        . "   document.write(getHeaderText(xmlhttp,'$name'));" . "}"
        . "</script>";
   }

   $comments = "&nbsp" if (not $comments);

   # Indicate guessed comments
   $comments = "<font color='gray'>? $comments</font>" if ($guessed);

   # Print comments
   if ($comments_type eq "preformatted") {

      # Preformatted comments: print $comment inside <PRE>
      # block
      # Create an indent-string and prepend to comments
      #  if wanted
      my $s = $indentspace x $indent . $comment_indent;
      $comments =~ s/^/$s/m if $indent;

      # Remove carriage returns at start and end of line
      $comments =~ s/^\n*//s;
      $comments =~ s/\n*$//s;

      # Replace remaining carriage returns by <BR>
      $comments =~ s/\n/<BR>/s;

      # Print the comments in a <PRE> block
      print OUT "<PRE>$comments</PRE>\n";
   } else {
      # HTML/smart-comment: print outside <PRE> block

      # Create indentation
      print OUT "<DL><DD><DL><DD>\n" if $indent;

      if ($comments_type eq "html")
      {

         # HTML-comments are already OK: do nothing
      } elsif ($comments_type eq "smart") {

         # Convert smart comments to HTML format
         $comments = smart2html($comments);
      } else {
         my_die("Unsupported comments type `$comments_type'");
      }

      # Do some fixes
      $comments =~ s/<P>\n(<P>\n)+/<P>\n/g;
      $comments =~ s/<P>\n$//;
      $comments =~ s/^<P>\n//;
      $comments =~ s/<P>/<DD>/g if $indent;

      # Replace carriage returns by <BR>
      $comments =~ s/\n/<BR>/s;

      # Print the HTML-comment and restart the PRE-block
      # if that is appropriate.
      print OUT $comments . "\n";
      print OUT "</DL></DL>\n" if $indent;
   }
}

# --------------------------------------------------------------------------
sub do_source($$$$$$$$;$)
{

=head2 do_source(\@source, \@header_vars, \@common_vars, \@local_vars,
                 \@types, \@interfaces, \@calls, $firstline, $lastline);

   Output the source in pretty HTML-format, with marks for line
   numbers and links to all known items

   INPUT VARIABLES
       @source      - the lines of source code
       @header_vars - array of header variable structures
       @common_vars - array of common bock variable structures
       @local_vars  - array of local variable structures
       @types       - array of type declarations
       @interfaces  - array of interface declarations
       @calls       - array of called subroutine names
       $firstline   - line number of first line
       $lastline    - line number of last line (optional)

=cut

   my @source      = @{$_[0]}; shift;
   my @header_vars = @{$_[0]}; shift;
   my @common_vars = @{$_[0]}; shift;
   my @local_vars  = @{$_[0]}; shift;
   my @types       = @{$_[0]}; shift;
   my @interfaces  = @{$_[0]}; shift;
   my @calls       = @{$_[0]}; shift;
   my $firstline   = shift;
   my $lastline    = shift;

   # source is preformatted
   print OUT "\n<PRE>\n";

   # Constants
   # Use temporary strings for HTML codes, so they won't get highlighted
   my $ahref = 'ThisIsATemporaryReplacementOfAandHREF';
   my $a     = 'ThisIsATemporaryReplacementOfClosingA';

   # Extract names from arrays of structs
   my @var_names;
   map { push(@var_names, $_->{name}); } (@header_vars, @common_vars);
   my @type_names;
   map { push(@type_names, $_->{name}); } @types;
   my @interface_names;
   map { push(@interface_names, $_->{name}); } @interfaces;
   my @local_names;
   map { push(@local_names, $_->{name}); } @local_vars;

   # Remove otherwise known items from the list of built-in statements
   my @otherwise_known = (@var_names, @type_names, @interface_names, @local_names, @calls);
   my @statements;
   foreach my $s (@stmts::builtin_statements) {
      push(@statements, $s) unless grep { $_ eq $s } @otherwise_known;
   }

   # Escape special characters used in operators
   foreach my $name (@interface_names) {
      $name =~ s/\(/\\(/;
      $name =~ s/\)/\\)/;
      $name =~ s/\*/\\*/;
      $name =~ s/\+/\\+/;
   }

   my $variablenames  = lc(join('|', @var_names));
   my $typenames      = lc(join('|', @type_names));
   my $interfacenames = lc(join('|', @interface_names));
   my $localnames     = lc(join('|', @local_names));
   my $callednames    = lc(join('|', @calls));
   my $stmtnames      = lc(join('|', @statements));

   my $file     = $htmlfile;
   my $typefile = $file;
   $typefile =~ s/.html/_types.html/i;
   my $interfacefile = $file;
   $interfacefile =~ s/.html/_interfaces.html/i;
   my $localfile = $file;
   $localfile =~ s/\.html/_variables.html/;
   my $calledfile = $file;
   $calledfile =~ s/\.html/_subroutines_called.html/;

   # Copy the source file contents into HTML file
   $lastline = $#source unless $lastline;
   foreach my $iline (0 .. $lastline)
   {
      my $jline = $iline + $firstline;

      my ($code, $comment) = code_and_comment($source[$iline]);
      $code    =~ s/[\n\r]//g;
      $comment =~ s/[\n\r]//g;

      # if comments aren't specified as HTML, replace < and >
      unless ($comments_type eq 'html')
      {
         $comment = txt2html($comment);
      }

      # The ##$1## will be replaced with a lower case version of that string
      my @replacements;
      my @ref_files;
      if ($variablenames) {
         while ($code =~ /\b($variablenames)\b/i) {
            my $nreplacements=@replacements;
            push(@replacements,$1);
            push(@ref_files,$file);
            $code =~ s/\b($variablenames)\b/##$nreplacements##/i;
         }
      }

      if ($typenames) {
         while($code =~ /\b($typenames)\b/i) {
            my $nreplacements=@replacements;
            push(@replacements,$1);
            push(@ref_files,$typefile);
            $code =~ s/\b($typenames)\b/##$nreplacements##/i;
         }
      }

      if ($interfacenames) {
         while ($code =~ /\b($interfacenames)\b/i) {
            my $nreplacements=@replacements;
            push(@replacements,$1);
            push(@ref_files,$interfacefile);
            $code =~ s/\b($interfacenames)\b/##$nreplacements##/i;
         }
      }

      if ($localnames) {
         while ($code =~ /\b($localnames)\b/i) {
            my $nreplacements=@replacements;
            push(@replacements,$1);
            push(@ref_files,$localfile);
            $code =~ s/\b($localnames)\b/##$nreplacements##/i;
         }
      }

      if ($callednames) {
         while ($code =~ /\b($callednames)\b/i) {
            my $nreplacements=@replacements;
            push(@replacements,$1);
            push(@ref_files,$calledfile);
            $code =~ s/\b($callednames)\b/##$nreplacements##/i;
         }
      }


      foreach my $i (0 .. $#replacements) {
         my $repl = lc($replacements[$i]);
         $code =~ s/##$i##/<$ahref='$ref_files[$i]#$repl'>$replacements[$i]<\/$a>/;
      }
      $code =~ s/$ahref/A\ HREF/gi;
      $code =~ s/$a/A/gi;

      # Syntax highlight the built-in statements that aren't known otherwise
      $code =~ s/([^%#<>]?)\b($stmtnames)\b/$1<font color='#aa2200'>$2<\/font>/ig
        if $stmtnames;
      $code =~ s/\.(eq|ne|le|lt|ge|gt|true|false|not)\./<font color='#cc00cc'>.$1.<\/font>/ig;

      my $line_no = $jline;
      while (length($line_no) < 3) { $line_no = " $line_no"; }
      print OUT "<A NAME=\"$jline\">$line_no : </A>" . "$code<font color=\"#007700\">$comment</font>\n";
   }

   # source is preformatted
   print OUT "\n</PRE>\n";
}

# --------------------------------------------------------------------------
sub smart2html ($)
{

=head2 $comments = smart2html ($comments)

    Convert smart comments to HTML comments

    INPUT VARIABLES
       $comment - 'smart format' comments
    OUTPUT VARIABLES
       $comment - HTML-format comments

=cut

   my $comments = shift;

   my @newcomments = ();    # each array item is a line of
                            # converted comments

   my @listmode = ();       # monotonously increasing list of all
                            #    indentation depths currently in use
                            # Initialization means: not in list mode
                            #    (itemize/enumerate)
   my $verbmode = 0;        # Initialize: not in verbatim mode
                            #    (i.e. not in <PRE> block)
   foreach my $line (split("\n", $comments)) {

      if ($verbmode) {
         # Verbatim mode (text in <PRE> block):

         # Warn for re-starting verbatim mode
         #   remove re-starting code and add to comments
         if ($line =~ /^>/) {
            warn "`$line' found while already in verbatim mode";
            substr($line, 0, 1) = " ";
            push @newcomments, $line;
            next;
         }

         # Line starts with '<' (Last line of verbatim):
         #   add to comments and end <PRE>-block
         if ($line =~ /^</) {
            $verbmode = 0;
            substr($line, 0, 1) = " ";
            push @newcomments, $line . "</PRE>";
            next;
         }

         # Line starts with 'v' (line is <PRE> block by itself)
         #   Warn, remove code and add to comments
         if ($line =~ /^v/) {
            warn "`$line' found while already in verbatim mode";
            substr($line, 0, 1) = " ";
            push @newcomments, $line;
            next;
         }

         # Otherwise, just add to comment block
         push @newcomments, $line;
         next;
      }

      # Convert text between '_' (e.g. _italic_) into
      # HTML-code for italic text
      while ($line =~ /(\A|\W)_(\w|\w.*?\w)_(\Z|\W)/) {
         my ($left, $mid, $right) = ("$`$1<I>", $2, "</I>$3$'");
         $mid =~ s/_/ /g;
         $line = $left . $mid . $right;
      }

      # Convert text between '*' (e.g. *bold*) into
      # HTML-code for bold text
      while ($line =~ /(\A|\W)\*(\w|\w.*?\w)\*(\Z|\W)/) {
         my ($left, $mid, $right) = ("$`$1<STRONG>", $2, "</STRONG>$3$'");
         $mid =~ s/\*/ /g;
         $line = $left . $mid . $right;
      }

      # Lists:
      #  If the line starts with a '-'
      if ($line =~ /^( *)-/) {
         my $newlistmode = length($1);

         # First, make the indentation level correct
         if (!@listmode || $newlistmode > $listmode[$#listmode]) {

            # Start of list mode or start of new list indentation level
            push @listmode,    $newlistmode;
            push @newcomments, " " x $listmode[$#listmode] . "<UL>";
         } else {

            # Unindent until the indentation level matches
            while ($listmode[$#listmode] != $newlistmode) {
               push @newcomments, " " x $listmode[$#listmode] . "</UL>";
               pop @listmode;
               my_die ("Unindented to invalid position in `$line'")
                 unless @listmode;
            }
         }

         # Now, add the new line to the list
         push @newcomments, " " x $listmode[$#listmode] . "<LI> " .
                            substr($line, length($&)) . '</LI>';
      } elsif ($line =~ /^>/) {

         # Line starts with '>': switch to verbatin mode
         warn "Verbatim mode started in list mode" if @listmode;
         $verbmode = 1;
         substr($line, 0, 1) = " ";
         push @newcomments, "<PRE>" . $line;

         # Ignore $line =~ /^</ because it may be an HTML tag.

      } elsif ($line =~ /^v/) {

         # Line starts with 'v': single line in verbatim mode
         warn "One-line verbatim in list mode" if @listmode;
         substr($line, 0, 1) = " ";
         push @newcomments, "<PRE>$line</PRE>";
      } elsif ($line =~ /^\s*$/) {

         # Empty line: new paragraph
         push @newcomments, "<P>";
      } elsif (@listmode) {

         # New line in list mode that does not start with '-':
         # Unindent and add the line
         $line =~ /^( *)(\t?)/;
         warn "Tabs have strange effects on indentation detection"
           if length($2) > 0;
         while (@listmode && $listmode[$#listmode] > length($1)) {
            push @newcomments, " " x $listmode[$#listmode] . "</UL>";
            pop @listmode;
         }
         push @newcomments, $line;
      } else {

         # No 'smart-directives' in this line: just add the line 'as is'
         push @newcomments, $line;
      }
   }

   # Unindent all possibly still open indentations
   foreach my $list (@listmode) {
      push @newcomments, " " x $list . "</UL>";
   }

   # End verbatim
   push @newcomments, "</PRE>" if $verbmode;

   # Collect the converted comments into a string and return them
   $comments = join("\n", @newcomments);
   return $comments;
}

#----------------------------------------------------------------------
sub var2str
{
   my ($var, $href) = @_;
   my ($typestr) = typing::type_to_f90($var->{'vartype'});
   my ($initial) = (
      !exists $var->{'initial'}
      ? ""
      : " $var->{'initop'} " . typing::expr_to_f90($var->{'initial'})
   );
   $href = txt2html($var->{'name'}) unless $href;
   return $typestr . lc(join("<br>", "", attriblist($var))) .
          " :: $href$initial";
}

#----------------------------------------------------------------------
sub var2cols
{

   my ($var, $href, $optcol) = @_;
   my $cols;
   $href = txt2html($var->{'name'}) unless $href;
   my $typestr = lc(typing::type_to_f90($var->{'vartype'}));

   #   my $initial = (
   #                  !exists $var->{'initial'}
   #                  ? ""
   #                  : " $var->{'initop'} " . typing::expr_to_f90($var->{'initial'})
   #                 );
   my %attribs = attribhash($var);

   $cols = "$href</td><td class=\"indexvalue\">$typestr</td>";


   foreach my $field ('dimension', 'intent_vis', 'save_optional',
                      'parameter') {
      if ( $optcol->{$field}) {
         if ($attribs{$field}) {
            $cols .="<td class=\"indexvalue\">$attribs{$field}</td>";
         } else {
            $cols .="<td class=\"indexvalue\">&nbsp</td>";
         }
      }
   }

   return $cols;
}

#----------------------------------------------------------------------
sub update_optcol
{
   my ($var, $optcol) = @_;
   my $typestr = typing::type_to_f90($var->{'vartype'});
   my %attribs = attribhash($var);
   $optcol->{dimension}     |= ($attribs{dimension})     ? 1 : 0;
   $optcol->{intent_vis}    |= ($attribs{intent_vis})    ? 1 : 0;
   $optcol->{save_optional} |= ($attribs{save_optional}) ? 1 : 0;
   $optcol->{parameter}     |= ($attribs{parameter})     ? 1 : 0;

   #   $optcol->{initial}       |= ($var->{initial})         ? 1 : 0;
}

# --------------------------------------------------------------------------
sub txt2html($)
{
   my $txt = shift;
   return '' unless $txt;
   $txt =~ s/</&lt;/g;
   $txt =~ s/>/&gt;/g;
   $txt =~ s/&lt;(.+)&gt;/<$1>/g;    # Try to fix HTML tags
   return $txt;
}

############################################################################
sub attriblist
{
   my ($struct) = @_;
   my @attribs = ();

   push @attribs, @{$struct->{'tempattribs'}}
     if exists $struct->{'tempattribs'};
   push @attribs, "parameter"      if exists $struct->{'parameter'};
   push @attribs, "save"           if exists $struct->{'save'};
   push @attribs, "external"       if exists $struct->{'external'};
   push @attribs, "intrinsic"      if exists $struct->{'intrinsic'};
   push @attribs, "optional"       if exists $struct->{'optional'};
   push @attribs, $struct->{'vis'} if exists $struct->{'vis'};

   return @attribs;
}

############################################################################
# Only for variable rows; puts several attributes in a single column
# (those attributes should not occur together). In addition, ignores
# some uninteresting attributes like external and intrinsic.
sub attribhash
{
   my ($struct) = @_;
   my %attribs;

   foreach my $a (@{$struct->{'tempattribs'}}) {
      my $b = $a;
      $b =~ s/^dimension//i;
      $attribs{dimension}  = lc($b) if ($a =~ /^dimension/i);
      $attribs{intent_vis} = lc($a) if ($a =~ /^intent/i);
   }
   $attribs{intent_vis}    = lc($struct->{'vis'}) if exists $struct->{'vis'};
   $attribs{save_optional} = 'save'               if exists $struct->{'save'};
   $attribs{save_optional} = 'optional'           if exists $struct->{'optional'};
   $attribs{parameter}     = 'parameter'          if exists $struct->{'parameter'};

   return %attribs;
}

############################################################################
sub externals_to_htmldir() {

   if ($do_html) {
      # Copy all external files to the html directory
      foreach my $file ( glob("\"$Bin/figs/tab_*.*\""), 
                         glob("\"$Bin/figs/*.css\""),
                         glob("\"$Bin/figs/*.js\"") ) {
        copy( $file, $html_output_path );
      }

      # Finally, start tree2html.pl
      tree2html();
   }
}

1;
