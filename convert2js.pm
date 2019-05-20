#!/usr/bin/perl
#----------------------------------------------------
# Create from the calltree.asc file -
#    - containing the package calling tree info
# the:
#    calltree.html
#    *.js
#
# input : calltree.asc
# output: calltree.html
#---------------------------------------------------
#
package convert2js;
use strict;
use warnings;

use FindBin ('$RealBin');
use lib $RealBin;
use File::Basename;
use File::stat;
use IO::Handle;
use utils ('my_die');

use vars ('$VERSION', '@EXPORT_OK', '@ISA');
$VERSION = '1.0';
@ISA     = ('Exporter');

our @EXPORT_OK = ('convert2js');

my $version = '$Revision: 162 $';
$version =~ s/\$//g;

our $idebug = 0;

sub output_html($$)
{

=head2 output_html($calltreename,\@parent_id);

   Write the HTML-file, with references to the top-level entries

   INPUT VARIABLES
      @parent_id    - the entries at top-level
      $calltree_out - name of the output file (HTML-file)

=cut

   my $calltreename = shift;
   my $calltree_out = "$calltreename.html";
   my @parent_id = @{$_[0]}; shift;

   my $select_call='';
   $select_call = 'selected' if $calltree_out =~ /call/i;
   my $select_cont='';
   $select_cont = 'selected' if $calltree_out =~ /cont/i;

   # Open the new html-outfile and the template-infile
   my $CALLTREE_OUT;
   open $CALLTREE_OUT,">$calltree_out"
        or my_die("Cannot open '$calltree_out' for writing");
   open SCRIPT, "<$RealBin/figs/header.html"
        or my_die("Cannot open file '$RealBin/figs/header.html' for reading");

   # copy the lines from input to output, applying the necessary replacements
   while (my $line = <SCRIPT>) {
      $line =~ s/<option value="call/<option $select_call value="call/;
      $line =~ s/<option value="cont/<option $select_cont value="cont/;
      if ($line =~ /INSERT SCRIPTS HERE/) {
         print $CALLTREE_OUT
            "       <script type=\"text/javascript\" src=\"root_$calltreename.js\"></script>\n";
         foreach my $elem (@parent_id) {
            print $CALLTREE_OUT
               "       <script type=\"text/javascript\" src=\"${elem}_$calltreename.js\"></script>\n";
         }
      } else {
         print $CALLTREE_OUT $line;
      }

   }
   close SCRIPT;
   close $CALLTREE_OUT;
}

sub output_initial_header($)
{

   # utility to output the initial calling tree js header

   my $PARENTJS = shift;

   print $PARENTJS
        "  var tree;\n".
        "  function treeInit()\n".
        "  {\n".
        "    tree = new YAHOO.widget.TreeView(\"treeDiv1\");\n".
        "    tree.setDynamicLoad(loadDataForNode);\n".
        "    tree.subscribe(\"collapse\", function(node){ \n" .
        "       // -- remove the dynamic loaded child data after collapse of node --\n" .
        "       tree.removeChildren(node);\n" .
        "    }); \n" .
        "    var root = tree.getRoot();\n";

}

sub output_initial_footer($$)
{
   my $PARENTJS = shift;
   my $calltreename= shift;

   # utility to output the calling tree js footer

   print $PARENTJS
        "tree.draw();\n".
        "}\n".
        "\n".
        "function loadDataForNode(node, onCompleteCallback)\n".
        "{\n".
        "   var id= node.data.id;\n".
        "   // -- load the data, use dynamic functions defined in *_$calltreename.js --\n".
        "    window[id](node,onCompleteCallback);\n".
        "   // --scroll expanded node to top of view (if possible) \n".
        "   document.getElementById(node.contentElId).scrollIntoView(true);\n".
        "}\n".
        "\n";
        "function unloadDataForNode(node, onCompleteCallback)\n".
        "{\n".
        "   var id= node.data.id;\n".
        "   // -- remove the dynamic loaded data after collapse of node --\n".
        "   tree.removeChildren(id);\n".
        "}\n";

}

sub output_node_header($$)
{
   # utility to output the calling tree js header for a node

   my $PARENTJS  = shift;
   my $fnam  = shift;

   print $PARENTJS
      "function $fnam(node, onCompleteCallback)\n".
      "{\n";
}

sub output_node_footer($)
{
   # utility to output the calling tree js footer for a node
   #
   my $PARENTJS  = shift;

   print $PARENTJS
        "     // notify the TreeView component when data load is complete\n".
        "     onCompleteCallback();\n".
        "}\n";

}

sub add_expand_node($$$$$$$)
{
   # utility to add an expandable node to the tree
   # NOTE: target is always 'basefrm'
   #
   my $skip  = shift;
   my $PARENTJS  = shift;
   my $qid   = shift;
   my $pid   = shift;
   my $ftype = shift;
   my $fnam  = shift;
   my $url   = shift;

   my $label = $fnam; $label =~ s/__/./g;

   if ($idebug){
      print "add-expand-node: $qid, $pid, $fnam, $url\n";
   }

   if( $pid eq 'root' ) {
      print $PARENTJS
         "var myobj = { label: \"$label\", id: \"$fnam\", href: \"$url\", target:\"basefrm\" };\n" .
         "var tmpNode$qid = new YAHOO.widget.TextNode(myobj, $pid, false);\n";
   } else {
      # if ( not $skip) {
      print $PARENTJS
         "   var myobj = { label: \"$label\", id: \"$fnam\", href: \"$url\", target:\"basefrm\" };\n" .
         "   var tmpNode$qid = new YAHOO.widget.TextNode(myobj, node, false);\n";
   }
}

sub add_single_node($$$$$$$)
{
   # utility to add a leaf node to the tree
   # if  add to pid
   # NOTE: target is always 'basefrm'
   #
   my $skip  = shift;
   my $PARENTJS  = shift;
   my $qid   = shift;
   my $pid   = shift;
   my $ftype = shift;
   my $fnam  = shift;
   my $url   = shift;

   if ($idebug){
      print "add_single_node: $qid, $pid, $fnam, $url\n";
   }

   if( $pid eq 'root' ) {
      print $PARENTJS
         "var myobj = { label: \"$fnam\", id: \"$fnam\", href: \"$url\", target:\"basefrm\" };\n" .
         "var tmpNode$qid = new YAHOO.widget.TextNode(myobj, $pid, false);\n" .
         "tmpNode$qid.isLeaf = true; \n" ;
   } elsif (not $skip) {
      print $PARENTJS
         "   var myobj = { label: \"$fnam\", id: \"$fnam\", href: \"$url\", target:\"basefrm\" };\n" .
         "   var tmpNode$qid = new YAHOO.widget.TextNode(myobj, node, false);\n" .
         "   tmpNode$qid.isLeaf = true; \n" ;
   }
}



sub asc2js($) {

=head2 asc2js($calltreename)

   Convert the calltree, recorded in ASC-format in file $calltree_in, to
   the HTML-file $calltree_out.

   INPUT VARIABLES
      $calltree.asc  - name of the input file (ASCII-file)
      $calltree.html - name of the output file (HTML-file)

=cut

   my $calltreename  = shift;

   my $calltree_in  = "$calltreename.asc";
   my $calltree_out = "$calltreename.html";

   if ($idebug){
      print "Converting ASCII-calltree to HTML-file\n".
            "Input file : $calltree_in\n".
            "Output file: $calltree_out\n";
   }

   # Create names for different files based on incoming calltree.
   #
   # Var.      Ext.      Description.
   #
   # Open files for read or write and get filehandles.
   my $CALLTREE_IN;
   open $CALLTREE_IN,"<$calltree_in"
        or my_die("Cannot open '$calltree_in' for reading");

   my @PARENTJS;
   my @parent_id ;
   my @level_names ;

   my $uniq_id= 0;
   my $pid=0;
   my $skip = 0;
   my $level  = 0;
   $parent_id[$pid]="root";

   my $name="$parent_id[$level]_$calltreename.js";
   open $PARENTJS[$level],">$name"
      or my_die("Cannot open '$name' for writing");
   #
   # output the initial tree
   #
   output_initial_header($PARENTJS[$level]);

   # Scan the calltree ascii file:
   #
   while ( my $line = <$CALLTREE_IN> ) {
      chomp $line;
      next if $line =~ /^\s*$/;
      $uniq_id++;

      # get type,name and url from line

      (my $unkn,$name,my $url) = split(/,/, $line);
      next if ($name =~ /^\s*$/);
      $name =~ s/\./__/g;
      $name =~ s/operator\\\((.*)\\\)/operator_$1/g;
      $name =~ s/operator_\//operator_divide/g;
      $name =~ s/operator_-/operator_minus/g;
      $name =~ s/operator_\\\+/operator_plus/g;
      $name =~ s/operator_==/operator_eq/g;
      $name =~ s/operator_\\\*/operator_mult/g;
      $name =~ s/operator_&gt;=/operator_ge/g;
      $name =~ s/operator_&lt;=/operator_le/g;
      $name =~ s/operator_&gt;/operator_gt/g;
      $name =~ s/operator_&lt;/operator_lt/g;

      my @fields = split(':',$unkn);
      my $type = $fields[1];
      $url =~ s/(<*)$//; my $shift_left = length($1);

      if ($line =~ /\+:#:/) {

         $skip = 0;
         if (grep {$_ eq $name} @level_names) {
            if ($idebug){
               print "'$name' already processed!\n" ;
            }
            $skip=1;
         }

         add_expand_node( $skip, $PARENTJS[$level], $uniq_id, $parent_id[$pid], $type, $name, $url);

         $level++;

         if ( not $skip ) {
            push (@level_names,$name);
            my $nodejs = "${name}_$calltreename.js";

            # Open node file for write and get filehandles.
            open $PARENTJS[$level],">$nodejs"
               or my_die("Cannot open '$nodejs' for writing");
            output_node_header( $PARENTJS[$level], $name );
         } else {
            my $nodejs = "empty_$calltreename.js";
            # Open node file for write and get filehandles.
            open $PARENTJS[$level],">$nodejs"
               or my_die("Cannot open '$nodejs' for writing");
         }
         $pid++;
         $parent_id[$pid] = $name;
      } else {
         add_single_node( $skip, $PARENTJS[$level], $uniq_id,$parent_id[$pid], $type, $name, $url );
      }

      $pid -= $shift_left;
      foreach my $i ( 1 .. $shift_left) {
         output_node_footer($PARENTJS[$level]);
         close( $PARENTJS[$level] );
         $level--;
      }

      if ($idebug and $shift_left>0){
         print "name='$name': moving $shift_left levels back to level $level\n";
      }
   }

   if ($idebug){
      print "Now at level: $level\n";
   }
   output_initial_footer( $PARENTJS[$level], $calltreename );

   # start outputting the html file
   #
   output_html( $calltreename, \@level_names );

   close($PARENTJS[$level]);
   close($CALLTREE_IN);

   unlink ("empty_$calltreename.js");
}

sub convert2js($) {
   my $calltreename = shift; 
   $calltreename =~ s/\.asc//;
   asc2js($calltreename);
};

1;
