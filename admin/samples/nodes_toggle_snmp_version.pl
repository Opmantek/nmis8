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
#
# this small contraption toggles multiple nodes' snmp versions between 1 and 2c,
# if the node is currently marked as 'snmp down'. other nodes are not
# touched. when done, a new conf/Nodes.nmis.new is left for you to
# activate/peruse.

use FindBin;
use lib "$FindBin::Bin/../lib";

use strict;
use func;
use NMIS;

# Get some command line arguements.
my %arg = getArguements(@ARGV);

# Load the NMIS Config
my $C = loadConfTable(conf=>$arg{conf},debug=>$arg{debug});

# Load the current Nodes Table.
my $LNT = loadLocalNodeTable();

my $mustupdate;
foreach my $node (sort keys %{$LNT})
{
	if (getbool($LNT->{$node}{active}) 
			and getbool($LNT->{$node}{collect}))
	{
		my $infodata = readFiletoHash(file => $C->{'<nmis_var>'}.lc("/$node-node.json"));
		next if (!getbool($infodata->{system}->{snmpdown}));
		my $currentversion = $LNT->{$node}->{version};
		next if ($currentversion eq "snmpv3");
		
		$LNT->{$node}->{version} = ($currentversion eq "snmpv1")? "snmpv2c" : "snmpv1";
		++$mustupdate;
		print "Updating $node, from $currentversion to $LNT->{$node}->{version}\n";
	}
}

if ($mustupdate)
{
	writeHashtoFile(file => "$C->{'<nmis_conf>'}/Nodes.nmis.new", data => $LNT);
}


