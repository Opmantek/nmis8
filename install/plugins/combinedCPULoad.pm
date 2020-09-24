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

package combinedCPULoad;
our $VERSION = "1.0.0";

use strict;
use warnings;
use func;	# for the conf table extras
use NMIS;
use rrdfunc;
use Data::Dumper;

sub collect_plugin
{
	my (%args) = @_;
	my ($node,$S,$C) = @args{qw(node sys config)};

	my $NI = $S->ndinfo;

	my $cpu_total = 0;

	my @instances = $S->getTypeInstances(section => "hrsmpcpu");

	my $rrddata = {};


	if (scalar @instances > 1){
		info("Working on $node Combined CPU Average Load");

		my $cpu_max = 0;

		foreach my $index (@instances) {
			# Get each CPU
			$cpu_total += $NI->{"device"}{$index}->{"hrCpuLoad"};
			$cpu_max = $NI->{"device"}{$index}->{"hrCpuLoad"} if ($NI->{"device"}{$index}->{"hrCpuLoad"} > $cpu_max);

			$rrddata->{"cpu_$index"} = { "option" => "GAUGE,0:U", "value" => $NI->{"device"}{$index}->{"hrCpuLoad"}},
		}

		my $cpu_count = scalar @instances;
		my $cpu_average = $cpu_total / $cpu_count;

		$rrddata->{'cpu_total'} = { "option" => "GAUGE,0:U", "value" => $cpu_total};
		$rrddata->{'cpu_max'} = { "option" => "GAUGE,0:U", "value" => $cpu_max};
		$rrddata->{'cpu_average'} = { "option" => "GAUGE,0:U", "value" => $cpu_average};
		$rrddata->{'cpu_count'} = { "option" => "GAUGE,0:U", "value" => $cpu_count};

		# updateRRD subrutine is called from rrdfunc.pm module
	    my $updatedrrdfileref = updateRRD(data=>$rrddata, sys=>$S, type=>"combinedCPUload", index => undef);

		# check for RRD update errors
		if (!$updatedrrdfileref) { info("Update RRD failed!") };


		# if (not defined $NI->{graphtype}{combinedCPUload}){
			$NI->{graphtype}{combinedCPUload} = "combinedCPUload";
		# }
	}
	return (1,undef);
}

1;