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
# this is a small example plugin, which doesn't do 
# anything useful but demonstrate the concept.
package TestPlugin;
our $VERSION = "1.0.0";
use strict;

use func; # required for logMsg

sub after_update_plugin
{
	my (%args) = @_;
	my ($nodes, $S, $C) = @args{qw(nodes sys config)};

	logMsg("The test plugin was run in the after_update phase");
	# this was hanging on the telmex servers
	#logMsg("Nodes that this update handled: ".join(", ",@$nodes)) if (ref($nodes) eq "ARRAY");

	return (0,undef);
}

sub after_collect_plugin
{
	my (%args) = @_;
	my ($nodes, $S, $C) = @args{qw(nodes sys config)};


	logMsg("The test plugin was run in the after_collect phase");
	# this was hanging on the telmex servers
	#logMsg("Nodes that this collect handled: ".join(", ",@$nodes)) if (ref($nodes) eq "ARRAY");

	return (0,undef);
}

sub update_plugin
{
	my (%args) = @_;
	my ($node, $S, $C) = @args{qw(node sys config)};

	logMsg("The test plugin was run in the per-node update phase for node $node");

	return (0,undef);
}

sub collect_plugin
{
	my (%args) = @_;
	my ($node, $S, $C) = @args{qw(node sys config)};


	logMsg("The test plugin was run in the per-node collect phase for node $node");

	return (0,undef);
}



1;
