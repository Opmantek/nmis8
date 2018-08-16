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
# a small update plugin for handling various Cisco features like CBQoS and Netflow

package Cisco_Features;
our $VERSION = "1.2.0";

use strict;

use func;												# for the conf table extras
use NMIS;

sub update_plugin
{
	my (%args) = @_;
	my ($node,$S,$C) = @args{qw(node sys config)};
	
	my $NI = $S->ndinfo;
	my $IF = $S->ifinfo;
	
	# anything to do?
	my $changesweremade = 0;
	if (ref($NI->{cpu_cpm}) eq "HASH") {

		info("Working on $node cpu_cpm");
		
		for my $index (keys %{$NI->{cpu_cpm}})
		{
			my $entry = $NI->{cpu_cpm}{$index};
			my $entityIndex = $entry->{cpmCPUTotalPhysicalIndex};
			if ( defined $NI->{entityMib}{$entityIndex}{entPhysicalName} ) {
				$entry->{entPhysicalName} = $NI->{entityMib}{$entityIndex}{entPhysicalName};
				$changesweremade = 1;
			}
			else {
				info("WARNING entPhysicalName not available for index $index");
			}
	
			if ( defined $NI->{entityMib}{$entityIndex}{entPhysicalDescr} ) {
				$entry->{entPhysicalDescr} = $NI->{entityMib}{$entityIndex}{entPhysicalDescr};
				$changesweremade = 1;
			}
			else {
				info("WARNING entPhysicalDescr not available for index $index");
			}
		}
	}
	
	if (ref($NI->{Cisco_CBQoS}) eq "HASH") {

		info("Working on $node Cisco_CBQoS");
		
		for my $key (keys %{$NI->{Cisco_CBQoS}})
		{
			my $entry = $NI->{Cisco_CBQoS}->{$key};
			my @parts;
	
			#   "Cisco_CBQoS" : {
			#      "354" : {
			#         "cbQosPolicyDirection" : "output",
			#         "index" : "354",
			#         "cbQosIfType" : "mainInterface",
			#         "cbQosIfIndex" : 22
			#      },
						
			if ( defined $IF->{$entry->{cbQosIfIndex}}{ifDescr} ) {
				$entry->{ifDescr} = $IF->{$entry->{cbQosIfIndex}}{ifDescr};
				$entry->{ifDescr_url} = "/cgi-nmis8/network.pl?conf=$C->{conf}&act=network_interface_view&intf=$entry->{cbQosIfIndex}&node=$node";
				$entry->{ifDescr_id} = "node_view_$node";
				$entry->{Description} = $IF->{$entry->{cbQosIfIndex}}{Description};
				$changesweremade = 1;
			}
		}
	}

	if (ref($NI->{NetFlowInterfaces}) eq "HASH") {

		info("Working on $node NetFlowInterfaces");
		
		for my $key (keys %{$NI->{NetFlowInterfaces}})
		{
			my $entry = $NI->{NetFlowInterfaces}->{$key};
			my @parts;
							
			if ( defined $IF->{$entry->{index}}{ifDescr} ) {
				$entry->{ifDescr} = $IF->{$entry->{index}}{ifDescr};
				$entry->{ifDescr_url} = "/cgi-nmis8/network.pl?conf=$C->{conf}&act=network_interface_view&intf=$entry->{index}&node=$node";
				$entry->{ifDescr_id} = "node_view_$node";
				$entry->{Description} = $IF->{$entry->{index}}{Description};
				$changesweremade = 1;
			}
		}
	}

	# if there is EntityMIB data then load map out the entPhysicalVendorType to the vendor type fields
	# store in the field called Type.
	if (ref($NI->{entityMib}) eq "HASH") {
		info("Working on $node entityMib");
		
		my $vendorOids = loadVendorOids($C);

		for my $key (keys %{$NI->{entityMib}})
		{
			my $entry = $NI->{entityMib}->{$key};

			if ( defined $entry->{entPhysicalVendorType} and $vendorOids->{$entry->{entPhysicalVendorType}} ne "" ) {
				$entry->{cardType} = $vendorOids->{$entry->{entPhysicalVendorType}};
				$entry->{cardType} =~ s/^cev//;
				$changesweremade = 1;
			}
		}
	}
	
	return ($changesweremade,undef); # report if we changed anything
}

sub loadVendorOids {
	my $C = shift;
	
	my $oids = "$C->{mib_root}/CISCO-ENTITY-VENDORTYPE-OID-MIB.oid";
	my $vendorOids;
	
	info("Loading Vendor OIDs from $oids");
	
	open(OIDS,$oids) or warn "ERROR could not load $oids: $!\n";
	
	my $match = qr/\"(\w+)\"\s+\"([\d+\.]+)\"/;
	
	while (<OIDS>) {
		if ( $_ =~ /$match/ ) {
			$vendorOids->{$2} = $1;
		}
		elsif ( $_ =~ /^#|^\s+#/ ) {
			#all good comment
		}
		else {
			info("ERROR: no match $_");
		}
	}
	close(OIDS);
	
	return ($vendorOids);
}

1;
