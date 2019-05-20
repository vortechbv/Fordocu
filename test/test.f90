! This is a test program, that can be used to check
! whether the fordocu program has been installed correctly.

!! Say Hello to someone
subroutine Hello(who)
   implicit none
   character(len=*) :: who !! Who to greet
   write (*.*) 'Hello ', trim(who), '!'
end subroutine Hello

!! The main routine
program Greeter
   use SaySomething, only: Hello
   implicit none

   character(len=8), parameter :: who = 'world'; !! Name of the person to greet
   call Hello(who);
end program Greeter

