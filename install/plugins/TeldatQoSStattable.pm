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
# a small update plugin for getting the TeldatQoSStat ifDescr

package TeldatQoSStattable;
our $VERSION = "1.0.1";

use strict;

use func;												# for the conf table extras
use NMIS;

use Data::Dumper;

sub update_plugin
{
	my (%args) = @_;
	my ($node,$S) = @args{qw(node sys)};
	#my ($node,$S,$C) = @args{qw(node sys config)};
	
	my $NI = $S->ndinfo;
	my $IF = $S->ifinfo;
	# anything to do?

	#my $IFD = $S->ifDescrInfo(); # interface info indexed by ifDescr

	return (0,undef) if (ref($NI->{TeldatQoSStat}) ne "HASH");
	my $changesweremade = 0;

	
	info("Working on $node TeldatQoSStattable");
     

	for my $key (keys %{$NI->{TeldatQoSStat}})
	{
		my $entry = $NI->{TeldatQoSStat}->{$key};
		if ( defined($entry->{ifIndex}) ) {
			$changesweremade = 1;

			my $ifindex = $entry->{ifIndex};
			
                        # Get the devices ifDescr.
                        if ( defined $IF->{$ifindex}{ifDescr} ) {
                                $entry->{ifDescr} = $IF->{$ifindex}{ifDescr};

				info("Found QoS Entry with interface $entry->{ifIndex}. 'ifDescr' = '$entry->{ifDescr}'.");
				dbg("TeldatQoSStattable.pm: Node $node updating node info QualityOfServiceStat $entry->{index}: new '$entry->{ifDescr}'");
                        }
                        else
                        {
				info("'ifDescr' could not be determined for ifIndex '$ifindex'.");
                        }
		}
		else
		{
			info("\$entry->{ifIndex} not defined. 'ifDescr' could not be determined for '$entry->{index}'");
		}
	}

	return ($changesweremade,undef); # report if we changed anything
}

1;
