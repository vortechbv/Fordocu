# Copyright (C) 2009-2010  Planbureau voor de Leefomgeving (PBL)
#
# full notice can be found in LICENSE

package docmake_style;

require 5.003;
use strict;
use warnings;

sub process_description($){
  my $package = shift;
  my $top = shift;
  my $description = $top->{description}->{line};
  $description = join('<br>',split("\n","\n$description\n"));
  if ($description =~ s/.*<br>\* *PURPOSE\s*<br>//) {
     $description =~ s/<br>\* *ARGUMENTS.*//;
  }
  $description =~ s/^\*//g;
  $description =~ s/<br>\*/<br>/g;
  $description =~ s/(<br>\s*)*$//;
  $description = join("\n",split("<br>",$description));
  #foreach my $line (split("\n",$description)) {
  #     print "descr-aft: '$line'\n";
  #}
  $top->{description}->{line} =  $description;
};
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

   my $reg_typ = '([IRL]\*4|CH\*\(\*\)|CH\*[0-9]*)';
   if ($line =~ /(^c\* +$name +$reg_typ *)([io\/]* *)(.*) *$/i) {
      print "$package: found line '$line'\n" if ($idebug>=2);
      my $spaces = "$1$3";
      $descr  = "$3$4";

      print "$name: found description: '$descr'\n" if ($idebug);
      $i++;

      print "$line$$source[$i]$spaces|\n" if ($idebug>=2);
      $spaces = 'c\*' . ' ' x (length($spaces) - 2);

      while ($i < @$source) {
         if ($$source[$i] =~ /^$spaces([^ ].*) *$/) {
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
