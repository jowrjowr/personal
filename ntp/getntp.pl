#!/usr/bin/perl
use warnings;
use strict;

my $ntp_str = `ntpq -c rv $ARGV[0]`;
my @vals = split('\n',$ntp_str);

my ($rootdelay, $rootdisp, $offset, $sys_jitter, $clk_jitter, $clk_wander);

my $time = time;
if ( $vals[3] =~ m/rootdelay=(.*), rootdisp=(.*), / ) {  $rootdelay = "$1";  $rootdisp = "$2"; };
if ( $vals[6] =~ m/offset=(.*), f.* sys_jitter=(.*),/ ) {  $offset = "$1";  $sys_jitter = "$2"; };
if ( $vals[7] =~ m/clk_jitter=(.*), clk_wander=(.*)/ ) {  $clk_jitter = "$1";  $clk_wander = "$2"; };

print "$time $ARGV[0] $rootdelay $rootdisp $offset $sys_jitter $clk_jitter $clk_wander\n";
