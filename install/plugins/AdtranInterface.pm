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
# a small update plugin for discovering interfaces on netgear 108 and 723 devices
# which requires custom snmp accesses
package AdtranInterface;
our $VERSION = "1.0.2";
use strict;

use func;												# for the conf table extras
use NMIS;												# get_nodeconf
use Data::Dumper;
use snmp 1.1.0;									# for snmp-related access

my $interestingInterfaces = qr/ten-gigabit-ethernet|^muxponder-highspeed/;

sub update_plugin
{
	my (%args) = @_;
	my ($node, $S, $C) = @args{qw(node sys config)};

	my $NI = $S->ndinfo;

	# this plugin deals only with this specific device type, and only ones with snmp enabled and working
	return (0,undef) if ( $NI->{system}{nodeModel} ne "Adtran-TA5000" or !getbool($NI->{system}->{collect}));

	my $NC = $S->ndcfg;
	my $V = $S->view;
	
	# load any nodeconf overrides for this node
	my ($errmsg, $override) = get_nodeconf(node => $node)
			if (has_nodeconf(node => $node));
	logMsg("ERROR $errmsg") if $errmsg;
	$override ||= {};

	my $max_repetitions = $NC->{node}->{max_repetitions} || $C->{snmp_max_repetitions};

	# Get the SNMP Session going.
	my $snmp = snmp->new(name => $node);
	return (2,"Could not open SNMP session to node $node: ".$snmp->error)
			if (!$snmp->open(config => $NC->{node}, host_addr => $NI->{system}->{host_addr}));
	
	return (2, "Could not retrieve SNMP vars from node $node: ".$snmp->error)
			if (!$snmp->testsession);
	
	
	my @ifIndexNum = ();
	my $intfTotal = 0;
	my $intfCollect = 0; # reset counters

	# do a walk to get the indexes which we know are OK.
	#ifName 1.3.6.1.2.1.31.1.1.1.1
	my $ifDescr = "1.3.6.1.2.1.2.2.1.2";

	info("getting a list of names using ifDescr: $ifDescr");

	my $changesweremade = 0;

	my $IFT = loadifTypesTable();

	my $names;
	if ( $names = $snmp->getindex($ifDescr,$max_repetitions) )
	{
		$changesweremade = 1;
		foreach my $key (keys %$names) 
		{
			if ( $names->{$key} =~ /$interestingInterfaces/ ) {
				push(@ifIndexNum,$key);
			}
		}
	}

	print "Could not retrieve SNMP vars from node $node: ".$snmp->error if $snmp->error;

	my $nameDump = Dumper $names;
	dbg($nameDump);

	my $ifTypeOid = "1.3.6.1.2.1.2.2.1.3";
	my $ifSpeedOid = "1.3.6.1.2.1.2.2.1.5";
	my $ifAdminStatusOid = "1.3.6.1.2.1.2.2.1.7";
	my $ifOperStatusOid = "1.3.6.1.2.1.2.2.1.8";

	foreach my $index (@ifIndexNum) 
	{
		$intfTotal++;				
		my @oids = (
			"$ifTypeOid.$index",
			"$ifSpeedOid.$index",
			"$ifAdminStatusOid.$index",
			"$ifOperStatusOid.$index",
		);
		
		# Store them straight into the results
		my $snmpData = $snmp->get(@oids);
		return (2, "Failed to retrieve SNMP variables: ".$snmp->error) 
				if (ref($snmpData) ne "HASH");

		my $ifDescr = $names->{$index};		
		my $ifType = $IFT->{$snmpData->{"$ifTypeOid.$index"}}{ifType};
		my $ifSpeed = $snmpData->{"$ifSpeedOid.$index"};
		my $ifAdminStatus = ifStatus($snmpData->{"$ifAdminStatusOid.$index"});
		my $ifOperStatus = ifStatus($snmpData->{"$ifOperStatusOid.$index"});

		$ifSpeed = 10000000000 if ( $ifDescr =~ /ten-gigabit-ethernet/ );
		$ifSpeed = 10000000000 if ( $ifSpeed == 4294967295 );
				
		dbg("SNMP $node $ifDescr $ifSpeed");
				
		$S->{info}{interface}{$index} = 
		{
			'Description' => '',
			'ifAdminStatus' => $ifAdminStatus,
			'ifDescr' => $ifDescr,
			'ifIndex' => $index,
			'ifOperStatus' => $ifOperStatus,
			'ifSpeed' => $ifSpeed,
			'ifSpeedIn' => $ifSpeed,
			'ifSpeedOut' => $ifSpeed,
			'ifType' => $ifType,
			'interface' => convertIfName($ifDescr),
		};

		my $intDump = Dumper $S->{info}{interface}{$index};
		dbg($intDump);
				
		# preset collect,event to required setting, Node Configuration Will override.
		$S->{info}{interface}{$index}{collect} = $ifAdminStatus eq "up" ? "true": "false";
		$S->{info}{interface}{$index}{event} = $ifAdminStatus eq "up" ? "true": "false";
		$S->{info}{interface}{$index}{threshold} = $ifAdminStatus eq "up" ? "true": "false";
									
		# ifDescr must always be filled
		if ($S->{info}{interface}{$index}{ifDescr} eq "") { $S->{info}{interface}{$index}{ifDescr} = $index; }
		# check for duplicated ifDescr
		foreach my $i (keys %{$S->{info}{interface}}) {
			if ($index ne $i and $S->{info}{interface}{$index}{ifDescr} eq $S->{info}{interface}{$i}{ifDescr}) {
				$S->{info}{interface}{$index}{ifDescr} = "$S->{info}{interface}{$index}{ifDescr}-${index}"; # add index to string
				$V->{interface}{"${index}_ifDescr_value"} = $S->{info}{interface}{$index}{ifDescr}; # update
				dbg("Interface Description changed to $S->{info}{interface}{$index}{ifDescr}");
			}
		}
		my $thisintfover = $override->{$ifDescr} || {};
		
		### add in anything we find from nodeConf - allows manual updating of interface variables
		### warning - will overwrite what we got from the device - be warned !!!
		if ($thisintfover->{Description} ne '') {
			$S->{info}{interface}{$index}{nc_Description} = $S->{info}{interface}{$index}{Description}; # save
			$S->{info}{interface}{$index}{Description} = $V->{interface}{"${index}_Description_value"} = $thisintfover->{Description};
			dbg("Manual update of Description by nodeConf");
		}
		
		if ($thisintfover->{ifSpeed} ne '') {
			$S->{info}{interface}{$index}{nc_ifSpeed} = $S->{info}{interface}{$index}{ifSpeed}; # save
			$S->{info}{interface}{$index}{ifSpeed} = $V->{interface}{"${index}_ifSpeed_value"} = $thisintfover->{ifSpeed};
			### 2012-10-09 keiths, fixing ifSpeed to be shortened when using nodeConf
			info("Manual update of ifSpeed by nodeConf");
		}
	
		if ($thisintfover->{ifSpeedIn} ne '') {
			$S->{info}{interface}{$index}{nc_ifSpeedIn} = $S->{info}{interface}{$index}{ifSpeedIn}; # save
			$S->{info}{interface}{$index}{ifSpeedIn} = $thisintfover->{ifSpeedIn};
			
			### 2012-10-09 keiths, fixing ifSpeed to be shortened when using nodeConf
			info("Manual update of ifSpeedIn by nodeConf");
		}
	
		if ($thisintfover->{ifSpeedOut} ne '') {
			$S->{info}{interface}{$index}{nc_ifSpeedOut} = $S->{info}{interface}{$index}{ifSpeedOut}; # save
			$S->{info}{interface}{$index}{ifSpeedOut} = $thisintfover->{ifSpeedOut};

			### 2012-10-09 keiths, fixing ifSpeed to be shortened when using nodeConf
			info("Manual update of ifSpeedOut by nodeConf");
		}
		
		# convert interface name
		$S->{info}{interface}{$index}{interface} = convertIfName($S->{info}{interface}{$index}{ifDescr});
		$S->{info}{interface}{$index}{ifIndex} = $index;
		
		### 2012-11-20 keiths, updates to index node conf table by ifDescr instead of ifIndex.
		# modify by node Config ?
		if ($thisintfover->{collect} ne '' and $thisintfover->{ifDescr} eq $S->{info}{interface}{$index}{ifDescr}) {
			$S->{info}{interface}{$index}{nc_collect} = $S->{info}{interface}{$index}{collect};
			$S->{info}{interface}{$index}{collect} = $thisintfover->{collect};
			dbg("Manual update of Collect by nodeConf");
			if ($S->{info}{interface}{$index}{collect} eq 'false') {
				$S->{info}{interface}{$index}{nocollect} = "Manual update by nodeConf";
			}
		}
		if ($thisintfover->{event} ne '' and $thisintfover->{ifDescr} eq $S->{info}{interface}{$index}{ifDescr}) {
			$S->{info}{interface}{$index}{nc_event} = $S->{info}{interface}{$index}{event};
			$S->{info}{interface}{$index}{event} = $thisintfover->{event};
			$S->{info}{interface}{$index}{noevent} = "Manual update by nodeConf" if $S->{info}{interface}{$index}{event} eq 'false'; # reason
			dbg("Manual update of Event by nodeConf");
		}
		if ($thisintfover->{threshold} ne '' and $thisintfover->{ifDescr} eq $S->{info}{interface}{$index}{ifDescr}) {
			$S->{info}{interface}{$index}{nc_threshold} = $S->{info}{interface}{$index}{threshold};
			$S->{info}{interface}{$index}{threshold} = $thisintfover->{threshold};
			$S->{info}{interface}{$index}{nothreshold} = "Manual update by nodeConf" if $S->{info}{interface}{$index}{threshold} eq 'false'; # reason
			dbg("Manual update of Threshold by nodeConf");
		}
		
		# interface now up or down, check and set or clear outstanding event.
		if ( $S->{info}{interface}{$index}{collect} eq 'true'
				 and $S->{info}{interface}{$index}{ifAdminStatus} =~ /up|ok/ 
				 and $S->{info}{interface}{$index}{ifOperStatus} !~ /up|ok|dormant/ 
				) {
			if ($S->{info}{interface}{$index}{event} eq 'true') {
				notify(sys=>$S,event=>"Interface Down",element=>$S->{info}{interface}{$index}{ifDescr},details=>$S->{info}{interface}{$index}{Description});
			}
		} 
		else 
		{
			checkEvent(sys=>$S,event=>"Interface Down",level=>"Normal",element=>$S->{info}{interface}{$index}{ifDescr},details=>$S->{info}{interface}{$index}{Description});
		}
		
		$S->{info}{interface}{$index}{threshold} = $S->{info}{interface}{$index}{collect};
		
		# number of interfaces collected with collect and event on
		$intfCollect++ if $S->{info}{interface}{$index}{collect} eq 'true' && $S->{info}{interface}{$index}{event} eq 'true';
		
		# save values only if all interfaces are updated
		$NI->{system}{intfTotal} = $intfTotal;
		$NI->{system}{intfCollect} = $intfCollect;
		
		# prepare values for web page
		$V->{interface}{"${index}_ifDescr_value"} = $S->{info}{interface}{$index}{ifDescr};

		$V->{interface}{"${index}_event_value"} = $S->{info}{interface}{$index}{event};
		$V->{interface}{"${index}_event_title"} = 'Event on';
		
		$V->{interface}{"${index}_threshold_value"} = $NC->{node}{threshold} ne 'true' ? 'false': $S->{info}{interface}{$index}{threshold};
		$V->{interface}{"${index}_threshold_title"} = 'Threshold on';
		
		$V->{interface}{"${index}_collect_value"} = $S->{info}{interface}{$index}{collect};
		$V->{interface}{"${index}_collect_title"} = 'Collect on';

		$V->{interface}{"${index}_ifSpeed_value"} = convertIfSpeed($S->{info}{interface}{$index}{ifSpeed});
		$V->{interface}{"${index}_ifSpeedIn_value"} = convertIfSpeed($S->{info}{interface}{$index}{ifSpeedIn});
		$V->{interface}{"${index}_ifSpeedOut_value"} = convertIfSpeed($S->{info}{interface}{$index}{ifSpeedOut});
		
		# collect status
		delete $V->{interface}{"${index}_nocollect_title"};
		if ($S->{info}{interface}{$index}{collect} eq "true") {
			dbg("ifIndex $index, collect=true");
		} else {
			$V->{interface}{"${index}_nocollect_value"} = $S->{info}{interface}{$index}{nocollect};
			$V->{interface}{"${index}_nocollect_title"} = 'Reason';
			dbg("ifIndex $index, collect=false, $S->{info}{interface}{$index}{nocollect}");
			# no collect => no event, no threshold
			$S->{info}{interface}{$index}{threshold} = $V->{interface}{"${index}_threshold_value"} = 'false';
			$S->{info}{interface}{$index}{event} = $V->{interface}{"${index}_event_value"} = 'false';
		}
		
		# get color depending of state
		$V->{interface}{"${index}_ifAdminStatus_color"} = getAdminColor(sys=>$S,index=>$index);
		$V->{interface}{"${index}_ifOperStatus_color"} = getOperColor(sys=>$S,index=>$index);
		$V->{interface}{"${index}_ifAdminStatus_value"} = $S->{info}{interface}{$index}{ifAdminStatus};
		$V->{interface}{"${index}_ifOperStatus_value"} = $S->{info}{interface}{$index}{ifOperStatus};
		
		# Add the titles as they are missing from the model.
		$V->{interface}{"${index}_ifOperStatus_title"} = 'Oper Status';
		$V->{interface}{"${index}_ifDescr_title"} = 'Name';
		$V->{interface}{"${index}_ifSpeed_title"} = 'Bandwidth';
		$V->{interface}{"${index}_ifType_title"} = 'Type';
		$V->{interface}{"${index}_ifAdminStatus_title"} = 'Admin Status';
		$V->{interface}{"${index}_ifLastChange_title"} = 'Last Change';
		$V->{interface}{"${index}_Description_title"} = 'Description';
		
		# index number of interface
		$V->{interface}{"${index}_ifIndex_value"} = $index;
		$V->{interface}{"${index}_ifIndex_title"} = 'ifIndex';
	}

	return ($changesweremade,undef);							# happy, and changes were made so save view and nodes file
}

sub ifStatus {
	my $statusNumber = shift;
	
	return 'up' if $statusNumber == 1;
	return 'down' if $statusNumber == 2;
	return 'testing' if $statusNumber == 3;
	return 'dormant' if $statusNumber == 5;
	return 'notPresent' if $statusNumber == 6;
	return 'lowerLayerDown' if $statusNumber == 7;
	
	# 4 is unknown.
	return 'unknown';
}	

1;

