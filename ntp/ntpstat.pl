#!/usr/bin/perl
#
# I want to see how far the clock is off on average from the network
# sources.
# 
# Output:
#    line 1 - positive offset #
#    line 2 - negative offset #
#

$count = "0";
$offset = "0";

foreach (`ntpq -pn`)
{
   ($remote,$ref,$st,$t,$w,$p,$reach,$delay,$o,$d) = split;
   if ( $remote ne "==============================================================================" ) {
   if ( $remote ne "remote" ) {

   $count = $count + "1";
   $offset = $offset + $o;

   } }
}


# Now we will get the average and print the output

$average = int( $offset / $count );

if ( $average > 0 ) {

      print "$average \n";
      print "0 \n";

      } else {

      $average = int( $average * -1 );
      print "0 \n";
      print "$average \n";

      }

