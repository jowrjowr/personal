#!/usr/bin/perl
use warnings;
use strict;
use Compress::Zlib;
use JSON;
use JSON::Parse qw(parse_json);
use ZMQ::LibZMQ3;
use ZMQ::Constants qw(ZMQ_SUB ZMQ_SUBSCRIBE);
use DBI;
use DateTime::HiRes;
use DateTime::Format::ISO8601;
use Data::Dumper;
use threads;

my $mysql_host :shared = "127.0.0.1"; #does nothing atm - localhost implicitly assumed
my $mysql_database :shared = "emdr";
my $mysql_user :shared = "emdr_user";
my $mysql_pass :shared = "oMTNziop0EAOs";

# EMDR relay address
my $relay = "tcp://relay-us-central-1.eve-emdr.com:8050";

# generate ZMQ subscription
my $context = zmq_init;
my $socket = zmq_socket($context, ZMQ_SUB);
my $status = zmq_connect($socket, $relay);
print "Socket status: $status\n";
$status = zmq_setsockopt($socket, ZMQ_SUBSCRIBE, "");
print "Status: $status\n";

# 0 is success. could add conditionals...


while (1) {
	my $msg = zmq_msg_data(zmq_recvmsg($socket));
	threads->create(\&emdr_parser, $msg);
}



sub emdr_parser {

	# be free! 
	threads->detach();
	# the emdr_parser subroutine is meant to be self contained for threading purposes

	my $json = parse_json(uncompress($_[0]));

	# data format
	# http://dev.eve-central.com/unifieduploader/start


	# mysql

	my $dbh = DBI->connect("DBI:mysql:$mysql_database", $mysql_user, $mysql_pass, {'RaiseError' => '0'});

	my $threadid = threads->tid;

	my $type = $json->{'resultType'}; 
	my $rowsets = $json->{'rowsets'}[0];

	my $typeid = $rowsets->{'typeID'};

	my $regionid = $rowsets->{'regionID'};
	my $gendate = DateTime::Format::ISO8601->parse_datetime($rowsets->{'generatedAt'})->strftime('%s');
	my @rows = @{$rowsets->{'rows'}};

	my $rowcount = @rows;
	
	# memory cleanup - of debatable need, though multithreaded leaks are real...
	$json = ''; $_ = '';

	if ( $rowcount eq '0' ) {
		my $dt = DateTime::HiRes->now;
		my $date = join ' ', $dt->ymd, $dt->hms;

		print "$date :$threadid: Null EMDR data set\n";

	} elsif ( $type eq 'history' ) {
		# history-specific processing
		my $dt = DateTime::HiRes->now;
		my $start = $dt->hires_epoch;
		my $date = join ' ', $dt->ymd, $dt->hms;
		print "$date :$threadid: History processing, $rowcount rows. Type ID $typeid in region $regionid\n";
		my $query = "INSERT INTO ".$regionid."_history VALUES";
		my $count = "0";
		# relay column ordering as per spec.
		# 'date', 'orders', 'quantity', 'low', 'high', 'average'
		# columns are NOT to spec.

		foreach(@rows) {
			my @row = @{ $_ }; # array within array within hash within array....	
			my ($date, $orders, $quantity, $low, $high, $average);
			$orders = $row[1]; $low = $row[4]; $high = $row[5]; $average = $row[2];
			if ( $row[3] lt 0 ) {
				# assuming underflow.
				$quantity = -$row[3] + 2**32 -1;
			} else {
				$quantity = $row[3];
			}
			# convert from ISO 8601 to epoch time
			my $iso_date = DateTime::Format::ISO8601->parse_datetime($row[0]);
			$date = $iso_date->strftime('%s');
			# 6 month cutoff
			next if $date lt $start - 86400*180;
			$count++;
			$query = "$query"."($gendate, $typeid, $date, $orders, $quantity, $low, $high, $average),";
		}
		@rows = [];
		chop ($query);
		$query = "$query"."ON DUPLICATE KEY UPDATE gendate=VALUES(gendate),date=VALUES(date),quantity=VALUES(quantity),low=VALUES(low),high=VALUES(high),average=VALUES(average)";
		eval { $dbh->do($query) };
		$dt = DateTime::HiRes->now;
		my $finish = $dt->hires_epoch;
		my $delta = sprintf('%.2f',$finish - $start);
		$date = join ' ', $dt->ymd, $dt->hms;
		print "$date :$threadid: History processing complete. Region: $regionid, Type ID: $typeid, $count/$rowcount inserted. $delta seconds\n";
		print "$date :$threadid: History processing error: $@" if $@;

	} elsif ( $type eq 'orders' ) { 
		# order-specific processing
		my $dt = DateTime::HiRes->now;
		my $start = $dt->hires_epoch;
		my $date = join ' ', $dt->ymd, $dt->hms;
		print "$date :$threadid: Order processing, $rowcount rows. Type ID $typeid in region $regionid\n";
		my $query = "INSERT INTO ".$regionid."_orders VALUES";
		my $count = "0";

		# relay column ordering:
		# 'price', 'volRemaining', 'range', 'orderID', 'volEntered', 'minVolume',
		# 'bid', 'issueDate', 'duration', 'stationID', 'solarSystemID'
		foreach(@rows) {
			my @row = @{ $_ }; # array within array within hash within array....	

			my ($price, $volremaining, $range, $orderid, $volentered, $minvolume);
			my ($issuedate, $duration, $bid, $stationid, $solarsystemid);

			$price = $row[0]; $volremaining = $row[1]; $range = $row[2]; $orderid = $row[3];
			$volentered = $row[4]; $minvolume = $row[5]; $bid = $row[6]; $duration = $row[8]; 
			$stationid = $row[9]; $solarsystemid = $row[10];
			my $iso_date = DateTime::Format::ISO8601->parse_datetime($row[7]);
			$issuedate = $iso_date->strftime('%s');
			# 1 month cutoff
			next if $gendate lt $start - 86400*30;
			$count++;
			$query = "$query"."($gendate, $typeid, $price, $volremaining, $range, $orderid, $volentered, $minvolume, $bid, $issuedate, $duration, $stationid, $solarsystemid),";
		}
		chop($query);
		$query = "$query"."ON DUPLICATE KEY UPDATE gendate=VALUES(gendate),price=VALUES(price),volRemaining=VALUES(volRemaining)";
		eval { $dbh->do($query) };
		$dt = DateTime::HiRes->now;
		my $finish = $dt->hires_epoch;
		my $delta = sprintf('%.2f',$finish - $start);
		$date = join ' ', $dt->ymd, $dt->hms;
		print "$date :$threadid: Order processing complete. Region: $regionid, Type ID: $typeid, $count/$rowcount inserted. $delta seconds\n";
		print "$date :$threadid: Order processing error: $@" if $@;

	} else {
		use Data::Dumper;
		my $dt = DateTime::HiRes->now;
		my $date = join ' ', $dt->ymd, $dt->hms;
		print "$date :$threadid: weirdness. neither order nor history. should never see this.\n";
		print Dumper($json);
	}

	$dbh->disconnect();
	threads->exit();
}

