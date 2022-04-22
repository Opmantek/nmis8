#!/usr/bin/env perl
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
# a test stub to use the CiscoMerakiCloud plugin as a library for testing.

use FindBin;
use lib "/usr/local/nmis8/install/plugins";
use lib "$FindBin::Bin/../lib"; 

use strict;
use AlcatelASAM;
use Data::Dumper;

my $version = "4.1";

my $ifIndex = 1080449536;
my $ifIndex = 1077936640;
my $asamModel = "7302 (NFXS-A)";

# New version is 6.2

my $node = "ASANPEDRO19";
my $asamModel = "7302";
my $version = "6.2";

my @ifIndexes = qw(
1080449536
1077936640
);

foreach my $ifIndex (@ifIndexes) {
	my $ifDescr = getIfDescr(prefix => "ATM", version => $version, ifIndex => $ifIndex, asamModel => $asamModel);	
	print "node=$node asamModel=$asamModel version=$version ifIndex=$ifIndex ifDescr=$ifDescr\n";
}

my $node = "ACHAMN1";
my $asamModel = "7330-FD";
my $version = "6.2";

my @ifIndexes = qw(
8294333608
8092360445
);

foreach my $ifIndex (@ifIndexes) {
	my $ifDescr = getIfDescr(prefix => "ATM", version => $version, ifIndex => $ifIndex, asamModel => $asamModel);	
	print "node=$node asamModel=$asamModel version=$version ifIndex=$ifIndex ifDescr=$ifDescr\n";
}

my $node = "ABONAO13";
my $asamModel = "7302";
my $version = "6.2";

my @ifIndexes = qw(
6369972979
8098964506
8092961253
8098964946
8092963796
8098964722
);

foreach my $ifIndex (@ifIndexes) {
	my $ifDescr = getIfDescr(prefix => "ATM", version => $version, ifIndex => $ifIndex, asamModel => $asamModel);	
	print "node=$node asamModel=$asamModel version=$version ifIndex=$ifIndex ifDescr=$ifDescr\n";
}





