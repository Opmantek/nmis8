#!/usr/bin/env perl

use FindBin;
use lib "/usr/local/nmis8/conf/plugins";
use lib "$FindBin::Bin/../lib"; 

use strict;
use CiscoMerakiCloud;
use Data::Dumper;

my @deviceList = qw(
	GID_30596_TELUM
	GID_25867_TELUM
	GID_164876_IMSS_MEGACABLE_71349
	GID_67011_TELECABLE
	GID_22520_CABLEVISION
	MX_WALTER_BONA
);

my $debug = 1;

foreach my $deviceName (@deviceList) {
	my $merakiData = getMerakiData(name => $deviceName);
	if ( defined $merakiData->{error} ) {
		print "ERROR with $deviceName: $merakiData->{error}\n";
	}
	print "$deviceName: status=$merakiData->{status} perfScore=$merakiData->{perfScore} avgLatency=$merakiData->{avgLatency} avgLossPercent=$merakiData->{avgLossPercent} maxLossPercent=$merakiData->{maxLossPercent}\n" if $debug;
	print Dumper $merakiData if $debug;
}

