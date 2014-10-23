#!/usr/bin/perl

use FCGI;
use Socket;
use POSIX qw(setsid);
use Sys::Syslog qw(:standard :macros); 
use warnings; 
use strict;
use Capture::Tiny ':all';

require 'syscall.ph';

my %req_params = ();
my $request;

# setup for possibly hosting perl-fastcgi on a getopt set host/port

my $host = "127.0.0.1";
my $port = "8999";

# get the logging started
openlog('fastcgi_perl','pid','daemon');

# fork off

chdir '/' or die "Can't chdir to /: $!";
defined(my $pid = fork)   or die "Can't fork: $!";
exit if $pid;
setsid                    or die "Can't start a new session: $!";
umask 0;

# socket is contained with an eval block because of error trapping
my $socket = eval {
       	my $socket = FCGI::OpenSocket( "$host:$port", 10 ); #use IP sockets
	return $socket;
};

syslog(LOG_ERR, "Could not open a socket on $host port $port") if !defined ($socket);
syslog(LOG_INFO, "Started on $host port $port");


# build the cgi request
$request = FCGI::Request( \*STDIN, \*STDOUT, \*STDERR, \%req_params, $socket );
if ($request) {	request_loop(); } 

# clean up
FCGI::CloseSocket( $socket );
closelog();

### only subs after this line


sub request_loop {

        while( $request->Accept() >= 0 ) {

		# processing any STDIN input from WebServer (for CGI-POST actions)
        	my $stdin_passthrough ='';
        	my $req_len = 0 + $req_params{'CONTENT_LENGTH'};

        	if (($req_params{'REQUEST_METHOD'} eq 'POST') && ($req_len != 0) ){
        		my $bytes_read = 0;
                	while ($bytes_read < $req_len) {
                        	my $data = '';
                        	my $bytes = read(STDIN, $data, ($req_len - $bytes_read));
                        	last if ($bytes == 0 || !defined($bytes));
                        	$stdin_passthrough .= $data;
                        	$bytes_read += $bytes;
                	}
		}

        	# running the cgi app
        	if ( 
			(-x $req_params{SCRIPT_FILENAME}) &&	# ...if executable by me. covers read check as well.
                	(-s $req_params{SCRIPT_FILENAME})	# ...if not empty
        	){
        		pipe(CHILD_RD, PARENT_WR);
        		my $pid = open(KID_TO_READ, "-|");
        		unless( defined($pid) ) {
            			print "Content-type: text/plain\r\n\r\n";
                        	print "Error: CGI app returned no output - ";
                        	print "Executing $req_params{SCRIPT_FILENAME} failed !\n";
				syslog('LOG_ERR',"$req_params{SCRIPT_FILENAME} exited without output");
            			next;
        		}
        		if ($pid > 0) {
            			close(CHILD_RD);
            			print PARENT_WR $stdin_passthrough;
            			close(PARENT_WR);

            		while( my $s = <KID_TO_READ> ) { print $s; }
            		close KID_TO_READ;
            		waitpid($pid, 0);
        	} else {
        		foreach my $key ( keys %req_params ){ $ENV{$key} = $req_params{$key}; }

			# cd to the script's local directory
			my $scriptdir;

                	if ($req_params{SCRIPT_FILENAME} =~ /^(.*)\/[^\/]+$/) { 
				chdir $1;
				$scriptdir = $1;
			}

            		close(PARENT_WR);
            		close(STDIN);
	        	syscall(&SYS_dup2, fileno(CHILD_RD), 0);
			syslog('LOG_INFO',"$req_params{'REQUEST_METHOD'} $req_params{SCRIPT_FILENAME} $scriptdir $req_params{REMOTE_ADDR}");
            		my ($stdout, $stderr, $exit) = capture { system($req_params{SCRIPT_FILENAME}) };
			# STDOUT doesn't get printed right through capture_stderr {}, so do it manually
			print $stdout;
			syslog('LOG_ERR',"$req_params{'REQUEST_METHOD'} $req_params{SCRIPT_FILENAME} $scriptdir $req_params{REMOTE_ADDR} ERROR: \"$stderr\"") if $stderr;
        	}
	}
        	else {
                	print("Content-type: text/plain\r\n\r\n");
                	print "Error: No such CGI app - $req_params{SCRIPT_FILENAME} may not ";
                	print "exist or is not executable by this process.\n";
			syslog('LOG_ERR',"ERROR: $req_params{'REQUEST_METHOD'} $req_params{SCRIPT_FILENAME} $req_params{REMOTE_ADDR}");
            	}

        }
}

