# Copyright (C) 2009-2010  Planbureau voor de Leefomgeving (PBL)
#
# full notice can be found in LICENSE

package dictionary;

=head1 PACKAGE dictionary

 This package contains functions to maintain a dictionary of
 items and associated information.

=head1 CONTAINS

=cut

require 5.003;
use warnings;
use strict;
use XML::Simple qw(:strict);
use utils ('trim','my_die');

use Exporter;
use vars('$VERSION','@ISA','@EXPORT_OK');

use stmts('print_stmt');

@ISA = ('Exporter');

our @EXPORT_OK = ('handle_comments', 'readComments', 'writeComments', 'store');
#-----------------------------------------------------------------------------

# The actual dictionaries
# Structure per $dictionary = %dictionaries{$dictionary_name}:
#    $dictionary{$item_key}->@comments
my %dictionaries;

#--------------------------------------------------------------
# Module-level constants
our $COMMENTS = 'comments.xml';

#-----------------------------------------------------------------------------

sub relevant_comments($) {

=head2 relevant_comments($top->{collected_comments});

  Find, among all the comments of a statement, those which describe
  the statement. This description is the only information which makes
  it into the HTML-documentation.

  If no description can be found, a description may be found later in the
  dictionary. If this is the case, this description must be included into
  the header, as well as all the available comments. **** We do not wish
  to lose any comnents in the process of writing headers ****

  INPUT VARIABLES
     $top->{collected_comments} : comments collected so far

  OUTPUT VARIABLES
     $description : hash containing 'line','guessed'

=cut

   my $collected_comments = shift;

   # initialise output struct and its values
   my $description;
   my $line_out = "";
   my $guessed = 0;
   my $after   = 0;
   my $idebug  = 0;
   my $is_eoln = 0;

   # Check if there are any admissable end-of-line comments
   #   Collect them if there are any
   foreach my $item (@$collected_comments) {
      $item->{to_description} = 0;
      if ($item->{comment_is_eoln}) {
      # Found an end-of-line comment
         my $commentline = $item->{line};
         next unless ($f90fileio::single_bang or $commentline =~ /!!/);
         # The end-of-line comment is admissable.
         $item->{to_description} = 1;
         $guessed = 1 if ($commentline =~ m/!* ?\?/);
         $commentline =~ s/!* *\?? *//;
         $line_out .= $commentline . "\n";
      }
   }

   # If end-of-line-comments are available, we've got the description
   if ($line_out) {
      $is_eoln = 1;
   } else {
   # There are no end-of-line comments:
   #  we have to find the description among the other comments
      # retrieve values from input
      foreach my $item (@$collected_comments) {

        # Check if we are after the statement or not now
        $after = 1 if ($item->{after_the_line});

        my $commentline = $item->{line};
        if ($idebug >= 3)
        {
           warn "======================================================\n";
           warn "\titem->{line}            = $item->{line}\n"
              if ($item->{line});
           warn "\titem->{comment_is_eoln} = $item->{comment_is_eoln}\n"
              if ($item->{comment_is_eoln});
           warn "\titem->{after_the_line}  = $item->{after_the_line}\n"
              if ($item->{after_the_line});
        }

        if ($commentline =~ m/\\nEMPTY_LINE\\n/ and not $after) {
           # cannot have multiple paragraphs as comment. So everything we
           # found so far before this line did not belong to this top.
           $line_out = "";
           $guessed  = 0;
           foreach my $item1 (@$collected_comments) {
              $item1->{to_description} = 0;
           }
        } elsif ($commentline =~ m/\\nEMPTY_LINE\\n/ and $after) {
           # If we are after the statement and we find a white line we have
           # everything we want.
           last if ($line_out or $f90fileio::single_bang);
        } else {
           # paste the commandline to the outputline, but remove !! first
           next unless ($commentline =~ /!!/ or $f90fileio::single_bang);
           $guessed = 1 if ($commentline =~ m/!* ?\?/);
           $commentline =~ s/!* *\?? *//;
           $line_out .= "$commentline" . "\n";
           $item->{to_description} = 1;
        }

        if ($idebug >= 5)
        {
           warn "SO FAR:\n-------\n$line_out\n";
           warn "======================================================\n";
        }

      }
   }

   if ($idebug >= 5)
   {
      warn "======================================================\n";
      warn "OUT: \n$line_out";
      warn "   guessed = $guessed\n";
      warn "======================================================\n";
   }

   # Create the struct which we will return
   $description = {
                   'line'    => $line_out,
                   'guessed' => $guessed,
                   'from_dictionary' => 0,
                   'after_the_line'   => $after,
                   'comment_is_eoln' => $is_eoln,
                  };

   return $description;

}
#-----------------------------------------------------------------------------
sub handle_comments($);  # Recursive

sub handle_comments($) {

=head2 handle_comments($top);

   Handle comments in the given tree.
   Comments are stored in the dictionary.
   Missing comments are retrieved from the dictionary.

 INPUT VARIABLES

   $top - top of the tree

=cut

   my $top    = shift;
   my $idebug = 0;

   # Collect the relevant bits of information from all the collected
   # comments into a struct description, which has the items
   #     line    : the text wich is the relevant explanation for the HTML-code
   #     guessed : 'line' was found in the code (0) or in the dictionary (1)
   #     other stuff, if necessary (comment_is_eoln?, comment_from_dict?)
   print "  DICT.PM: calling relevant_comments for $top->{name}\n"
         if ($idebug > 2);
   $top->{description} = relevant_comments($top->{collected_comments});

   # Store non-guessed comments or try to guess missing comments.
   # Ignore comments longer than an abritraty 160 characters (DOCMAKE).
   if ( $top->{type} eq 'var' and $top->{description}->{line} ne "" and
        not $top->{description}->{guessed}) {
      store( $top->{name}, $top->{description}->{line} );
   }

   # If the comment can not subtracted from the file itself we look in our
   # comment_dictionary if we have an idea
   if ( $top->{type} eq 'var' and $top->{description}->{line} =~ /^\s*$/) {
      my $cmt = retrieve( $COMMENTS, $top->{name} );
      $top->{description} = {
         'line' => $cmt,
         'guessed' => 1,
         'from_dictionary' => 1,
         'after_the_line' => 0,
         };
      if ($idebug>=1){
         if ($cmt){
            print "\nFound a guessed comment for var '$top->{name}'\n".
               "    comment='$top->{description}->{line}'\n\n";
         }else{
            print "\nDid not found a guessed comment for var '$top->{name}'\n" .
                  "   Add a ? to the description\n\n";
         }
      }
   }

   # Recurse through the tree
   return unless $top->{ocontains};
   foreach my $subtop ( @{ $top->{ocontains} } ) {
      handle_comments($subtop);
   }
}





sub readAll($)
{

=head2 readAll($dictionary_name)

  Read a dictionary (if there is one)

  INPUT VARIABLES
     $dictionary_name : name of the dictionary to use

=cut

   my $dictionary_name = $COMMENTS;

   my $idebug = 0;
  # Create empty dictionary if file does not exist
   if (not -r $dictionary_name) {
      $dictionaries{$dictionary_name} = {};
      return;
   }

   # Else, read the dictionary
   $dictionaries{$dictionary_name} = XMLin($dictionary_name,
                       ForceArray => 1,
                       KeyAttr    => []
                      );
   if ($idebug >= 5){
      foreach my $key (keys(%{$dictionaries{$dictionary_name}})) {
         print "  dictionary about $key: \n";
         foreach my $com (@{$dictionaries{$dictionary_name}->{$key}}) {
            print "    + $com\n";
         }
      }
   }
   warn "Comments dictionary read\n";

}

#-----------------------------------------------------------------------------

sub writeAll($)
{

=head2 writeAll($dictionary_name)

  Write a dictionary

  INPUT VARIABLES
     $dictionary_name : name of the dictionary to use

=cut

   my $dictionary_name = shift;
   my_die("Cannot find dictionary $dictionary_name\n") unless $dictionaries{$dictionary_name};
   my $dictionary = $dictionaries{$dictionary_name};

   # Write the dictionary
   open XMLOUT, ">$dictionary_name"
       or my_die("Cannot open file '$dictionary_name' for writing");

   print XMLOUT XMLout(
                       $dictionary,
                       KeyAttr => [],
                       NoAttr  => 1
                      );
   close XMLOUT;
   warn "Comments dictionary '$dictionary_name' written\n";
}

sub readComments() { readAll($COMMENTS);}
sub writeComments() { writeAll($COMMENTS);}
#-----------------------------------------------------------------------------

sub retrieve($$)
{

=head2 $comments/@comments = retrieve($dictionary_name, $name)

  Retrieve information from the dictionary.

  INPUT VARIABLES
     $dictionary_name : name of the dictionary to use
     $name    : name of the item documented
  OUTPUT VARIABLES
     $comments: comments to $name (or empty string if not found)

=cut

   my $dictionary_name = shift;
   my_die("Cannot find dictionary $dictionary_name\n")
      unless exists($dictionaries{$dictionary_name});
   my $dictionary = $dictionaries{$dictionary_name};

   my $name = lc(trim(shift));
   return '' unless $name and exists($dictionary->{$name});

   #   warn "Multiple comments available for $name\n"
   #      if $#{$dictionary->{$name}} > 0;
   my @retval =  @{$dictionary->{$name}};
   return @retval if wantarray;
   return $retval[0];
}

#-----------------------------------------------------------------------------

sub store($$)
{

=head2 store($name, $comments)

  Store information in the dictionary.

  INPUT VARIABLES
     $name    : name of the item documented
     $comments: comments to $name

=cut

   my $name     = lc(trim(shift));
   my $comments = trim(shift);

   # Keep only the last bit of comment
   $comments =~ s/\n/<br>/g;
   $comments =~ s/(.*\\nEMPTY_LINE\\n<br>)//;
   $comments =~ s/<br>/\n/g;
   return unless $comments =~ /\w/;
   return if ( length( $comments ) > 160 );

   my $dictionary_name = $COMMENTS;

   $dictionaries{$dictionary_name} = {}
        unless (exists($dictionaries{$dictionary_name}));

   my $dictionary = $dictionaries{$dictionary_name};
   $dictionary->{$name}= [] unless (exists($dictionary->{$name}));

   if ($dictionary) {
      # Item exists, check whether the given description
      # also exists. If so - return.
      foreach my $cmt (@{$dictionary->{$name}}) {
         return if $cmt eq $comments;
      }
   }

   # Add new comment
   push(@{$dictionary->{$name}}, $comments);
}

#-----------------------------------------------------------------------------

1;

