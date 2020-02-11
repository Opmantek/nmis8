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
# a small update plugin for converting the Huawei HQoS Interface index into interface name.

package HuaweiHqos;
our $VERSION = "1.1.0";

use strict;

use func; # required for logMsg

use NMIS;


sub update_plugin
{
	my (%args) = @_;
	my ($node,$S,$C) = @args{qw(node sys config)};

	my $NI = $S->ndinfo;
	my $IF = $S->ifinfo;
	my $IFD = $S->ifDescrInfo(); # interface info indexed by ifDescr

	return (0,undef) if (ref($NI->{Huawei_ProfUserHQoS}) ne "HASH");
	my $changesweremade = 0;

	info("Huawei_ProfUserHQoS plugin update-phase Working on $node HQoS Table");


	for my $key (keys %{$NI->{Huawei_ProfUserHQoS}})
	{
		my $entry = $NI->{Huawei_ProfUserHQoS}{$key};
		$entry->{ifDescr} = $IF->{$entry->{ifIndex}}{ifDescr};
		$entry->{Description} = $IF->{$entry->{ifIndex}}{Description};
    	$entry->{ifDescr_url} = "/cgi-nmis8/network.pl?conf=$C->{conf}&act=network_interface_view&intf=$entry->{ifIndex}&node=$node";
		$entry->{ifDescr_id} = "node_view_$node";
		$changesweremade = 1;

	}


return ($changesweremade,undef); # report if we changed anything
}	

1;
