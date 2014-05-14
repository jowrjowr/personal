#!/usr/bin/perl

use warnings;
use strict;
use Math::Round ':all';
use Statistics::Distributions;

open (DATA, "wds.txt");
my $cutoff = 1; my $percent = 100 * $cutoff;
my $totaldeviations; my $count; my $totalmass = 0;
my $chisq = 0; my @stars;

while (my $line = <DATA>) {
	my @data = split(' ', $line);
	my $mass = $data[9]; my $mass_error = "0.03";
	my $multiple = round( nearest(0.145, $mass) / 0.145 );
	my $residual = $mass - ($multiple * 0.145);
	my $truncated_residual = substr($residual, 0, 5); 
	my $deviations = substr( abs($residual / $mass_error), 0, 4);
	if ($mass_error  le $cutoff) {
		$totaldeviations += $deviations;
		$count++;
		$totalmass += $mass;
		$chisq += ($residual / $mass_error)**2;
		push (@stars, $mass);
	}
}

my @sorted = sort @stars;
my $largest = $sorted[-1]; my $smallest = $sorted[0];
my $binning_largest = nearest_ceil(0.145, $largest);
my $binning_smallest = nearest_floor(0.145, $smallest);
my $reduced_chisq = $chisq / $count;
my $probability = Statistics::Distributions::chisqrprob ($count, $chisq);
my $average_deviations = substr($totaldeviations / $count, 0, 4);
my $average_mass = substr($totalmass / $count, 0, 4);
print "BEEP BOOP...analyzing $count stars with masses determined to $percent% or better

Average standard deviation per star: $average_deviations
Average mass of star: $average_mass solar masses
Mass range of sample: $smallest to $largest solar masses
Chi-squared of the expected binning hypothesis: $chisq
Reduced chi-squared: $reduced_chisq
The probability that the reduced chi-squared value 
of $reduced_chisq is larger than the value of $chisq 
for $count degrees of freedom is $probability.
";
