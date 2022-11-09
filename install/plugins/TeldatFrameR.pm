
package TeldatFrameR;
our $VERSION = "1.0.3";

use strict;

use func;												# for the conf table extras
use NMIS;

use Data::Dumper;

sub update_plugin
{
	my (%args) = @_;
	my ($node,$S,$C) = @args{qw(node sys config)};

	my $sub = 'update';
	my $plugin = 'TeldatFrameR.pm';
	my $concept = 'TeldatFRStat';

	dbg("$plugin:$sub: \$node: ".Dumper \$node,9);
	dbg("$plugin:$sub: \$S: ".Dumper \$S,9);
	dbg("$plugin:$sub: \$C: ".Dumper \$C,9);

	my $NI = $S->ndinfo;
	dbg("$plugin:$sub: \$NI: ".Dumper \$NI,9);

	# anything to do?
	return (0,undef) if (ref($NI->{$concept}) ne "HASH");
	dbg("$plugin:$sub: \$NI->{$concept}: ".Dumper \$NI->{$concept},9);

	my $IF = $S->ifinfo;
	dbg("$plugin:$sub: \$IF: ".Dumper \$IF,9);

	my $changesweremade = 0;

	info("$plugin:$sub: Working on $node $plugin");


	for my $key (keys %{$NI->{$concept}})
	{
		my $entry = $NI->{$concept}->{$key};
		dbg("$plugin:$sub: \$entry: ".Dumper \$entry,9);

		if ( defined($entry->{ifIndex}) )
		{
			$changesweremade = 1;

			my $ifindex = $entry->{ifIndex};

			# Get the devices ifDescr.
			if ( defined $IF->{$ifindex}{ifDescr} )
			{
				$entry->{ifDescr} = $IF->{$ifindex}{ifDescr};
				$entry->{sysDescr} = $IF->{$ifindex}{Description};
				$entry->{ifAlias} = $IF->{$ifindex}{sysDescr};
				$entry->{ifType} = $IF->{$ifindex}{ifType};
				$entry->{ifOperStatus} = $IF->{$ifindex}{ifOperStatus};
				# populate virtual field with ifDescr:ClassifierName
				$entry->{ifDescr_ClassifierName} = "$entry->{ifDescr}:$entry->{ClassifierName}";

				info("$plugin:$sub: Found FrameRelay Entry with interface $entry->{ifIndex}. 'ifDescr' = '$entry->{ifDescr}'.");
                info("$plugin:$sub: 'ifDescr_ClassifierName' = '$entry->{ifDescr_ClassifierName}'.");

				dbg("$plugin:$sub: Node $node updating node info $concept $entry->{index}: new '$entry->{ifDescr}'");
			}
			else
			{
				# no ifDescr: fall back to populate virtual field with ifIndex:ClassifierName
				$entry->{ifDescr_ClassifierName} = "$entry->{ifIndex}:$entry->{ClassifierName}";
				info("$plugin:$sub: 'ifDescr' could not be determined for ifIndex '$ifindex': 'ifDescr_ClassifierName' = '$entry->{ifDescr_ClassifierName}'.");
			}
			dbg("$plugin:$sub: \$ifindex '$ifindex' updated \$entry:\n".Dumper \$entry,9);
		}
		else
		{
			info("$plugin:$sub: \$entry->{ifIndex} not defined. 'ifDescr' could not be determined for '$entry->{index}'");
		}
	}

	return ($changesweremade,undef); # report if we changed anything
}

# collect plugin is needed as 'ClassifierName' is converted from integer index to equivalent string during collect phase:
#   getSystemHealthData, updating node info TeldatBRSStat 7.5 ClassifierName: old '5' new 'ce.mt'
sub collect_plugin
{
	my (%args) = @_;
	my ($node,$S,$C) = @args{qw(node sys config)};

	my $sub = 'collect';
	my $plugin = 'TeldatFrameR.pm';
	my $concept = 'TeldatFRStat';

	dbg("$plugin:$sub: \$node: ".Dumper \$node,9);
	dbg("$plugin:$sub: \$S: ".Dumper \$S,9);
	dbg("$plugin:$sub: \$C: ".Dumper \$C,9);

	my $NI = $S->ndinfo;
	dbg("$plugin:$sub: \$NI: ".Dumper \$NI,9);

	# anything to do?
	return (0,undef) if (ref($NI->{$concept}) ne "HASH");
	dbg("$plugin:$sub: \$NI->{$concept}: ".Dumper \$NI->{$concept},9);

	#my $IF = $S->ifinfo;
	#dbg("$plugin:$sub: \$IF: ".Dumper \$IF,9);

	my $changesweremade = 0;

	info("$plugin:$sub: Working on $node $plugin");

	for my $key (keys %{$NI->{$concept}})
	{
		my $entry = $NI->{$concept}->{$key};
		dbg("$plugin:$sub: \$entry: ".Dumper \$entry,9);

		if ( defined($entry->{ifIndex}) )
		{
			$changesweremade = 1;

			my $ifindex = $entry->{ifIndex};

			# Get the devices ifDescr.
			if ( defined $entry->{ifDescr} )
			{
				# populate virtual field with ifDescr:ClassifierName
				$entry->{ifDescr_ClassifierName} = "$entry->{ifDescr}:$entry->{ClassifierName}";
				info("$plugin:$sub: 'ifDescr_ClassifierName' = '$entry->{ifDescr_ClassifierName}'.");
			}
			else
			{
				# no ifDescr: fall back to populate virtual field with ifIndex:ClassifierName
				$entry->{ifDescr_ClassifierName} = "$entry->{ifIndex}:$entry->{ClassifierName}";
				info("$plugin:$sub: '\$entry->{ifDescr}' is undefined for ifIndex '$ifindex': 'ifDescr_ClassifierName' = '$entry->{ifDescr_ClassifierName}'.");
			}
			dbg("$plugin:$sub: \$ifindex '$ifindex' updated \$entry:\n".Dumper \$entry,9);
		}
		else
		{
			info("$plugin:$sub: \$entry->{ifIndex} not defined. 'ifDescr' could not be determined for '$entry->{index}'");
		}
	}

	return ($changesweremade,undef); # report if we changed anything
}

1;
