# Copyright (C) 2009-2010  Planbureau voor de Leefomgeving (PBL)
#
# full notice can be found in LICENSE

package simona_style;

require 5.003;
use strict;
use warnings;

sub process_description($){};
sub line($$$$)
{
   my $package = shift;
   my $i      = shift;
   my $name   = shift;
   my $source = shift;

   my $idebug = 0; # if ($name eq "nerror") {$idebug=1};

   my $descr = '';

   my $line = $$source[$i];

   print "$package: LINE '$line'\n".
         "          NAME '$name'\n" if ($idebug>=1);


   if ($line =~ /(^[!c] +$name +)(.*) *$/i) {
      print "$package: found line '$line'\n" if ($idebug>=2);
      my $spaces = "$1";
      $descr  = "$2";

      print "$name: found description: '$descr'\n" if ($idebug);
      $i++;

      print "$line$$source[$i]$spaces|\n" if ($idebug>=2);
      $spaces = '[!c]' . ' ' x (length($spaces) - 1);

      while ($i < @$source) {
         if ($$source[$i] =~ /^$spaces *(.*) *$/) {
            $descr .= "\n$1";
         } else { last }
         $i++;
      }
      $descr =~ s/[\r]//g;

      print "complete description for $name : '$descr'\n"
           if ($idebug>=1);
   }
   return ($i, $descr);
}
1;
