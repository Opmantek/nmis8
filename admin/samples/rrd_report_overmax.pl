#!/usr/bin/perl
# a tiny helper to compare interface max speed against the actual rrd data,
# and counts+reports when and how often the transferred data goes above what the 
# interface speed indicate (= either dud interface speed max set, or bursting on the interface)

our $VERSION = "1.0.1";
use FindBin;
use lib "$FindBin::Bin/../../lib";

use strict;
use File::Basename;
use File::Find;
use Data::Dumper;
use Cwd;

use func;
use NMIS::uselib;
use lib "$NMIS::uselib::rrdtool_lib";
use RRDs 1.000.490;

die "Usage: ".basename($0). " <rrdfile> <dsname> <if max bits/sec> <days to look back>\n"
		if (@ARGV != 4 && $ARGV[0] =~ /^(help|--?h(elp)?|--?\?)$/);

my ($fn, $ds, $max, $examine) = @ARGV;

print basename($0)." $VERSION starting up.\n\n";
my $C = loadConfTable(conf=>undef, dir => "$FindBin::RealBin/../../conf", debug=>undef);


print "checking RRD $fn\n";
# get the info, check if min and max are set
my $rrdinfo = RRDs::info($fn);

my $dsmax = $rrdinfo->{"ds[$ds].max"};
my $dsmin = $rrdinfo->{"ds[$ds].min"};

print "$ds has set max $dsmax byte/s (= ".($dsmax*8)." bps)\n";
print "$ds has set min $dsmin byte/s (= ".($dsmin*8)." bps)\n";

my $intfmaxbytes = int($max/8);

print  "script was given interface speed $max bps (= $intfmaxbytes) byte/s)\n",
		"ds max is normally set to 2x interface speed\n";

my $rrdstep = $rrdinfo->{step};
$rrdstep ||= 300;

my $now = time;
$examine *= 86400;
$now = $now - ($now % $rrdstep);
my ($begin,$step,$names,$data) = RRDs::fetch($fn, "AVERAGE", "--start" => $now-$examine, "--end" => $now);
print "Warning: RRD has step $rrdstep, but fetch returned step $step.\n" if ($step != $rrdstep);

		
my $timesovermax;
 ROWS: 	for my $ridx (0..$#$data)
{
	my $row = $data->[$ridx];
	for my $idx (0..$#{$row})
	{
		my $thisdsname = $names->[$idx];
		next if ($thisdsname ne $ds);
		
		my $value = $row->[$idx];
		if ($value > $intfmaxbytes)
		{
			$timesovermax++;
			print scalar localtime($begin+($step*$ridx)),
			" $thisdsname above interface max ($value > $intfmaxbytes)\n";
		}
	}
}

print "Total readings in period: ".scalar(@$data)."\n",
		"times over interface maximum speed: $timesovermax\n";




