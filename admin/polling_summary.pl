#!/usr/bin/perl
#
#  Copyright (C) Opmantek Limited (www.opmantek.com)
#
#  ALL CODE MODIFICATIONS MUST BE SENT TO CODE@OPMANTEK.COM
#
#  This file is part of Network Management Information System ("NMIS").
#
#  NMIS is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  NMIS is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with NMIS (most likely in a file named LICENSE).
#  If not, see <http://www.gnu.org/licenses/>
#
#  For further information on NMIS or for a license other than GPL please see
#  www.opmantek.com or email contact@opmantek.com
#
#  User group details:
#  http://support.opmantek.com/users/
#
# *****************************************************************************

# this script produces a csv document with a node overview in terms of
# modelling and enabled features; a similar overview is available in the GUI
# under system -> configuration check -> node admin summary

use FindBin;
use lib "$FindBin::Bin/../lib";

use strict;
use func;
use NMIS;
use rrdfunc;
use Data::Dumper;

my %arg = getArguements(@ARGV);

# Set debugging level.
my $debug = setDebug($arg{debug});

my $C = loadConfTable(conf=>$arg{conf},debug=>$arg{debug});

my $LNT = loadLocalNodeTable();

my $totalPoll = 0;
my $goodPoll = 0;
my $pingDown = 0;
my $snmpDown = 0;
my $noSnmp = 0;
my $demoted = 0;
my $latePoll5m = 0;
my $latePoll15m = 0;
my $latePoll1h = 0;
my $latePoll12h = 0;

my @polltimes;
my $PP = loadTable(dir=>'conf',name=>"Polling-Policy");

# define the output heading and the print format
my @heading = ("node", "status", "ping", "snmp", "policy", "delta", "snmp", "poll", "update", "pollmessage");
printf "%-16s %-9s %-5s %-5s %-10s %-6s %-4s %-6s %-7s %-16s\n", @heading;

foreach my $node (sort keys %{$LNT}) {
	if ( getbool($LNT->{$node}{active}) ) {
		++$totalPoll;
		my $S = Sys::->new; # get system object
		$S->init(name=>$node,snmp=>'false'); # load node info and Model if name exists
		my $NI = $S->ndinfo;
		
		my $polling_policy = $LNT->{$node}{polling_policy} ? $LNT->{$node}{polling_policy} : "default";
		my $polltime;
		my $updatetime;
		
		my $snmp = 300;
		if ( defined $PP->{$polling_policy}{snmp} ) {
			$snmp = $PP->{$polling_policy}{snmp};
			if ( $snmp =~ /(\d+)m/ ) {
				$snmp = $1 * 60;
			}
			else {
				$snmp = "ERROR";
			}				
		}
		
		my $message = "";
		my $pollstatus = "ontime";
		my $lastPollAgo = time() - $NI->{system}{lastCollectPoll} if $NI->{system}{lastCollectPoll};
		my $delta = $NI->{system}{collectPollDelta};
		if (not $delta and $lastPollAgo) {
			$delta = $lastPollAgo;
		}
		elsif ( not $delta ) {
			$delta = "---";
		}
		
#$VAR1 = {
#  'failover_ping_status' => undef,
#  'failover_status' => undef,
#  'overall' => -1,
#  'ping_enabled' => 1,
#  'ping_status' => 1,
#  'primary_ping_status' => undef,
#  'snmp_enabled' => 1,
#  'snmp_status' => 1,
#  'wmi_enabled' => 0,
#  'wmi_status' => undef
#};

		my %status = PreciseNodeStatus(system => $S);
		print Dumper \%status if $debug > 5;

		my $ping_status = $status{'ping_status'} ? "up" : "down";
		++$pingDown if $ping_status eq "down";

		my $snmp_status = $status{'snmp_status'} ? "up" : "down";
		++$snmpDown if $snmp_status eq "down";

		if ( $LNT->{$node}{collect} eq "false" 
			or  $LNT->{$node}{collect_snmp} eq "false" 

		) {
			$message = "no snmp collect";
			$pollstatus = "pingonly";
			++$noSnmp;
		}
		elsif ( defined $NI->{system}->{demote_grace} and $NI->{system}->{demote_grace} > 0 ) {
			$message = "snmp polling demoted";
			$pollstatus = "demoted";
			++$demoted;
		}
		elsif ( $delta > $snmp * 1.1 * 144 ) {
			$message = "144x late poll";
			$pollstatus = "late";
			++$latePoll12h;
		}
		elsif ( $delta > $snmp * 1.1 * 12 ) {
			$message = "12x late poll";
			$pollstatus = "late";
			++$latePoll1h;
		}
		elsif ( $delta > $snmp * 1.1 * 3 ) {
			$message = "3x late poll";
			$pollstatus = "late";
			++$latePoll15m;
		}
		elsif ( $delta > $snmp * 1.1 ) {
			$message = "1x late poll";
			$pollstatus = "late";
			++$latePoll5m;
		}
		else {
			++$goodPoll;
		}

		if (-f (my $rrdfilename = $S->getDBName(type => "health")))
		{
			my $string;
			my @results;
			my $stats = getRRDStats(sys => $S, graphtype => "health", index => undef, item => undef, start => time() - 86400,  end => time() );
			
			$polltime = $stats->{polltime}->{mean};
			$updatetime = $stats->{updatetime}->{mean};			
		}
		printf "%-16s %-9s %-5s %-5s %-10s %-6s %-4s %-6s %-7s %-16s\n", $node, $pollstatus, $ping_status, $snmp_status, $polling_policy, $delta, $snmp, $polltime, $updatetime, $message;
	}
}

print "totalPoll=$totalPoll ontime=$goodPoll pingDown=$pingDown snmpDown=$snmpDown pingonly=$noSnmp demoted=$demoted 1x_late=$latePoll5m 3x_late=$latePoll15m 12x_late=$latePoll1h 144x_late=$latePoll12h\n";

