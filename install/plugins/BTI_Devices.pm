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
# a small update plugin for handling various things the BTI devices need

package BTI_Devices;
our $VERSION = "1.0.0";

use strict;

use func;												# for the conf table extras
use NMIS;

sub update_plugin
{
	my (%args) = @_;
	my ($node,$S,$C) = @args{qw(node sys config)};
	
	my $NI = $S->ndinfo;
	
	# anything to do?
	return (0,undef) if ( $NI->{system}{nodeModel} !~ "BTI-7000" or !getbool($NI->{system}->{collect}));

	# anything to do?
	my $changesweremade = 0;
	my @sections = qw(BTI_7000_GE_Ports BTI_7000_STM_Optical BTI_7000_GE_Optical BTI_7000_FC_Optical BTI_7000_GE_Bytes);
	foreach my $section (@sections) {
		if (ref($NI->{$section}) eq "HASH") {
			info("Working on $node $section");
			$changesweremade = 1;
		
			for my $index (keys %{$NI->{$section}})
			{
				my $entry = $NI->{$section}{$index};
				my @parts = split(/\./,$index);
				if ( @parts == 5 ) {
					# dispose of the first field
					shift @parts;
				}
				my $interface = "GE";
				if ( $section =~ /BTI_7000_(\w+)_/ ) {
					$interface = $1;
				}
				my $shelf = $parts[0];
				my $slot = $parts[1];
				my $port = $parts[2];
				my $name = "$interface/Shelf-$shelf/Slot-$slot/Port-$port";
				$entry->{name} = $name;
		
			}
		}
	}
	if (ref($NI->{BTI_7000_Slot_Inventory}) eq "HASH") {
		info("Working on $node BTI_7000_Slot_Inventory");
		$changesweremade = 1;
	
		for my $index (keys %{$NI->{BTI_7000_Slot_Inventory}})
		{
			my $entry = $NI->{BTI_7000_Slot_Inventory}{$index};
			my @parts = split(/\./,$index);
			my $shelf = $parts[0];
			my $slot = $parts[2];
			my $name = "Shelf-$shelf/Slot-$slot";
			$entry->{name} = $name;
		}
	}
	return ($changesweremade,undef); # report if we changed anything
}

1;
