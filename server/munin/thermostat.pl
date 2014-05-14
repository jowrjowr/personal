#!/usr/bin/perl
# dump data for munin via a radio thermostat
# documentation:
# http://radiothermostat.com/documents/RTCOAWiFIAPIV1_3.pdf
use JSON qw(decode_json);
use LWP::Simple;

if ( $ARGV[0] eq "config" ) {
	print "graph_category temperature\n";
	print "graph_title Thermostat Temperature\n";
	print "graph_vlabel Temperature (F)\n";
	print "thermostat_temp.label Current Temperature (F)\n";
	print "thermostat_temp.draw LINE1\n";
	print "thermostat_targettemp.label Target Temperature (F)\n";
	print "thermostat_targettemp.draw LINE1\n"; 
	}
 else {
	my $thermostat_url = "http://172.16.0.5/tstat";
	my $data = decode_json(get($thermostat_url));
	print "thermostat_temp.value $data->{'temp'}\n";
	print "thermostat_targettemp.value $data->{'t_cool'}\n";
 }


