# Copyright (C) 2009-2010  Planbureau voor de Leefomgeving (PBL)
#
# full notice can be found in LICENSE

package tree2html;

use strict;
use warnings;

use File::DosGlob('glob');
use File::Path('mkpath');
use utils('my_die');
use convert2js('convert2js');

use vars ('$VERSION', '@EXPORT_OK', '@ISA');
$VERSION = '1.0';
@ISA     = ('Exporter');

our @EXPORT_OK = ('tree2html', 'prepareTrees', 'whatCalls', 'calledBy',
                  'whatContains', 'make_key', 'split_key',
                  'getModuleName', 'tryToFindFunction',
                  'write_treelog', 'close_treelog', 'set_treeoption',
                 );

my $version = '$Revision: 170 $';
$version =~ s/\$//g;

# Different levels of types, in (more or less) decreasing order
my $levels = "directory file program module interface subroutine function";

# Graphviz bit flags
my $GV_ENABLE    = 1;
my $GV_CONTAINER = 2;
my $GV_JOIN      = 4;

# Virtual module that indicates "no module"
my $NO_MODULE = 'module://no module';

# Options/settings:
#   'no_interface_call' - boolean flag indicating that routines called
#                         by an interface shouldn't be contained in the call tree.
#   'hide'              - list of values to ignore when writing the call tree.
#   'graphviz'          - also procedure GraphViz output.
my %options;

# Made these hashes module-level due to the preread functionality
my %display_name;
my %what_describes;
my %called_by;
my %what_calls;
my %used_by;
my %what_uses;
my %what_contains;
my %contained_by;
my %what_exports;
my %exported_by;

my  $treelog          = 0;
our $treefilename     = 'tree.log';
our $update_treelog   = 1;
our $tree_output_path = 'html';
our $welcome          = 'welcome_fordocu';
our $skip_unknown     = 0;


sub set_treeoption($;$){
   my $option = shift;
   if (not @_)  {
      if    ($option eq 'update_treelog'          ) { $update_treelog = 1;}
      elsif ($option eq 'dont_update_treelog'     ) { $update_treelog = 0;}
      elsif ($option eq 'skip_unknown'            ) { $skip_unknown   = 1;}
      else          {my_die("unknown option '$option'"); die;}
   } else {
      if    ($option eq 'welcome')     { $welcome         = shift;}
      elsif ($option eq 'output_path') { $tree_output_path= shift;}
      else          {my_die("unknown option '$option'"); die;}
  }
}

sub make_key($$;$)
{

=head2 $key = make_key($type, $name, $modulename)

      Generate a standardized key value from given $type and $key

      INPUT VARIABLES
         $type - type information
         $name - name information
         $modulename - module name (optional)
      OUTPUT VARIABLES
         $key  - generated key

=cut

   # DO NOT USE REGEXP IN THIS FUNCTION!
   my ($type, $name, $modulename) = @_;
   my $to_ret = lc($type) . '://' . ($modulename ? lc($modulename) . '::' : '') .
                                ($type eq 'htmlpage' ? $name : lc($name));
   return $to_ret;
}

sub split_key($)
{

=head2 ($type, $name) = split_key($key)

      Return type and name information from given $key.
      If the return value has to be a scalar, only the name is returned.

      INPUT VARIABLES
         $key  - provided key
      OUTPUT VARIABLES
         $type - type information
         $name - name information

=cut

   my ($key) = @_;
   $key =~ /(.*):\/\/(.+)/;
   my_die "No name found in $key\n" unless $2;
   return ($1, $2) if wantarray;
   return $2;
}

sub getDisplayName($$)
{

=head2 ($dispname) = getDisplayName($key, \%display_name)

      Produce a display name for the given key

      INPUT VARIABLES
         $key           - provided key
         \%display_name - struct with display names
      OUTPUT VARIABLES
         $dispname - display name produced

=cut

   my $key          = shift;
   my $display_name = shift;

   # Beautify name to display name
   my ($type, $name) = split_key($key);
   my $dispname = $name;
   $dispname = $display_name->{$key} if (defined $display_name->{$key});
   $dispname =~ s/.*:://i
     if (   $type eq "subroutine"
         || $type eq "function"
         || $type eq "interface");
   $dispname =~ s/.*[\\\/]([^\\\/]*)$/$1/
     if ($type eq "file" || $type eq "directory");
   $dispname = $name unless ($dispname);
   return $dispname;
}

sub hidden($$)
{

=head2 $hidden = hidden($name, \@hidden_things)

      Check whether an item should be hidden from the calltree

      INPUT VARIABLES
         $name          - name to be checked
         @hidden_things - array of strings which should be hidden
      OUTPUT VARIABLES
         $hidden        - $name should be hidden (1) or not (0)

=cut

   my ($name, $hidden_things) = @_;
   my $hidden = 0;

   return $hidden unless (@{$hidden_things});

   $hidden = 1 if grep(/\b$name\b/i, @{$hidden_things});
   my $nam = $name;
   $nam =~ s/::.*//;
   $hidden = 1 if grep(/\b$nam\b/i, @{$hidden_things});
   $nam = $name;
   $nam =~ s/.*:://;
   $hidden = 1 if grep(/\b$nam\b/i, @{$hidden_things});
   return $hidden;
}

sub writeTree($$$$$$$$);    # Recursive

sub writeTree($$$$$$$$)
{

=head2 writeTree($key, \%called_by, \%display_name, \%what_describes,
   $margin, $last, $trace, $is_calltree);

Print the condensed code for the calling tree starting at
   a given routine

   INPUT VARIABLES
      $key            - key of the routine where to start
      %called_by      - struct with field names corresponding to
                        routine names and values names of called routines
      %display_name   - display name information
      %what_describes - link information
      $margin         - string, consisting of ' ' and '|' characters,
                        coding the margin
      $last           - flag: this is the last call from the parent 
                              routine yes/no
      \@trace         - list of routines that lead to the current call in <>
      $is_calltree    - flag indicating whether this is a calltree

=cut

   my ($key, $called_by, $display_name, $what_describes, 
       $margin, $last, $trace, $is_calltree) = @_;
   my ($type, $name) = split_key($key);

   #$key =~ s/[\n\r]//g;
   my_die "There must be something wrong\n\n$trace\n\n"
     if length($margin) > 100;

   # Don't handle variables
   return if $type eq 'variable';
   return if ($type eq 'file' and $is_calltree);
   return if ($type eq 'directory' and $is_calltree);

   # Check whether this item will be hidden
   return if hidden($name, $options{'hide'});

   # Check whether this is a recursive call
   # (do not print recursion on directory level to STDOUT)
   my $recursive = 0;
   if ($trace =~ m/<$key>/i) {

      #print "recursive call $trace : $key\n" unless $type eq 'directory';
      $recursive = 1;
      return if $type eq 'interface'; # Interfaces won't recurse into themselves
   }
   $trace .= "<$key>";

   # options{'no_interface_call'} is set and this is an interface.
   my $final_interface = ($is_calltree and $options{'no_interface_call'} and
                          $type eq "interface");

   # Count the number of calls from this routine
   my @my_calls = ();
   if (!$final_interface) {
      foreach my $c (@{$called_by->{$key}}) {
         my $n = split_key($c);
         if ( not hidden($n, $options{'hide'}) and not
              ($skip_unknown and not defined($what_contains{$c})) ) {
            push(@my_calls,$c);
         }
      }
   }

   # First, print the margin on a new line
   print OUT "\n$margin";

   # Next, print indications of 'last routine in the row'
   # and 'routine calls others', if appropriate
   print OUT "\\" if ($last);
   print OUT "+" if (@my_calls > 0 and not $recursive);

   # Determine describer
   my $describer_name = '';
   $describer_name = split_key($what_describes->{$key})
     if ($what_describes->{$key});

   # Beautify name to display name
   my $dispname = getDisplayName($key, $display_name);
   $dispname .= " (recursive)" if $recursive && $key ne $NO_MODULE;

   # Now, print the routine name
   print OUT ":#:$type,$dispname,$describer_name";

   # If this is a calltree and options{no_interface_call} is not set,
   # we are ready if this is an interface.
   return if $final_interface;

   if (@my_calls > 0 and not $recursive) {
      # This routine calls other routines: recursively
      # print their calltree

      # First sort on display name
      my %called;
      my @calledkeys=();
      my $count = 0;
      foreach my $call (@my_calls) {
         my $dname = lc($display_name->{$call});
         $dname =~ s/(.+)::(.+)/$2/;
         $dname .= sprintf("%04d", $count);
         $called{$dname} = $call;
         push(@calledkeys,$dname);
         $count++;
      }

      my $icalls    = 0;
      my $newmargin = "$margin ";
      if (not $last) { $newmargin = "$margin|"; }
      foreach my $call_dname (@calledkeys) {
         my $call = $called{$call_dname};
         $icalls++;
         writeTree($call, $called_by, $display_name, $what_describes, 
                   $newmargin, $icalls == @my_calls, $trace, $is_calltree);
      }
      print OUT "<";
   }
   return;
}

sub createHTMLfile($$$$$)
{

=head2 createHTMLfile($name, \%tree, \@toplevel, \%display_name, \%what_describes);

   Create a HTML file from the given tree.

      INPUT VARIABLES
         $name            - name of the tree
         \%tree           - tree to write
         \@toplevel       - array with top-level elements
         \%display_name   - display information
         \%what_describes - description information

=cut

   my $name           = shift;
   my $tree           = shift;
   my $toplevel       = shift;
   my $display_name   = shift;
   my $what_describes = shift;

   # Print tree starting from all not-called/not-contained routines
   print STDERR "Writing tree  $name...\n";
   open OUT, ">$name.asc"
     or my_die("cannot open file '$name.asc' for writing");

   my $is_calltree = ($name =~ /^call/);

   foreach my $key (sort (@$toplevel)) {
      writeTree($key, $tree, $display_name, $what_describes, "", 1, '',
                $is_calltree);
   }
   close OUT;

   # Create the html-file
   convert2js("$name.asc");
}

sub createGraphvizFile($$$$$)
{

=head2 createGraphvizFile($name, \%tree, \%display_name,
                          \%contained_by, \%what_contains);

   Create a Graphviz file from the given tree.

      INPUT VARIABLES
         $name            - name of the tree
         \%tree           - tree to write
         \%display_name   - display information
         \%contained_by,
         \%what_contains  - containment information

=cut

   my $name          = shift;
   my $tree          = shift;
   my $display_name  = shift;
   my $contained_by  = shift;
   my $what_contains = shift;

   print STDERR "Writing graph $name...\n";

   # Helper function to get a color
   sub getColor($$)
   {

      my $type = shift;
      my $sep  = shift;
      my $style;

      if ($type eq "subroutine") {
        $style = 'color=blue,fillcolor=lightblue';
      } elsif ($type eq "function") { 
        $style = 'color=blue,fillcolor=lightblue';
      } elsif ($type eq "program") { 
        $style = 'color=red';                      
      } elsif ($type eq "interface") { 
        $style = 'color=purple,fillcolor=pink';
      } elsif ($type eq "module") { 
        $style = 'color=green,fillcolor=palegreen';
      } elsif ($type eq "file") { 
        $style = 'color=gray,fillcolor=lightgray';
      } elsif ($type eq "directory") { 
	$style = 'color=brown,fillcolor=yellow';
      } else { 
	$style = 'color=black,fillcolor=lightgray';
      }

      $style =~ s/,/$sep/g if $sep ne ',';
      return $style;
   }

   # Helper function to get a type, a name and a GraphViz element key
   sub gSplit($)
   {
      my $key = shift;
      my ($type, $name) = split_key($key);
      my $gkey = $key;
      $gkey =~ s/[\:|\\|\/|_|\?|\.\s]+//g;
      return ($type, $name, $gkey);
   }

   my $is_calltree = ($name =~ /^call/);
   my $interfaces_dont_call = $is_calltree && $options{'no_interface_call'};

   # Open Graphviz output
   open GRAPHVIZ, ">$name.dot"
     or my_die("cannot open file '$name.dot' for writing");
   print GRAPHVIZ "digraph G {\n"
     . "    clusterrank=local;\n"
     . "    labeljust=l;\n"
     . "    nodesep=\".1\";\n"
     . "    remincross=true;\n";
   print GRAPHVIZ "    rankdir=LR;\n";    # unless $is_calltree;
   print GRAPHVIZ "    concentrate=true;\n" if $options{'graphviz'} & $GV_JOIN;

   # Write styles for nodes
   my %nodewritten;
   foreach my $caller_key (keys %$tree) {

      # Handle container
      my ($caller_type, $caller_name, $caller_gkey) = gSplit($caller_key);
      next if $caller_type eq 'variable';
      next if (hidden($caller_name, $options{'hide'}));

      unless ($nodewritten{$caller_key}) {
         $nodewritten{$caller_key} = 1;
         my $caller_dname = getDisplayName($caller_key, $display_name);
         print GRAPHVIZ "    $caller_gkey [label=\"$caller_dname\"," .
                        getColor($caller_type, ",") . ",style=filled];\n";
      }

      # options{'no_interface_call'} is not set and this is an interface.
      next if $interfaces_dont_call && $caller_type eq "interface";

      # Handle everything called
      foreach my $callee_key (@{$tree->{$caller_key}}) {
         my ($callee_type, $callee_name, $callee_gkey) = gSplit($callee_key);
         next if $callee_type eq 'variable';
         next if (hidden($callee_name, $options{'hide'}));
         unless ($nodewritten{$callee_key}) {
            $nodewritten{$callee_key} = 1;
            my $callee_dname = getDisplayName($callee_key, $display_name);
            print GRAPHVIZ "    $callee_gkey [label=\"$callee_dname\"," .
                       getColor($callee_type, ",") . ",style=filled];\n";
         }
      }
   }

   # Write clusters
   if ($is_calltree && ($options{'graphviz'} & $GV_CONTAINER)) {
      sub cluster($$$$;$);

      sub cluster($$$$;$)
      {
         my $cont_key     = shift;
         my $contained_by = shift;
         my $display_name = shift;
         my $nodewritten  = shift;
         my $recursion    = shift;

         my ($cont_type, $cont_name, $cont_gkey) = gSplit($cont_key);
         unless ($#{$contained_by->{$cont_key}} >= 0) {
            print GRAPHVIZ "$cont_gkey; "
              if $nodewritten->{$cont_key} && !$recursion;
            return;
         }
         return if (hidden($cont_name, $options{'hide'}));
         my $cont_dname = getDisplayName($cont_key, $display_name);
         print GRAPHVIZ "\nsubgraph \"cluster_$cont_gkey\" {\n"
           . "label=\"$cont_dname\";\n"
           . getColor($cont_type, ";\n") . ";\n"
           . "style=bold;\n";
         print GRAPHVIZ "$cont_gkey; " if $nodewritten->{$cont_key};

         #            if $cont_type eq 'subroutine' || $cont_type eq 'function';
         foreach my $member (@{$contained_by->{$cont_key}}) {
            my ($mem_type, $mem_name, $mem_gkey) = gSplit($member);
            next if $mem_type eq 'variable';
            next if (hidden($mem_name, $options{'hide'}));
            if (   $contained_by->{$member}
                && $#{$contained_by->{$member}} >= 0) {
               cluster($member, $contained_by, $display_name, $nodewritten);
            } else {
               print GRAPHVIZ "$mem_gkey; " if ($nodewritten->{$member});
            }
         }
         print GRAPHVIZ "\n}\n";
      }
      foreach my $cont_key (keys %$contained_by) {
         next if $what_contains->{$cont_key};
         cluster($cont_key, $contained_by, $display_name, \%nodewritten, 1);
      }
   }

   # Write tree
   foreach my $caller_key (keys %$tree) {
      my ($caller_type, $caller_name, $caller_gkey) = gSplit($caller_key);
      next if $caller_type eq 'variable';
      next if (hidden($caller_name, $options{'hide'}));

      # options{'no_interface_call'} is set and this is an interface.
      next if $interfaces_dont_call && $caller_type eq "interface";

      foreach my $callee_key (@{$tree->{$caller_key}}) {
         my ($callee_type, $callee_name, $callee_gkey) = gSplit($callee_key);
         next if $callee_type eq 'variable';
         next if (hidden($callee_name, $options{'hide'}));
         print GRAPHVIZ "    $caller_gkey -> $callee_gkey;\n";
      }
   }

   # Close Graphviz output
   print GRAPHVIZ "}\n";
   close GRAPHVIZ;
}

sub reportStats()
{

=head2 reportStats()

   Report the number of times things are called.

=cut

   sub reportTable($$)
   {
      my ($header, $data) = @_;

      print STATS "$header\:\n", '=' x (1 + length($header)), "\n";

      # Make a new hash with the number of values in the original hash
      my %times_called;
      foreach my $routine (keys %$data) {
         my $count = 1 + $#{$data->{$routine}};
         unless ($times_called{$count}) {
            my @tmp;
            $times_called{$count} = \@tmp;
         }
         push @{$times_called{$count}}, $routine;
      }

      # Now print this hash to file, sorted decreasing
      my $maxwidth = 0;
      foreach my $times (sort { $b <=> $a } keys %times_called) {
         my $len = length($times);
         $maxwidth = $len if $len > $maxwidth;
         foreach my $routine (@{$times_called{$times}}) {
            my ($type, $name) = split_key($routine);
            $name =~ s/.+\:\:(.+)$/$1/;
            print STATS ' ' x ($maxwidth - $len), $times, ': ',
              $type, ' ' x (11 - length($type)),
              $name, ' ' x (33 - length($name));

            my $container = $what_contains{$routine};
            if ($container) {
               ($type, $name) = split_key($container);
               print STATS '(in ', $type, ' ' x (11 - length($type)), $name, ')';
            }

            print STATS "\n";
         }
      }
      print STATS "\n";
   }

   open STATS, ">stats.txt"
     or my_die("ncannot open file 'stats.txt' for writing");

###   print STDERR "Creating file 'stat.txt' in './html/stat.txt'.\n";
   reportTable('Called by ... routines/interfaces', \%what_calls);
#   reportTable('Calls ... routines/interfaces',     \%called_by);

   close STATS;
}

sub update01($$$)
{

=head2 update01($describer, $described, \%mapping)

   Process the input file and store the describers of something.
   (It's a N:1 relationship, but since it's stored in one way,
    we'll call it a 0:1 relationship)

   INPUT VARIABLES
      $describer - describer of something
      $described - name of something being described


=cut

   my $describer = shift;
   my $described = shift;
   my $mapping   = shift;

   if (defined $mapping->{$described}) {
      my $what = $mapping->{$described};
      if ($what eq "mprocedure"
          && ($describer eq "subroutine" || $describer eq "function")) {
         # 'subroutine' or 'function' are better describers than 'mprocedure'
         $mapping->{$described} = $describer;
         return;
      }
      my_die "'$described' cannot be associated with both '$describer' and " .
         "'$what'\n\n" unless ($what =~ /$describer/i);
   }
   $mapping->{$described} = $describer;
}

sub updateNN($$$$)
{

=head2 updateNN($caller, $called, \%called_by, \%what_calls)

   Process the input file and administrate which routines
   call which routines or use which modules.
   (Generally speaking these items have a N:N relationship).

   For use with 'uses', read 'use' where it says 'call'.

   INPUT VARIABLES
      $caller - name of the caller or user
      $called - name of what is being called or used

   INPUT/OUTPUT VARIABLES
      \%called_by - struct with keys corresponding to names
                    and values a struct with the following keys:
      $called_by{$routine}->{called}: keys of routines
      called by subroutine $routine
      \%what_calls- 'inverse' of %called_by

=cut

   my $caller     = shift;
   my $called     = shift;
   my $called_by  = shift;
   my $what_calls = shift;

   # Put the information in calltree
   if (not defined($called_by->{$caller})) {
      $called_by->{$caller} = [];
   }
   push(@{$called_by->{$caller}}, $called)
     unless (grep(/\b$called\b/, @{$called_by->{$caller}}));

   # Put the information in inv_calltree
   $what_calls->{$called} = []
     if (not defined($what_calls->{$called}));

   push(@{$what_calls->{$called}}, $caller)
     unless (grep(/\b$caller\b/, @{$what_calls->{$called}}));
}

sub update_contains($$$$)
{

=head2 update_contains($container, $contained, \%what_contains, \%contained_by)

      Process the input file and administrate what is contained by what.

      INPUT VARIABLES
         $container - container
         $contained - whatever is being contained
      INPUT/OUTPUT VARIABLES
         \%what_contains - struct with items contained by the key item
         fields may be directory, file, program, module, subroutine or function
         \%contained_by - struct with containers of the key item
         for fields: see \%what_contains

=cut

   my $container     = shift;
   my $contained     = shift;
   my $what_contains = shift;
   my $contained_by  = shift;

   # Check whether we already know this relation
   # Also check whether we only have a single container
   if (defined($what_contains->{$contained})) {
      my_die "'$contained' cannot be contained by both '$container'" .
             " and '$what_contains->{$contained}'\n\n"
        if $what_contains->{$contained} ne $container;

      return;
   }

   # Put the information in contained_by:
   if (not defined($contained_by->{$container})) {
      my @dum;
      $contained_by->{$container} = \@dum;
   }
   push(@{$contained_by->{$container}}, $contained)
     unless (grep(/\b$contained\b/, @{$contained_by->{$container}}));

   # Put the information in what_contains
   $what_contains->{$contained} = $container;
}

sub handle_line($$$$$$$$$$$)
{

=head2 handle_line($line, \%display_name, \%what_describes, \%called_by, 
                   \%what_calls, \%used_by, \%what_uses, \%what_contains, 
                   \%contained_by, \%what_exports, \%exported_by)

      Process a single line from the the input file and administrate
      the contents of that line by updating several hashes.

      INPUT VARIABLES
         $line - the line to process

      INPUT/OUTPUT VARIABLES
         \%display_name   - display names
         \%what_describes - which file describes the given item?
         \%called_by      - struct with keys corresponding to names
                            and values a struct with the following keys:
                            $called_by{$routine}->{called}: keys of 
                                   routines called by subroutine $routine
         \%what_calls     - 'inverse' of %called_by
         \%used_by        - analogous to \%called_by, only for USE 
                            dependencies
         \%what_uses      - analogous to \%what_calls, only for USE 
                            dependencies
         \%what_contains  - struct with items contained by the key item
                            fields may be directory, file, program, module, 
                            subroutine or function
         \%contained_by   - struct with containers of the key item for 
                            fields: see \%what_contains
         \%what_exports   - subset of \%what_contains; only contains public 
                            items
         \%exported_by    - subset of \%contained_by:  only contains public 
                            items

=cut

   my $line           = shift;
   my $display_name   = shift;
   my $what_describes = shift;
   my $called_by      = shift;
   my $what_calls     = shift;
   my $used_by        = shift;
   my $what_uses      = shift;
   my $what_contains  = shift;
   my $contained_by   = shift;
   my $what_exports   = shift;
   my $exported_by    = shift;

   # Handle "DESCRIBES" lines
   if ($line =~ /!! (.+) (.+) DESCRIBES (.+) (.+)/i) {
      my $describer = make_key($1, $2);
      my $described = make_key($3, $4);
      update01($describer, $described, $what_describes);
      return;
   }

   # Handle "CALLS" lines
   if ($line =~ /!! (.+) (.+) CALLS (.+) (.+)/i) {
      my $caller = make_key($1, $2);
      my $called = make_key($3, $4);
      updateNN($caller, $called, $called_by, $what_calls);
      return;
   }

   # Handle "USES" lines
   if ($line =~ /!! (.+) (.+) USES (.+) (.+)/i) {
      my $user = make_key($1, $2);
      my $used = make_key($3, $4);
      updateNN($user, $used, $used_by, $what_uses);
      return;
   }

   # Handle "CONTAINS" and "EXPORTS" lines
   # This updates contains relations and display names.
   # Contains doesn't contain variables
   # Exports only contains public
   if ($line =~ /!! (.+) (.+) (CONTAINS|EXPORTS) (.+) (.+)/i) {
      my $container_type = lc($1);
      my $container_name = $2;
      my $relation       = lc($3);
      my $contained_type = lc($4);
      my $contained_name = $5;
      my $container      = make_key($container_type, $container_name);
      my $contained      = make_key($contained_type, $contained_name);
      update_contains($container, $contained, $what_contains, $contained_by)
        unless $contained_type eq 'variable';
      update_contains($container, $contained, $what_exports, $exported_by)
        if $relation eq 'exports';
      update01($container_name, $container, $display_name);
      update01($contained_name, $contained, $display_name);
      return;
   }

   # Handle "OPTION INTERFACE CALLS"
   if ($line =~ /!! OPTION NO INTERFACE CALL/i) {
      $options{'no_interface_call'} = 1;
      return;
   }

   # Handle "OPTION GRAPHVIZ"
   if ($line =~ /!! OPTION GRAPHVIZ\s*(.*)/i) {
      my $flags = $1;
      $options{'graphviz'} = $GV_ENABLE;
      $options{'graphviz'} |= $GV_CONTAINER if $flags =~ /CONTAINER/i;
      $options{'graphviz'} |= $GV_JOIN      if $flags =~ /JOIN/i;
      return;
   }

   # Handle "OPTION HIDE"
   if ($line =~ /!! OPTION HIDE (.+)/i) {
      my $hide = make_key('', $1);
      push(@{$options{'hide'}}, $hide)
        unless grep(/\b$hide\b/, @{$options{'hide'}});
      return;
   }
}

sub complete_contains($$$)
{

=head2 complete_contains(\%what_contains, \%contained_by, \%display_name)

      Add directory levels to file names.

      INPUT/OUTPUT VARIABLES
         \%what_contains - struct with items contained by the key item
               fields may be directory, file, program, module, subroutine or function
         \%contained_by - struct with containers of the key item
               for fields: see \%what_contains
         \%display_name - struct with display names

=cut

   my $what_contains = shift;
   my $contained_by  = shift;
   my $display_name  = shift;

   foreach my $key (keys %{$what_contains}) {
      my $item = $what_contains->{$key};
      my ($item_type, $item_name) = split_key($item);
      if ($item_type eq "file") {
         # A file name is found - add directories
         my $contained      = $item;
         my $contained_name = $item_name;
         my $container_name = $item_name;
         my $container_show = $display_name->{$item};
         while ($container_name =~ s/[\\\/][^\\\/]+$//) {
            $container_show =~ s/[\\\/][^\\\/]+$// if ($container_show);

            my $container = make_key('directory', $container_name);
            update_contains($container, $contained, $what_contains, $contained_by);
            update01($container_show, $container, $display_name)
              if ($container_show);
            $contained      = $container;
            $contained_name = $container_name;
         }
      }
   }
}

sub find_parent($$$)
{

=head2
      ($parent) = find_parent($child, $level, \%what_contains)

      Find a parent of the given item on the given level.

      INPUT VARIABLES
         $child         - child to find the parent for
         $level         - level of the parent
         \%what_contains - struct with containers of the key item
      OUTPUT VARIABLES
         $parent        - parent found (or empty)

=cut

   my $child         = shift;
   my $level         = shift;
   my $what_contains = shift;

   my $search_index = index($levels, $level);
   my $parent = $child;
   while ($what_contains->{$parent}) {
      $parent = $what_contains->{$parent};
      my ($type, $name) = split_key($parent);
      if ($level eq $type) {

         # print "PARENT=$parent\n" if ($level eq 'file');
         # Yes, this is what we are looking for
         return $parent;
      }
      last
        if (   (!$type)
            || ($type && index($levels, $type) < $search_index));
   }
   return "";
}


sub find_routine($$$$;$);    # Recursive

sub find_routine($$$$;$)
{

=head2 find_routine($called, $caller, \%used_by, \%exported_by, \%contained_by)

   Find the called routine, following the use trail.

   INPUT VARIABLES
      $called        - key the routine to find
      $caller        - key of the caller to search
      \%used_by      - use dependencies
      \%exported_by  - exported dependencies
      \%contained_by - contained dependencies (optional)
   INPUT/OUTPUT VARIABLES
      @all_found     - name(s) found

=cut

   my $called      = shift;
   my $caller      = shift;
   my $used_by     = shift;
   my $exported_by = shift;

   my $contained_by = shift;
   $contained_by = $exported_by unless $contained_by;

   my $called_name = split_key($called);

   my @all_found = ();

   # Search all routines contained by $caller
   foreach my $contained (@{$contained_by->{$caller}}) {

      # Check whether the last part of the name matches
      if ($contained =~ /.*::$called_name$/) {
         push(@all_found, $contained);
      }
   }

   # Search all modules used by $caller
   foreach my $module (@{$used_by->{$caller}}) {
      push(@all_found, find_routine($called, $module, $used_by, $exported_by));
   }
   return @all_found;
}

sub find_missing_routines($$$$$$$$$$)
{

=head2 find_missing_routines(\%display_name, \%what_describes, \%called_by,
   \%what_calls, \%used_by, \%what_uses, \%what_contains, \%contained_by,
   \%what_exports, \%exported_by)

      Find missing routines by examining modules, use statements and such.

      INPUT VARIABLES
         \%display_name - display names
         \%what_describes - which file describes the given item?
         \%used_by   - analogous to \%called_by, only for USE dependencies
         \%what_uses - analogous to \%what_calls, only for USE dependencies
         \%what_contains - struct with items contained by the key item
            fields may be directory, file, program, module, subroutine or function
         \%contained_by - struct with containers of the key item
            for fields: see \%what_contains
         \%what_exports - public members of \%what_contains
         \%exported_by  - public members of \%contained_by
      INPUT/OUTPUT VARIABLES
         \%called_by - struct with keys corresponding to names
            and values a struct with the following keys:
            $called_by{$routine}->{called}: keys of routines
            called by subroutine $routine
         \%what_calls- 'inverse' of %called_by

=cut

   my $display_name   = shift;
   my $what_describes = shift;
   my $called_by      = shift;
   my $what_calls     = shift;
   my $used_by        = shift;
   my $what_uses      = shift;
   my $what_contains  = shift;
   my $contained_by   = shift;
   my $what_exports   = shift;
   my $exported_by    = shift;

   # Find everything that is called, but not contained
   foreach my $called (keys %$what_calls) {
      my ($called_type, $called_name) = split_key($called);
      if (!exists $what_contains->{$called}) {
         foreach my $caller (@{$what_calls->{$called}}) {
            my ($caller_type, $caller_name) = split_key($caller);
            my @all_found = ();

            # First, try to find it in the caller's container itself
            my $container = $what_contains->{$caller};
            foreach my $contained (@{$contained_by->{$container}}) {
               # Check whether the last part if the name matches 'mprocedure'
               # may only be replaced by 'subroutine' or 'function'
               my ($contained_type, $contained_name) = split_key($contained);
               if ( $contained =~ /.*::$called_name$/ and
                    (   $called_type ne 'mprocedure' or
                        $contained_type eq 'subroutine' or
                        $contained_type eq 'function') ) {
                  push(@all_found, $contained);
               }
            }

            # Then, try to find it in the modules used by the caller
            # or in case of nested routines, contained by the caller
            push(@all_found, find_routine(
                    $called, $caller, $used_by, $exported_by, $contained_by));

            # Then, try to find it in the modules used by the caller's
            # container
            push(@all_found, find_routine(
                    $called, $what_contains->{$caller}, $used_by, $exported_by))
              if defined $what_contains->{$caller};

            # Finally, try to find it in the modules used by the caller's
            # container's container
            push(@all_found, find_routine($called,
                 $what_contains->
                    {$what_contains->{$caller}}, $used_by, $exported_by))
              if defined $what_contains->{$what_contains->{$caller}};

            # If it is found, store it. Otherwise, report it.
            if (@all_found) {
               # If we have both interfaces and subroutines/functions with the
               # same name, remove the subroutines/functions. In order to do
               # that, first collect all interface names in the result set.
               my %interfaces;
               foreach my $found (@all_found) {
                  my ($type, $name) = split_key($found);
                  $interfaces{$name} = $found if $type eq 'interface';
               }

               # Make links - skip duplicates
               my $prev = '!@#$%^&*()';
               foreach my $found (sort @all_found) {
                  next if $prev eq $found;
                  $prev = $found;

                  my ($type, $name) = split_key($found);
                  next if ($interfaces{$name} && $type ne 'interface' &&
                           $caller_type ne 'interface');

                  my $updated = 0;
                  for (my $i = 0 ; $i <= $#{$called_by->{$caller}} ; $i++) {
                     if (@{$called_by->{$caller}}[$i] eq $called) {
                        @{$called_by->{$caller}}[$i] = $found;
                        $updated = 1;
                     }
                  }
                  push(@{$called_by->{$caller}}, $found) unless $updated;

                  if (not defined($what_calls->{$found})) {
                     my @dum;
                     $what_calls->{$found} = \@dum;
                  }
                  push(@{$what_calls->{$found}}, $caller);
               }
            } else {
               warn "Cannot find $called, called from $caller.\n"
                      unless $skip_unknown;
            }
         }
      }
   }
}

sub complete_options_hide($)
{

=head2

      complete_options_hide(\%contained_by)

      Not only the item specified is hidden, but also
      everything contained by it.

      INPUT VARIABLES
         \%contained_by - struct with containers

=cut

   my $contained_by = shift;

   # Find all items to hide
   foreach my $hide (@{$options{'hide'}}) {
      my ($hide_type, $hide_name) = split_key($hide);
      next if $hide_type;    # Ignore filled $hide_type

      sub hidetree($$);

      sub hidetree($$)
      {
         my $root         = shift;
         my $contained_by = shift;
         push(@{$options{hide}}, $root);    # Hide the node itself
         foreach my $also_hide (@{$contained_by->{$root}}) {
            hidetree($also_hide, $contained_by);
         }
      }
      foreach my $container (keys %{$contained_by}) {
         next
           unless $container =~ /\b$hide_name\b/;    # Container has different
                                                     # name
         hidetree($container, $contained_by);
      }
   }
}

sub tryToFindFunction($)
{

=head2

      $found = tryToFindFunction($name)

      Try to find an interface or a function based on the given name.
      Will return the key if found or an empty string if it isn't.

=cut

   my ($name) = @_;

   return '' unless $name && %display_name;

   $name = lc($name);
   foreach my $key (keys %display_name) {
      return $key if $key =~ /^(?:function|interface).*\b${name}$/;
   }
   return '';
}

sub whatContains($)
{

=head2

      $container = whatConbtains($contained)

      Returns the container of the argument.

=cut

   my $contained = shift;
   return %what_contains ? $what_contains{$contained} : '';
}

sub whatCalls($)
{

=head2
      \@callers = whatCalls($callee)

      Returns an array containing the callers of the argument.

=cut

   my $callee = shift;

   my $retval = [];
   $retval = $what_calls{$callee} if (defined $what_calls{$callee});

   return $retval;
}

sub calledBy($)
{

=head2
      \@called = calledBy($caller)

      Returns an array containing the callees of the argument.

=cut

   my $caller = shift;
   return %called_by ? $called_by{$caller} : ();
}

sub getModuleName($)
{

=head2

      $module = getModuleName($routine)

      Attempts to find a module name for the given routine name.
      Will return an empty string if no module name is found.

      Possible expansion: it is possible that multiple answers exist
                          In that case, the best answer has to be selected.
                          At present, just the first answer found is returned.

=cut

   my $routine = shift;

   foreach my $key (keys %what_contains) {
      next unless $key =~ /\/\/(.+)::$routine\b/;
      return $1;
   }
   return '';
}

sub clearTrees()
{

=head2

      clearTrees()

      Remove all data from the trees.

=cut

   %display_name   = ();
   %what_describes = ();
   %called_by      = ();
   %what_calls     = ();
   %used_by        = ();
   %what_uses      = ();
   %what_contains  = ();
   %contained_by   = ();
   %what_exports   = ();
   %exported_by    = ();
}

sub prepareTrees($)
{

=head2

      $success = prepareTrees($silent)

      Generate trees.

      INPUT VARIABLES
         $silent   - optional boolean indicating (mostly) silent operation
      RETURN VARIABLES
         $success - 1 in case of success, 0 in case of failure

=cut

   my $silent = shift;
   my $filename =  "$tree_output_path/$treefilename";

   # Clear trees
   clearTrees();

   # Read input file
   open IN, "<$filename" or return 0;
   while (my $line = <IN>) {
      handle_line($line,       \%display_name,  \%what_describes, \%called_by,
                  \%what_calls, \%used_by,
                  \%what_uses, \%what_contains, \%contained_by,   \%what_exports,
                  \%exported_by);
   }
   close IN;

   # Try to find missing subroutines/functions called
   find_missing_routines(\%display_name, \%what_describes, \%called_by,
                         \%what_calls,   \%used_by,
                         \%what_uses,    \%what_contains,  \%contained_by,
                         \%what_exports, \%exported_by);

   # Complete "options{$hide}"
   complete_options_hide(\%contained_by);

   # Generate "contains" tree
   complete_contains(\%what_contains, \%contained_by, \%display_name);

   print STDERR "Stored call tree data read\n" unless $silent;
   return 1;    # success
}

sub choose_title($$$) {

=head2

      $title = choose_title(\%display_name,\@notcontained,\@notcalled)

      Choose a title for the documentation

      INPUT VARIABLES
         %display_name - struct with display names
         @notcontained - nodes which are not contained in anything     
         @notcalled    - nodes which are not called by anything     

      RETURN VARIABLES
         $title        - the title chosen

=cut

my $display_name = shift;
my @notcontained = @{$_[0]}; shift;
my @notcalled    = @{$_[0]}; shift;
my $title = "";

   # Choose a title:
   $title = $display_name->{$notcalled[0]} if (@notcalled and $#notcalled == 0);

   
   if ( not $title ) {
      $title = $notcontained[0]  if (@notcontained and $#notcontained == 0);
   }

   if ( not $title ) {
      foreach my $key (@notcalled) {
         my ($type, $name) = split_key($key);
         if ($type eq "program") {
            $title .= ", " if $title;
            if ($display_name->{$name}) {
               $title .= $display_name->{$name}
            } else { 
               $title .= $name;
            }
         }
      }
   }

   if (not $title) {
      foreach my $name (@notcontained) {
         $title .= ", " if $title;
         $title .= $display_name->{$name};
      }
   }

   if (not $title) {
      use Cwd;
      $title = cwd;
      $title =~ s/.*\///;
   }

   $title = "Sources" unless $title;

   return $title;
}
# =====================================================================

# MAIN
sub tree2html()
{

=head1 tree2html(); 

      tree2html()

   Process the input file $treefilename and create  ASCII files 'tree.asc'
   and 'pseudo.asc' (for further processing by conv2js()).

   =head1 Input file format

   The input file should have lines of the form
   !! <UNIT TYPE1> <unit name1> <RELATION> <UNIT TYPE2> <unit name2>
   <UNIT TYPE> may be FILE, MODULE, PROGRAM, SUBROUTINE, FUNCTION,
                      ?FUNCTION, INTERFACE, HTMLPAGE, VARIABLE
   <RELATION>  may be CONTAINS, EXPORTS, CALLS, USES, DESCRIBES
   <unit name> must be uniquely describing (file names contain directory components,
   routine names contain the module)

   Also processed from the input file:
   !! OPTION NO INTERFACE CALL
   !! OPTION HIDE
   !! OPTION GRAPHVIZ [CONTAINER] [JOIN]

   =head1 Output file format

   =head1 'tree.html'

   The file 'tree.html' is a nice, graphic representation of the
   call tree. You can click on parts to collaps or expand them.

   =head2 'tree.inp'

   Every line in the calltree-file has a simple structure
   An example of the input is:

   \+:#:qq,qq
   \+:#:aadate,aadate
   :#:sadate,sadate
   \:#:sadate,sadate<<

   Every line consists of the following parts:
   a. $margin, consisting of ' ' and '|' characters
   b. $last, indication '\', to signify that this is the last routine
   called by the parent routine
   c. $plus, indication '+', to signify that this routine calls others
   d. $html, name of HTML-file for the routine
   e. $name, name of for the routine
   f. $divs, string of '<'-characters, to indicate how many depth-levels
   are ended after this routine.

   =head1 local subroutines:

=cut


   prepareTrees(1) or
      my_die("Nothing interpreted in file \'$treefilename\'",'WARNING');

   # Report stats
   chdir $tree_output_path;
   reportStats();

   # Generate "contains" tree
   my @notcontained;
   foreach my $key (keys(%contained_by)) {
      push(@notcontained, $key) if (!defined $what_contains{$key});
   }
   createHTMLfile("conttree", \%contained_by, \@notcontained, \%display_name,
                  \%what_describes);
   createGraphvizFile("conttree", \%contained_by, \%display_name, \%contained_by,
                      \%what_contains) if $options{'graphviz'};

   # Generate routine-level calltree
   my @notcalled;
   foreach my $key (keys(%what_contains)) {
      my $ncalls = 1 + $#{$what_calls{$key}} + 1+$#{$what_uses{$key}};
      push(@notcalled, $key) if ($ncalls == 0);
   }
   createHTMLfile("calltree", \%called_by, \@notcalled, \%display_name,
                  \%what_describes);
   createGraphvizFile("calltree", \%called_by, \%display_name, \%contained_by,
                      \%what_contains) if $options{'graphviz'};

   # Finally, copy all external files to the current directory
   use File::Copy;
   use FindBin('$Bin');
   my $g = "$Bin/figs/*.*";
   $g = "\"$g\"" if $g =~ /\ /;
   foreach my $file (glob($g)) {
      copy($file, '.');
   }

   my $title = choose_title(\%display_name,\@notcontained,\@notcalled);

   # Create the index.html file
   open INDEX_TEMP, "<$Bin/figs/index_template.html"
        or my_die("Cannot open '<$Bin/figs/index_template.html' " .
                         "for reading");
   open INDEX,      ">index.html"
        or my_die("Cannot open 'index.html' for writing");
   while (my $line = <INDEX_TEMP>) {
      $line =~ s/TITLE/$title/;
      $line =~ s/welcome_fordocu/$welcome/;
      print INDEX $line;
   }
   close INDEX;
   close INDEX_TEMP;

   # Create the welcome_fordocu.html file
   open WELCOME_TEMP, "<$Bin/figs/welcome_fordocu_template.html"
        or my_die("Cannot open ".
                         "'$Bin/figs/welcome_fordocu_template.html' " .
                         "for reading");
   open WELCOME,      ">welcome_fordocu.html"
        or my_die("Cannot open 'welcome_fordocu.html' " .
                         "for writing");
   my $today = localtime();
   while (my $line = <WELCOME_TEMP>) {
      $line =~ s/TITLE/$title/;
      $line =~ s/VERSION/$version/;
      $line =~ s/TODAY/$today/;
      print WELCOME $line;
   }
   close WELCOME;
   close WELCOME_TEMP;
}

#---------------------------------------------------------------------------
sub check_output_path()
{

=head2 check_output_path();

  Check (en ensure) whether output+path exists.

=cut

   if ($tree_output_path) {
      if (not -w "$tree_output_path") {
         mkpath($tree_output_path);
         my_die("Cannot create directory '$tree_output_path'")
            if (not -w "$tree_output_path");
      }
      $tree_output_path =~ s/([^\\\/])$/$1\//;
      return;
   }
   $tree_output_path = '';
}

#---------------------------------------------------------------------------
sub open_treelog()
{

=head2 open_treelog();

  Open the treelog file

=cut

   check_output_path();
   return unless $update_treelog;
   if (not $treelog) {
      open(TREELOG, ">$tree_output_path$treefilename")
         or my_die("Cannot open file '$tree_output_path$treefilename'");
   }
   $treelog = 1;
}

#---------------------------------------------------------------------------
sub close_treelog()
{

=head2 close_treelog();

  Close the treelog file

=cut

   return unless $treelog;
   close TREELOG if $treelog;
   $treelog = 0;
}

#---------------------------------------------------------------------------
sub write_treelog($)
{

=head2 write_treelog($line);

  Write a line to the treelog file

=cut

   my $line = shift;
   return unless $update_treelog;
   open_treelog() unless $treelog;
   print TREELOG "!! $line" or my_die "Cannot write to tree log\n";
}

1;
