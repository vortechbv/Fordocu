#!/usr/bin/perl
# On LINUX: 
#    Change the line above if perl is installed in a different location.



$ENV{PATH} = "C:\\fordocu;$ENV{PATH}";  # Change this line if fordocu.pl is
                                        # installed in a different
                                        # directory.

# Change the following line so that it suits your project.
system( 'fordocu.pl -h -1 -I main -hide gentools ' .
        '           -free */*.f90 */*/*.f90 */*/*/*/.f90' .
        '           -fixed */*.f */*/*.f */*/*/*.f');

