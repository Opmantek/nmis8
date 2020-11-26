#
#  Copyright Opmantek Limited (www.opmantek.com)
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
#
# MLA: Created to get topology changes working with vlans. TBD: graphs

package ciscoTopChanges;
our $VERSION = "1.0.0";

use strict;

use func;												# for the conf table extras
use NMIS;												# lnt
use snmp 1.1.0;									# for snmp-related access

sub update_plugin
{
	my (%args) = @_;
	my ($node,$S,$C) = @args{qw(node sys config)};

	my $LNT = loadLocalNodeTable();
	
	my $NI = $S->ndinfo;
	my $IF = $S->ifinfo;
	my $NC = $S->ndcfg;
	# anything to do?

	my $status = {
		'1' => 'other',
		'2' => 'invalid',
		'3' => 'learned',
		'4' => 'self',
		'5' => 'mgmt',
	};

	return (0,undef) if (not defined $S->{mdl}{systemHealth}{sys}{topChanges} or ref($NI->{vtpVlan}) ne "HASH");
	
	#dot1dBase
	#vtpVlan
	
	info("Working on $node topChanges");

	my $changesweremade = 0;

	my $max_repetitions = $NC->{node}->{max_repetitions} || $C->{snmp_max_repetitions};
	
	for my $key (keys %{$NI->{vtpVlan}})
	{
		my $entry = $NI->{vtpVlan}->{$key};

		info("processing vtpVlan $entry->{vtpVlanName}");
	
		# get the VLAN ID Number from the index
		if ( my @parts = split(/\./,$entry->{index}) ) {
			shift(@parts); # dummy
			$entry->{vtpVlanIndex} = shift(@parts);
			$changesweremade = 1;
		}
				
		# Get the connected devices if the VLAN is operational
		if ( $entry->{vtpVlanState} eq "operational" ) 
		{
			my %nodeconfig = %{$NC->{node}}; # copy required because we modify it...
			
			# community string: <normal>@<vlanindex>
			# https://www.cisco.com/c/en/us/support/docs/ip/simple-network-management-protocol-snmp/40367-camsnmp40367.html
			my $magic = $nodeconfig{community}.'@'.$entry->{vtpVlanIndex};
			$nodeconfig{community} = $magic;

			$nodeconfig{host_addr} = $NI->{system}->{host_addr};

			# nmisng::snmp doesn't fall back to global config
			my $max_repetitions = $nodeconfig{max_repetitions} || $C->{snmp_max_repetitions};

			my $snmp = snmp->new(name => $node);
			if (!$snmp->open(config => \%nodeconfig ))
			{
				logMsg("Could not open SNMP session to node $node: ".$snmp->error);
			}
			else
			{
				my ($addresses, $ports, $addressStatus, $baseIndex);
				if (!$snmp->testsession)
				{
					logMsg("Could not retrieve SNMP vars from node $node: ".$snmp->error);
				}
				my $dot1dStpTopChanges = "1.3.6.1.2.1.17.2.4"; #dot1dStpTopChanges
					
				my $topChanges = $snmp->gettable($dot1dStpTopChanges,$max_repetitions);

				foreach my $key (keys %$topChanges)
				{
					info("Got topology changes:" . $topChanges->{$key});
					
					$NI->{topChanges}->{$entry->{vtpVlanIndex}}{TopChanges} = $topChanges->{$key};					
					$NI->{topChanges}->{$entry->{vtpVlanIndex}}{vlan} = $entry->{vtpVlanIndex};
				}
			}
		}
	}
	return ($changesweremade,undef); # report if we changed anything
}


1;
