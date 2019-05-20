# Copyright (C) 2009-2010  Planbureau voor de Leefomgeving (PBL)
#
# full notice can be found in LICENSE

package smart_style;

require 5.003;
use strict;
use warnings;

sub process_description($) {
  my $package = shift;
  my $top = shift;
  my $description = $top->{description}->{line};
  $description = join('<br>',split("\n","\n$description\n"));
  $description =~ s/<br>b *<br>.*<br>e *<br>//;
  $description =~ s/<br> *Arguments*  *type*  *dim  *I\/O  *description *<br>.*//i;
  $description =~ s/<br> *Arguments*  *type*  *dimension  *I\/O  *description *<br>.*//i;
  $description = join("\n",split("<br>",$description));
  #foreach my $line (split("\n",$description)) {
  #     print "descr-aft: '$line'\n";
  #}
  $top->{description}->{line} =  $description;
}

sub line($$$$)
{
   my $package = shift;
   my $i      = shift;
   my $name   = shift;
   my $source = shift;

   my $idebug = 0;

   my $descr = '';

   my $line = $$source[$i];

   print "$package: LINE '$line'\n".
         "          NAME '$name'\n" if ($idebug>=1);


   my $NAME = uc($name);
   if ($line =~ /(^C +$NAME +)(.*) *$/) {
      print "$package: found line '$line'\n" if ($idebug>=2);
      my $spaces = "$1";
      $descr  = "$2";

      print "$name: found description: '$descr'\n" if ($idebug);
      $i++;

      print "$line$$source[$i]$spaces|\n" if ($idebug>=2);
      $spaces = 'C' . ' ' x (length($spaces) - 1);

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
