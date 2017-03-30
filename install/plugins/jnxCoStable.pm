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

package jnxCoStable;
our $VERSION = "1.0.0";

use strict;

use func;												# for the conf table extras
use NMIS;

use Data::Dumper;

sub update_plugin
{
	my (%args) = @_;
	my ($node,$S,$C) = @args{qw(node sys config)};
	
	my $NI = $S->ndinfo;
	my $IF = $S->ifinfo;
	# anything to do?

    my $IFD = $S->ifDescrInfo(); # interface info indexed by ifDescr

	return (0,undef) if (ref($NI->{Juniper_CoS}) ne "HASH");
	my $changesweremade = 0;

	
	info("Working on $node jnxCoStable");

 
      

	for my $key (keys %{$NI->{Juniper_CoS}})
	{
		my $entry = $NI->{Juniper_CoS}->{$key};
		
		if ( $entry->{index} =~ /(\d+)\.\d+\.(.+)$/ ) {
			
			$changesweremade = 1;
			
			my $intIndex = $1;
			my $FCcodename = $2;
			my $FCname = join("", map { chr($_) } split(/\./,$FCcodename));
			$entry->{jnxCosFcName} = $FCname . ' Class' ;

			
			$entry->{ifIndex} = $intIndex;
			$entry->{IntName} = $IF->{$entry->{ifIndex}}{ifDescr};
		    $entry->{IntName_url} = "/cgi-nmis8/network.pl?conf=$C->{conf}&act=network_interface_view&intf=$entry->{ifIndex}&node=$node";
		    $entry->{cosDescription} = $entry->{IntName} . '-' . $FCname . '-Class';
		  
			
			info("Found COS Entry with interface $entry->{IntName} and $entry->{jnxCosFcName} ");
		}
	}

	return ($changesweremade,undef); # report if we changed anything
}

1;
