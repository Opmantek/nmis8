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
# a small update plugin for converting the cdp index into interface name.

package CiscoDSL;
our $VERSION = "1.0.1";

use strict;
use NMIS;												# lnt
use func;												# for the conf table extras
use Data::Dumper;
use Net::SNMP qw(oid_lex_sort);

sub update_plugin
{
	my (%args) = @_;
	my ($node,$S,$C) = @args{qw(node sys config)};

	my $LNT = loadLocalNodeTable(); # fixme required? are rack_count and shelf_count kept in the node's ndinfo section?
	my $NC = $S->ndcfg;
	my $NI = $S->ndinfo;
	my $IF = $S->ifinfo;
	my $ifTable = $NI->{ifTable};
	
	my $changesweremade = 0;
	
	# anything to do?  if the data we need isn't there, return.
	return (0,undef) if ( not defined $NI->{ifStack} );

	info("Working on $node ifStack");

  # sample ifStack information
  #"ifStack" : {
  #   "0.11" : {
  #      "index" : "0.11",
  #      "ifStackStatus" : "active"
  #   },
  #   "11.12" : {
  #      "index" : "11.12",
  #      "ifStackStatus" : "active"
  #   },
  #   "12.14" : {
  #      "index" : "12.14",
  #      "ifStackStatus" : "active"
  #   },   
  #   "13.14" : {
  #      "index" : "13.14",
  #      "ifStackStatus" : "active"
  #   },
  #   "14.0" : {
  #      "index" : "14.0",
  #      "ifStackStatus" : "active"
  #   },


	for my $key (oid_lex_sort(keys %{$NI->{ifStack}}))
	{
		my $entry = $NI->{ifStack}->{$key};
		
		if ( my @parts = split(/\./,$entry->{index}) ) {
			my $ifStackHigherLayer = shift(@parts);
			my $ifStackLowerLayer = shift(@parts);
			
			$entry->{ifStackHigherLayer} = $ifStackHigherLayer;
			$entry->{ifStackLowerLayer} = $ifStackLowerLayer;
			
			if ( defined $IF->{$ifStackHigherLayer} and defined $IF->{$ifStackHigherLayer}{ifDescr} ) {
				#delete $IF->{$ifStackHigherLayer}{ifStackLowerLayer};
				# in the interfaces table, add the details of what is an upper or lower interface.
				if (ref($IF->{$ifStackHigherLayer}{ifStackLowerLayer}) eq "SCALAR") {
					delete $IF->{$ifStackHigherLayer}{ifStackLowerLayer};
				}
				push(@{$IF->{$ifStackHigherLayer}{ifStackLowerLayer}},$ifStackLowerLayer);
								
				# create a linkage in the GUI so people can see the relationships
				$entry->{ifDescrHigherLayer} = $IF->{$ifStackHigherLayer}{ifDescr};
				$entry->{ifDescrHigherLayer_url} = "/cgi-nmis8/network.pl?conf=$C->{conf}&act=network_interface_view&intf=$ifStackHigherLayer&node=$node";
				$entry->{ifDescrHigherLayer_id} = "node_view_$node";
			}

			if ( defined $IF->{$ifStackLowerLayer} and defined $IF->{$ifStackLowerLayer}{ifDescr} ) {				
				#delete $IF->{$ifStackLowerLayer}{ifStackHigherLayer};
				# in the interfaces table, add the details of what is an upper or lower interface.
				if (ref($IF->{$ifStackLowerLayer}{ifStackHigherLayer}) eq "SCALAR") {
					delete $IF->{$ifStackLowerLayer}{ifStackHigherLayer};
				}
				push(@{$IF->{$ifStackLowerLayer}{ifStackHigherLayer}},$ifStackHigherLayer);
				
				# create a linkage in the GUI so people can see the relationships
				$entry->{ifDescrLowerLayer} = $IF->{$ifStackLowerLayer}{ifDescr};
				$entry->{ifDescrLowerLayer_url} = "/cgi-nmis8/network.pl?conf=$C->{conf}&act=network_interface_view&intf=$ifStackLowerLayer&node=$node";
				$entry->{ifDescrLowerLayer_id} = "node_view_$node";
			}

			dbg("WHAT: ifDescr=$IF->{$ifStackHigherLayer}{ifDescr} ifStackHigherLayer=$entry->{ifStackHigherLayer} ifStackLowerLayer=$entry->{ifStackLowerLayer} ");

			$changesweremade = 1;
		}
	}
	
	return ($changesweremade,undef); # report if we changed anything
}



1;
