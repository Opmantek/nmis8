# a small update plugin for converting the mac addresses in dot1q dot1qTpFdbs
# into a more human-friendly form
package Server_Connections;
our $VERSION = "1.1.0";

use strict;
use func;												# for the conf table extras
use snmp 1.1.0;									# for snmp-related access

sub update_plugin
{
	my (%args) = @_;
	my ($node,$S,$C) = @args{qw(node sys config)};
	my ($changesweremade, $message) = collect_plugin(node => $node, sys => $S, config => $C);
	return ($changesweremade, $message);
}

sub collect_plugin
{
	my (%args) = @_;
	my ($node,$S,$C) = @args{qw(node sys config)};

	my $NI = $S->ndinfo;
	my $changesweremade = 0;

	my $connState = {
		'1' => 'closed',
		'2' => 'listen',
		'3' => 'synSent',
		'4' => 'synReceived',
		'5' => 'established',
		'6' => 'finWait1',
		'7' => 'finWait2',
		'8' => 'closeWait',
		'9' => 'lastAck',
		'10' => 'closing',
		'11' => 'timeWait',
		'12' => 'deleteTCB'
	};

	my $addressType = {
		'0' => 'unknown',
		'1' => 'ipv4',
		'2' => 'ipv6',
		'3' => 'ipv4z',
		'4' => 'ipv6z',
		'16' => 'dns',
	};

	if (ref($NI->{Server_Connections}) eq "HASH")
	{
		my $NC = $S->ndcfg;    
		
		if (ref($NI->{Server_Connections}) eq "HASH" and $NI->{system}{nodedown} ne "true")
		{
			dbg("Processing Server_Connections for $node");

	    #  "1.4.192.168.1.42.3306.1.4.192.168.1.7.47883" : {
	    #     "tcpConnectionState" : "established",
	    #     "index" : "1.4.192.168.1.42.3306.1.4.192.168.1.7.47883"
	    #  },
      #"2.16.0.0.0.0.0.0.0.0.0.0.255.255.192.168.1.7.80.2.16.0.0.0.0.0.0.0.0.0.0.255.255.192.168.1.7.34089" : {
      #   "tcpConnectionState" : "timeWait",
      #   "index" : "2.16.0.0.0.0.0.0.0.0.0.0.255.255.192.168.1.7.80.2.16.0.0.0.0.0.0.0.0.0.0.255.255.192.168.1.7.34089"
      #},

			### OK we have data, lets get rid of the old one.
			my $date = returnDateStamp();

			foreach my $tcpKey (keys %{$NI->{Server_Connections}})
			{
				my $thistarget = $NI->{Server_Connections}->{$tcpKey};

				#$thistarget->{tcpConnectionState} = $connState->{$tcpConn->{$tcpKey}};

				if ( $tcpKey =~ /1\.4\.(\d+\.\d+\.\d+\.\d+)\.(\d+)\.1\.4\.(\d+\.\d+\.\d+\.\d+)\.(\d+)$/ )
				{
					$thistarget->{tcpConnectionLocalAddressType} = "ipv4";
					$thistarget->{tcpConnectionLocalAddress} = $1;
					$thistarget->{tcpConnectionLocalPort} = $2;
					$thistarget->{tcpConnectionRemAddress} = $3;
					$thistarget->{tcpConnectionRemPort} = $4;
					$thistarget->{date} = $date;
				}
				elsif ( $tcpKey =~ /2\.16\.([\d+\.]+)\.(\d+)\.2\.16\.([\d+\.]+)\.(\d+)$/ )
				{
					
					$thistarget->{tcpConnectionLocalAddressType} = "ipv6";
					$thistarget->{tcpConnectionLocalAddress} = $1;
					$thistarget->{tcpConnectionLocalPort} = $2;
					$thistarget->{tcpConnectionRemAddress} = $3;
					$thistarget->{tcpConnectionRemPort} = $4;
					$thistarget->{date} = $date;
				}
				$changesweremade = 1;
			}
		}
	}
	return ($changesweremade,undef); # report if we changed anything
}


1;
