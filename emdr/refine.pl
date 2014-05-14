#!/usr/bin/perl
use warnings;
use strict;
use List::MoreUtils 'pairwise';
use DBI;
use DateTime::HiRes;
use DateTime::Format::ISO8601;
use Text::Table;
use Getopt::Std;
use POSIX 'ceil';
use Number::Format 'round';
use Data::Dumper;
use threads;

my $mysql_host :shared = "127.0.0.1"; #does nothing atm - localhost implicitly assumed
my $mysql_database :shared = "emdr";
my $mysql_user :shared = "emdr_user";
my $mysql_pass :shared = "oMTNziop0EAOs";
my %options;
getopt('dtrT',\%options);
my $debug = 0;
my $required_ratio = 0.95;
my $threshold_value = 1000000;
$required_ratio = $options{r} if exists $options{r};
$threshold_value = $options{T} if exists $options{T};
$debug = 1 if exists $options{d}; 

#while (1) {
#	my $msg = zmq_msg_data(zmq_recvmsg($socket));
#	threads->create(\&emdr_parser, $msg);
#}


# iterate through the amount of viable eve items for refining/manu purposes. 

my $dbh = DBI->connect("DBI:mysql:$mysql_database", $mysql_user, $mysql_pass, {'RaiseError' => '0'});

my $query;
if (defined $options{t}) {
	$query = "select typeID,typeName from eve_static.invTypes where typeID=$options{t}";
} else {
	$query = "select typeID,typeName from eve_static.invTypes where published=1 and typeID < 100000 and typeName not rlike 'blueprint*'";
}
my $sth = $dbh->prepare($query);
$sth->execute();

my $table = Text::Table->new( "typeID", "Item", "Avg. refine ratio", "Market average", "Refine value", "Amount selling below refine value");
my @table_values = [" ", " ", " ", " ", " "," "];

while ( my @result = $sth->fetchrow_array) {

	my $typeID = $result[0];
	my $description = $result[1];
#	my @manu_cost = manu_cost($typeID);

	my @refine_value = refine_value($typeID);
	next if $refine_value[0] eq 0;
	# find the count of items from jita (forge region) that are being sold within the last ~2 days who have prices less than refine value
	my $value_query = "select sum(volRemaining) from 10000002_orders where bid=0 and stationID=60003760 and UNIX_TIMESTAMP(now()) - gendate < 200000 and typeID=$typeID and price < $refine_value[2] order by issueDate desc";
	my @amounts = $dbh->selectrow_array("$value_query");
	my @values = $dbh->selectrow_array("select low,high,average from 10000002_history where typeID=$typeID order by date asc limit 1");

	next if !defined $amounts[0];
	next if !defined $values[0];

	if ( $amounts[0] gt 0 && $values[2] > $threshold_value) {
		# is there a defined market cost for this item?
		my $format = new Number::Format(-thousands_sep => ",", -decimal_point => ".");
		my @ratio = pairwise { round($a / $b, 3) } @values, @refine_value; 
		if ( $ratio[2] lt $required_ratio ) {
			my @array = [ $typeID, $description, $ratio[2], $format->format_number($values[2]), $format->format_number($refine_value[2]), $format->format_number($amounts[0]) ];
			push @table_values, @array; 
		}
	}
}
$dbh->disconnect();
$table->load(@table_values);
print $table;

sub manu_cost {

	my $typeID = $_[0]; 
	my $dbh = DBI->connect("DBI:mysql:$mysql_database", $mysql_user, $mysql_pass, {'RaiseError' => '0'});
	my $query = "select blueprintTypeID,wasteFactor from eve_static.invBlueprintTypes where productTypeID=$typeID";
	my @batch_size = $dbh->selectrow_array("select portionSize from eve_static.invTypes where typeID=$typeID");
	my @bp_result = $dbh->selectrow_array($query);
	return (0,0,0) if !defined $bp_result[0];
	my $blueprintTypeID = $bp_result[0];
	my $ME = 100; # could make this programmable later for some reason
	my $wastefactor = 1 + ( ($bp_result[1] / 100) / (1 + $ME) );
	my @total = (0,0,0);
	if (defined $blueprintTypeID ) {
		# item has a blueprint. determine ME 0 base components, run refine_value($typeID) on that.
		$query = "SELECT t.portionSize, t.typeID, t.typeName, m.quantity FROM eve_static.invTypeMaterials AS m  INNER JOIN eve_static.invTypes AS t   ON m.materialTypeID = t.typeID WHERE m.typeID = $typeID";
		my $sth = $dbh->prepare($query);
		$sth->execute();
		while ( my @result = $sth->fetchrow_array) {
			my $component_typeID = $result[1];
			my $quantity = ceil($result[3] * $wastefactor);
			my @cost = map { $_ * $quantity } refine_value($component_typeID);
			@total = pairwise { ($a + $b) } @cost, @total;
			if ( $debug eq 1 ) {
				print "Item: $result[2] (typeID $result[1]), Amount: $result[3], Batch size: $batch_size[0]\n";
				print "Avg. cost: $cost[2], total so far: $total[2]\n";
			}

		}

		# now account for "extra materials"
	
		# activityID = 1 --> manufacture
		# categoryid = 16 --> skills required to build
		$query = "
			SELECT a.requiredTypeID, a.quantity, b.typeName 
			FROM eve_static.ramTypeRequirements AS a 
			INNER JOIN eve_static.invTypes AS b 
			ON a.requiredTypeID=b.typeID 
			INNER JOIN eve_static.invGroups AS g 
			ON g.groupID=b.groupID 
			WHERE a.typeID=$blueprintTypeID AND activityID=1 and g.categoryID != 16
		";
		$sth = $dbh->prepare($query);
		$sth->execute();
		while ( my @result = $sth->fetchrow_array) {
			if ( $debug eq 1 ) {
				print "Item: $result[2] (typeID $result[0]), Amount: $result[1], Batch size: $batch_size[0]\n";
			}
			my $component_typeID = $result[0];
			my $quantity = $result[1]; # extra materials have no waste factor
			my @cost = map { $_ * $quantity } manu_cost($component_typeID);
			@total = pairwise { ($a + $b) } @cost, @total;
		}
	} else {
		# item doesn't have a blueprint.  
		$query = "SELECT t.portionSize, t.typeID, t.typeName, m.quantity FROM eve_static.invTypeMaterials AS m  INNER JOIN eve_static.invTypes AS t   ON m.materialTypeID = t.typeID WHERE m.typeID = $typeID";
		my $sth = $dbh->prepare($query);
		my @cost;
		$sth->execute();
		my @batch_size = $dbh->selectrow_array("select portionSize from eve_static.invTypes where typeID=$typeID");
		while ( my @result = $sth->fetchrow_array) {
			if ( $debug eq 1 ) {
				print "Item: ($typeID | $result[1] ) $result[2] (typeID $result[1]), Amount: $result[3], Batch size: $batch_size[0]\n";
			
			}
			my $component_typeID = $result[1];
			my $batch_size = $result[0];
			my $quantity = $result[3];
			my @values = $dbh->selectrow_array("select low,high,average from 10000002_history where typeID=$component_typeID order by date asc limit 1");
			next if !defined $values[0];
				
			if ( $debug eq 1 ) {
				print "\tlow: $values[0], high: $values[1], average: $values[2]\n";
			}
			my @cost = map { $_ * $quantity  } @values;
			@total = pairwise { ($a + $b) } @cost, @total;
		}
	}

	# account for batch size
	@total = map { $_ / $batch_size[0] } @total;
	return (@total);
}
sub refine_value {

	my $typeID = $_[0]; 
	my $dbh = DBI->connect("DBI:mysql:$mysql_database", $mysql_user, $mysql_pass, {'RaiseError' => '0'});
	my $query = "select blueprintTypeID from eve_static.invBlueprintTypes where productTypeID=$typeID";
	my @batch_size = $dbh->selectrow_array("select portionSize from eve_static.invTypes where typeID=$typeID");
	my @blueprintTypeID = $dbh->selectrow_array($query);
	my @total = (0,0,0);
	if (exists $blueprintTypeID[0] ) {
		# item has a blueprint. determine components, run refine_value($typeID) on that.
		$query = "SELECT t.portionSize, t.typeID, t.typeName, m.quantity FROM eve_static.invTypeMaterials AS m  INNER JOIN eve_static.invTypes AS t   ON m.materialTypeID = t.typeID WHERE m.typeID = $typeID";
		my $sth = $dbh->prepare($query);
		$sth->execute();
		while ( my @result = $sth->fetchrow_array) {
			if ( $debug eq 1 ) {
				print "Item: $result[2] (typeID $result[1]), Amount: $result[3]\n";
			}
			my $component_typeID = $result[1];
			my $quantity = $result[3];
			my @cost = map { $_ * $quantity  } refine_value($component_typeID);
			@total = pairwise { ($a + $b) } @cost, @total;
		}
	} else {
			my @cost = unit_cost($typeID);
			@total = pairwise { ($a + $b) } @cost, @total;
	}
	# account for minimum amount to refine.
	@total = map { $_ / $batch_size[0] } @total;
	return (@total);
}

sub unit_cost {

	# determining cost of an item that has no blueprint
	my $typeID = $_[0];
	my $dbh = DBI->connect("DBI:mysql:$mysql_database", $mysql_user, $mysql_pass, {'RaiseError' => '0'});
	my @values = $dbh->selectrow_array("select low,high,average from 10000002_history where typeID=$typeID order by date asc limit 1");
	return @values;
}
sub bbbunit_cost {

	# determining cost of an item that has no blueprint
	my $typeID = $_[0];
	my $query = "SELECT t.portionSize, t.typeID, t.typeName, m.quantity FROM eve_static.invTypeMaterials AS m  INNER JOIN eve_static.invTypes AS t   ON m.materialTypeID = t.typeID WHERE m.typeID = $typeID";
	my $dbh = DBI->connect("DBI:mysql:$mysql_database", $mysql_user, $mysql_pass, {'RaiseError' => '0'});
	my $sth = $dbh->prepare($query);
	my @cost = (0,0,0);
	my @total = (0,0,0);
	$sth->execute();
	while ( my @result = $sth->fetchrow_array) {
		if ( $debug eq 1 ) {
			print "Item: ($typeID | $result[1] ) $result[2] (typeID $result[1]), Amount: $result[3]\n";
		}
		my $component_typeID = $result[1];
		my $batch_size = $result[0];
		my $quantity = $result[3];
		my @values = $dbh->selectrow_array("select low,high,average from 10000002_history where typeID=$component_typeID order by date asc limit 1");
		next if !defined $values[0];
			
		if ( $debug eq 1 ) {
			print "\tlow: $values[0], high: $values[1], average: $values[2]\n";
		}
		@cost = map { $_ * $quantity  } @values;
	}
	return @cost;
}
