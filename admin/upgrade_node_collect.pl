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

our $VERSION = '1.0.0';

use FindBin;
use lib "$FindBin::Bin/../lib";
use strict;
use warnings;
use func;
use NMIS;

my %arg = getArguements(@ARGV);

upgrade_node_collect();

# this will automatically upgrade the Nodes.nmis and convert collect into collect_wmi and collect_snmp automatically.

sub upgrade_node_collect
{
	my $C = loadConfTable();			# likely cached
	my $LNT = loadLocalNodeTable(sanitise => 1); # this removes garbage data
	
	# get a list of nodes which do not have collect_snmp and collect_wmi not configured.
	my $num_nodes = keys %{$LNT};
	my @nodesIgnored = grep {
		exists $LNT->{$_}{collect_snmp} and
		exists $LNT->{$_}{collect_wmi}
	} keys %{$LNT};
	
	my @nodesToMigrate = grep {
		!exists $LNT->{$_}{collect_snmp} or
		!exists $LNT->{$_}{collect_wmi}
	} keys %{$LNT};
	my @nodesError;
	my @nodesOK;
	
	print "nodesIgnored=@nodesIgnored\n";
	print "nodesToMigrate=@nodesToMigrate\n";
	
	my $nodeDataChanged = 0;

	foreach my $node (@nodesToMigrate) {
		my $cfg = $LNT->{$node};
		
		my ($collect_wmi, $collect_snmp);
		
		# If WMI username and password are set, we can assume this node uses WMI
		$collect_wmi = (length $cfg->{wmipassword} and length $cfg->{wmipassword});
	
		if ( defined $cfg->{version} and $cfg->{version} =~ /snmpv1|snmpv2c/ ) {
			# If SNMP community is set, we can assume this node uses SNMP
			$collect_snmp = length $cfg->{community} ? 1 : 0;
		}
		# we should not need this but people are adding nodes without SNMP version
		elsif ( not defined $cfg->{version} ) {
			# If SNMP community is set, we can assume this node uses SNMP
			$collect_snmp = length $cfg->{community} ? 1 : 0;
		}
		elsif ( defined $cfg->{version} and $cfg->{version} =~ /snmpv3/ ) {
			# If SNMP username and passwords are sent then we can assume this node uses SNMPv3
			$collect_snmp = (length $cfg->{username} and length $cfg->{authpassword} and length $cfg->{privpassword});
		}
	
		# reset if the node has collect set to false?
		if ( $cfg->{collect} ne "true" ) {
			$collect_snmp = 0;
			$collect_wmi = 0;
		}

		# Add the properties to node table, print warning if both are missing (and -v given)
		#dbg_log UNDERLINE, "$node", RESET, "\n" if $opt_verbose;
		if ($collect_wmi or $collect_snmp) {
			push @nodesOK, $node;
			#print "collect_wmi:  " . ($collect_wmi ? 'true' : 'false') . "\n";
			#print "collect_snmp: " . ($collect_snmp ? 'true' : 'false') . "\n\n";
		} 
		else {
			push @nodesError, $node;
			#print "WARNING: No SNMP community or WMI credentials found. Collection is turned OFF.\n\n";
		}
	
		$LNT->{$node}{collect_snmp} = $collect_snmp ? 'true' : 'false';
		$LNT->{$node}{collect_wmi} = $collect_wmi ? 'true' : 'false';
		$nodeDataChanged = 1;
		
		print "Node $node collect=$LNT->{$node}{collect} collect_snmp=$LNT->{$node}{collect_snmp} collect_wmi=$LNT->{$node}{collect_wmi}\n";	
	}
	
	if ( $nodeDataChanged ) {
		# backup the nodes file
		my $nodesFile = "$C->{'<nmis_conf>'}/Nodes.nmis";
		my $backupFile = "$C->{'<nmis_base>'}/backup/Nodes.nmis.". time();
		
		print "Backup $nodesFile to $backupFile\n";
		createDir("$C->{'<nmis_base>'}/backup");
		setFileProtParents("$C->{'<nmis_base>'}/backup", $C->{'<nmis_base>'}); # which includes the parents up to nmis_base
		backupFile(file => $nodesFile, backup => $backupFile);
		setFileProt($backupFile);
		writeHashtoFile(file=>$nodesFile, data=>$LNT);
	}

	
	#logMsg("INFO NMIS has successfully converted the nodeConf data structure, and the old nodeConf file was renamed to \"$oldncf.disabled\".");

	return undef;
}
