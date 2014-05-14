#!/usr/bin/perl

use warnings;
use strict;
use Math::Round ':all';
open (DATA, "stars2.txt");
my $cutoff = 0.05;
my $percent = 100 * $cutoff; my $zero = 0; my $one = 0;
my $two = 0; my $three = 0; my $four = 0; my $five = 0;
my $morethanfive = 0; my $totaldeviations; my $count; my $totalmass = 0;

while (my $line = <DATA>) {
	my @data = split(' ', $line);
	my $mass = $data[2]; my $mass_error = $data[3];
	my $multiple = round( nearest(0.145, $mass) / 0.145 );
	my $residual = $mass - ($multiple * 0.145);
	my $truncated_residual = substr($residual, 0, 5); 
	my $deviations = substr( abs($residual / $mass_error), 0, 4);
	if ($mass_error / $mass le $cutoff) {
		$totaldeviations += $deviations;
		$count++;
		$totalmass += $mass;
		if ($deviations eq 0) { $zero++; next; };
		if ($deviations le 1 && $deviations ne 0) { $one++; next; };
		if ($deviations le 2 && $deviations gt 1) { $two++; next; };
		if ($deviations le 3 && $deviations gt 2) { $three++; next; };
		if ($deviations le 4 && $deviations gt 3) { $four++; next; };
		if ($deviations le 5 && $deviations gt 4) { $five++; next; };
		if ($deviations gt 5) { $morethanfive++; next; };
	}
}
my $average_deviations = substr($totaldeviations / $count, 0, 4);
my $average_mass = substr($totalmass / $count, 0, 4);
print "$count stars with masses determined to $percent% or better:
$zero exactly as predicted
$one within 1 standard deviations
$two off by 1 to 2 standard deviations
$three off by 2 to 3 standard deviations
$four off by 3 to 4 standard deviations
$five off by 4 to 5 standard deviations
$morethanfive off by more than 5+ standard deviations
Average standard deviation per star: $average_deviations
Average mass of star: $average_mass solar masses
";
