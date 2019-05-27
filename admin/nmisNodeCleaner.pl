#!/usr/bin/perl
#
#  Copyright 1999-2015 Opmantek Limited (www.opmantek.com)
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
# This helper is there to help get your Nodes.nmis clean of issues when people make bad edits.

use FindBin;
use lib "$FindBin::Bin/../lib";
use strict;
use warnings;
use func;

my %arg = getArguements(@ARGV);
my $nodesFile = "$FindBin::Bin/../conf/Nodes.nmis";

my $usage = "Usage: act=run\n";

die $usage if (!@ARGV or ( $arg{run} ne 'true'));

my $nodesHash = readFiletoHash(file=>$nodesFile);

my $newNodeHash;
my $actionRequired = 0;

my $backupFile = $nodesFile .".". time(); 
my $backup = backupFile(file => $nodesFile, backup => $backupFile);
setFileProt($backupFile);
if ( $backup ) {
        print "$nodesFile backup'ed up to $backupFile\n";
}


foreach my $outerNode ( sort keys % { $nodesHash } ) {
	my $lcOuterNode = lc $outerNode;
	my $keep = 1;
	if ( not defined($nodesHash->{$outerNode}->{uuid}) ) {
		print "$outerNode has no UUID and shall be deleted.\n";
		$actionRequired = 1;
		next;
	}
	elsif ( $outerNode ne $nodesHash->{$outerNode}->{name} ) {
		print "$outerNode has a node-key node-name mismatch and shall be deleted\n";
		$actionRequired = 1;
		next;  
	}
	foreach my $innerNode ( sort keys % { $nodesHash } ) {
		my $lcInnerNode = lc $innerNode;
		if ($lcOuterNode eq $lcInnerNode) {
			if ($nodesHash->{$outerNode}->{uuid} ne $nodesHash->{$innerNode}->{uuid}) {
				print "$outerNode is a case mutated duplicate of $innerNode and shall be deleted\n";
				$keep = 0;
				$actionRequired = 1;
				last;
			}
		}
	}
        if ( defined($nodesHash->{$outerNode}->{host_backup}) && $nodesHash->{$outerNode}->{host_backup} eq '' ) {
                print "$outerNode has a blank host_backup entry that shall be set to undefined\n";
		$nodesHash->{$outerNode}->{host_backup} = undef;
        }
	if ( $keep == 1 ) {
		$newNodeHash->{$outerNode} = $nodesHash->{$outerNode};
	}
}

writeHashtoFile(file=>$nodesFile, data=>$newNodeHash);

if ( $actionRequired == 1 ) {
	system('rm -vf /usr/local/nmis8/var/nmis-nodesum.json');
	system('rm -vf /usr/local/nmis8/var/nmis-summary*.json');
	system('/usr/local/nmis8/bin/nmis.pl type=summary');
}

