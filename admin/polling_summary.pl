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
my $PP = loadTable(dir=>'conf',name=>"Polling-Policy");

if ( defined $arg{node} and $arg{node} ne "" ) {
	printPollingSummary($arg{node});
	printNodePollDetails($arg{node});
}
else {
	printPollingSummary();
}

sub printNodePollDetails {
	my $node = shift;

	my $S = Sys::->new; # get system object
	$S->init(name=>$node,snmp=>'false'); # load node info and Model if name exists
	my $NI = $S->ndinfo;
	
	my $polling_policy = $LNT->{$node}{polling_policy} ? $LNT->{$node}{polling_policy} : "default";
	
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
	
	my $lastAttempt = $NI->{system}{last_poll_attempt} ? returnDateStamp($NI->{system}{last_poll_attempt}) : "--:--:--";
	my $last_poll_snmp = $NI->{system}{last_poll_snmp} ? returnDateStamp($NI->{system}{last_poll_snmp}) : "--:--:--";
	my $lastCollectPoll = $NI->{system}{lastCollectPoll} ? returnDateStamp($NI->{system}{lastCollectPoll}) : "--:--:--";
	my $lastPollAgo = time() - $NI->{system}{lastCollectPoll} if $NI->{system}{lastCollectPoll};
	my $delta = $NI->{system}{collectPollDelta};

	if (not $delta and $lastPollAgo) {
		print "DEBUG: no delta using lastPollAgo $lastPollAgo\n" if $debug;
		$delta = $lastPollAgo;
	}
	elsif ( not $delta ) {
		$delta = "---";
	}

	my $polldelta = "NaN";
	my $polltime = "NaN";
	my $updatetime = "NaN";
	if (-f (my $rrdfilename = $S->getDBName(type => "health")))
	{
		my $string;
		my @results;
		my $stats = getRRDStats(sys => $S, graphtype => "health", index => undef, item => undef, start => time() - 86400,  end => time() );
		
		$polldelta = $stats->{polldelta}->{mean};
		$polltime = $stats->{polltime}->{mean};
		$updatetime = $stats->{updatetime}->{mean};			
	}

	my %status = PreciseNodeStatus(system => $S);

	my $ping_enabled = $status{'ping_enabled'} ? "yes" : "no";
	my $ping_status = $status{'ping_status'} ? "up" : "down";
	my $snmp_enabled = $status{'snmp_enabled'} ? "yes" : "no";
	my $snmp_status = $status{'snmp_status'} ? "up" : "down";

	my $now = returnDateStamp(time());
	my $time = time();

	print Dumper $LNT->{$node} if $debug > 5;

	print Dumper $NI->{system} if $debug > 5;

	print Dumper \%status if $debug > 5;

	print <<EOF;
node : $node
  time now:          $now ($time)

  sysDescr:          $NI->{system}{sysDescr}
  sysObjectName:     $NI->{system}{sysObjectName}
  model:             $NI->{system}{model}
  nodeModel:         $NI->{system}{nodeModel}
  polling_policy:    $polling_policy

  active:            $NI->{system}{active}
  ping:              $NI->{system}{ping}
  collect:           $NI->{system}{collect}

  nodestatus:        $NI->{system}{nodestatus}
  ping_enabled:      $ping_enabled
  ping_status:       $ping_status
  snmp_enabled:      $snmp_enabled
  snmp_status:       $snmp_status
  demote_grace:      $NI->{system}{demote_grace}

  last_poll_attempt: $lastAttempt ($NI->{system}{last_poll_attempt})
  last_poll:         $lastAttempt ($NI->{system}{last_poll})
  last_poll_snmp:    $last_poll_snmp ($NI->{system}{last_poll_snmp})
  lastCollectPoll:   $lastCollectPoll ($NI->{system}{lastCollectPoll})

  lastPollAgo:       $lastPollAgo
  last poll delta:   $delta  
  avg poll delta:    $polldelta
  avg poll time:     $polltime
  avg update time:   $updatetime

EOF

}

sub printPollingSummary {
	my $argnode = shift;

	my $totalNodes = 0;
	my $totalPoll = 0;
	my $goodPoll = 0;
	my $pingDown = 0;
	my $snmpDown = 0;
	my $pingOnly = 0;
	my $noSnmp = 0;
	my $badSnmp = 0;
	my $demoted = 0;
	my $latePoll5m = 0;
	my $latePoll15m = 0;
	my $latePoll1h = 0;
	my $latePoll12h = 0;

	my @polltimes;

	# define the output heading and the print format
	my @heading = ("node", "attempt", "status", "ping", "snmp", "policy", "delta", "snmp", "avgdel", "poll", "update", "pollmessage");
	printf "%-24s %-9s %-9s %-5s %-5s %-10s %-6s %-4s %-7s %-6s %-7s %-16s\n", @heading;

	foreach my $node (sort keys %{$LNT}) {
		if ( defined $argnode and $argnode ne $node ) {
			next;
		}
		if ( getbool($LNT->{$node}{active}) ) {
			++$totalNodes;
			++$totalPoll;
			my $S = Sys::->new; # get system object
			$S->init(name=>$node,snmp=>'false'); # load node info and Model if name exists
			my $NI = $S->ndinfo;
			
			my $polling_policy = $LNT->{$node}{polling_policy} ? $LNT->{$node}{polling_policy} : "default";
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

			my $polldelta = "NaN";
			my $polltime = "NaN";
			my $updatetime = "NaN";
			if (-f (my $rrdfilename = $S->getDBName(type => "health")))
			{
				my $string;
				my @results;
				my $stats = getRRDStats(sys => $S, graphtype => "health", index => undef, item => undef, start => time() - 86400,  end => time() );
				
				$polldelta = sprintf("%.2f",$stats->{polldelta}->{mean});
				$polltime = sprintf("%.2f",$stats->{polltime}->{mean});
				$updatetime = sprintf("%.2f",$stats->{updatetime}->{mean});			
			}
						
			my $lastAttempt = $NI->{system}{last_poll_attempt} ? returnTime($NI->{system}{last_poll_attempt}) : "--:--:--";
			my $lastPollAgo = time() - $NI->{system}{lastCollectPoll} if $NI->{system}{lastCollectPoll};
			my $delta = $NI->{system}{collectPollDelta};

			if (not $delta and $lastPollAgo) {
				$delta = $lastPollAgo;
			}
			elsif ( not $delta ) {
				$delta = "---";
			}

			my %status = PreciseNodeStatus(system => $S);
			print Dumper \%status if $debug > 5;

			my $ping_enabled = $status{'ping_enabled'} ? "yes" : "no";
			my $ping_status = $status{'ping_status'} ? "up" : "down";
			++$pingDown if $ping_status eq "down";

			my $snmp_enabled = $status{'snmp_enabled'} ? "yes" : "no";
			my $snmp_status = $status{'snmp_status'} ? "up" : "down";
			++$snmpDown if $snmp_status eq "down";

			my $collect_snmp = 1;
			if ( $LNT->{$node}{collect} eq "false" 
				or  $LNT->{$node}{collect_snmp} eq "false" 
			) {
				$collect_snmp = 0;
			}

			my $message = "";
			my $pollstatus = "ontime";
			if ( not $collect_snmp ) {
				$message = "no snmp collect";
				$pollstatus = "pingonly";
				++$pingOnly;
			}
			elsif ( getbool($C->{demote_faulty_nodes}) and defined $NI->{system}->{demote_grace} and $NI->{system}->{demote_grace} > 0 ) {
				$message = "snmp polling demoted";
				$pollstatus = "demoted";
				++$demoted;
			}
			elsif ( $NI->{system}{nodeModel} eq "Model" and $collect_snmp ) {
				$message = "snmp never successful";
				$pollstatus = "bad_snmp";
				++$badSnmp;
				--$totalPoll;
			}
			elsif ( $collect_snmp and not defined $NI->{system}{last_poll_snmp} ) {
				$message = "snmp never successful";
				$pollstatus = "bad_snmp";
				++$badSnmp;
				--$totalPoll;
			}
			elsif ( not defined $NI->{system}{last_poll_snmp} ) {
				$message = "snmp not enabled";
				$pollstatus = "no_snmp";
				++$noSnmp;
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

			if ( $NI->{system}{last_poll_attempt} and $NI->{system}{lastCollectPoll} 
				and $NI->{system}{last_poll_attempt} > $NI->{system}{lastCollectPoll} ) {
				$message .= "Last poll attempt failed";
			}

			printf "%-24s %-9s %-9s %-5s %-5s %-10s %-6s %-4s %-7s %-6s %-7s %-16s\n", $node, $lastAttempt, $pollstatus, $ping_status, $snmp_status, $polling_policy, $delta, $snmp, $polldelta, $polltime, $updatetime, $message;
		}
	}

	my $now = returnTime(time());
	print "\ntotalNodes=$totalNodes totalPoll=$totalPoll ontime=$goodPoll pingOnly=$pingOnly 1x_late=$latePoll5m 3x_late=$latePoll15m 12x_late=$latePoll1h 144x_late=$latePoll12h\n";
	print "time=$now pingDown=$pingDown snmpDown=$snmpDown badSnmp=$badSnmp noSnmp=$noSnmp demoted=$demoted\n";
	print "\n\n" if defined $argnode;
}
