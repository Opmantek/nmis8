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

package Arris;
our $VERSION = "1.0.1";

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

	if (ref($NI->{cmtsmonups}) eq "HASH") {

		info("Working on $node cmtsmonups");
		
		foreach my $key (keys %{$NI->{cmtsmonups}}) {
			# working on an entry from the list of possible objects
			my $entry = $NI->{cmtsmonups}->{$key};
			
			# splitting the two part index into something we can use
			if ( my @parts = split(/\./,$entry->{index}) ) {
				
				# the MIB defines two parts of the index given these names
				#cadCmtsCmStatusMacChSummaryEntry OBJECT-TYPE
				#        SYNTAX      CadCmtsCmStatusMacChSummaryEntry
				#        MAX-ACCESS  not-accessible
				#        STATUS      current
				#        DESCRIPTION
				#            ""
				#        INDEX { cadIfMacDomainIfIndex, 
				#                cadMacChlChannelIfIndex}
				#        ::= { cadCmtsCmStatusMacChSummaryTable 1 }
				$entry->{cadIfMacDomainIfIndex} = shift(@parts);
				$entry->{cadMacChlChannelIfIndex} = shift(@parts);
				
				# use a shorter easier name now
				my $ifIndex = $entry->{cadMacChlChannelIfIndex};
	
				# do I have an interface defined for that index?
				if ( defined $IF->{$ifIndex}{ifDescr} ) {
					# copy the data we need out of the interface data, and use the special _url and _id fields for GUI stuff
					$entry->{ifDescr} = $IF->{$ifIndex}{ifDescr};
					$entry->{ifDescr_url} = "/cgi-nmis8/network.pl?conf=$C->{conf}&act=network_interface_view&intf=$ifIndex&node=$node";
					$entry->{ifDescr_id} = "node_view_$node";
					$entry->{Description} = $IF->{$ifIndex}{Description};
					$changesweremade = 1;
				}
			}
		}
	}	

	return ($changesweremade,undef); # report if we changed anything
}

1;
