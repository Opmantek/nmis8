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

use FindBin;
use lib "$FindBin::Bin/../lib";

# Include for reference
#use lib "/usr/local/nmis8/lib";

# 
use strict;
use Fcntl qw(:DEFAULT :flock);
use func;
use NMIS;
use NMIS::Timing;

# set these variables.
my @syncFields = qw(sysLocation location group);

my $t = NMIS::Timing->new();

print $t->elapTime(). " Begin\n";

# Variables for command line munging
my %arg = getArguements(@ARGV);

# Set debugging level.
my $debug = setDebug($arg{debug});
my $nmisDebug = $debug if $debug > 1;

# load configuration table
my $C = loadConfTable(conf=>$arg{conf},debug=>$nmisDebug);
my $LNT = loadLocalNodeTable();

foreach my $node (sort keys %{$LNT}) {

	if ( getbool($LNT->{$node}{active}) ) {

		my $S = Sys::->new; # get system object
		$S->init(name=>$node,snmp=>'false'); # load node info and Model if name exists
		my $NI = $S->ndinfo;

		my @updateFields;
		foreach my $field (@syncFields) {
			if ( defined $NI->{system}{$field} and $NI->{system}{$field} ne "" ) {
				print "Node $node $field=$NI->{system}{$field}\n" if $debug;
				push(@updateFields,"entry.$field=\"$NI->{system}{$field}\"");
			}
		}
		my $updateThese = join(" ",@updateFields);

		my $exec = "/usr/local/omk/bin/opnode_admin.pl act=set node=$node $updateThese";
		my $out = `$exec`;
		print "Node $node: $exec\n$out\n" if $debug;
	}
}


