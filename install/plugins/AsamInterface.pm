# a small update plugin for discovering interfaces on alcatel asam devices
# which requires custom snmp accesses
package AsamInterface;
our $VERSION = "1.2.2";

use strict;

use NMIS;												# lnt
use func;												# for loading extra tables
use snmp 1.1.0;									# for snmp-related access
use Net::SNMP qw(oid_lex_sort);
use Data::Dumper;

sub update_plugin
{
	my (%args) = @_;
	my ($node, $S, $C) = @args{qw(node sys config)};

	my $NI = $S->ndinfo;

	# this plugin deals only with certain alcatel devices, and only ones with snmp enabled and working
	return (0,undef) if ( $NI->{system}{nodeModel} !~ "AlcatelASAM" 
												or !getbool($NI->{system}->{collect}));
	
	my $LNT = loadLocalNodeTable(); # fixme required? are rack_count and shelf_count kept in the node's ndinfo section?
	my $NC = $S->ndcfg;
	my $V = $S->view;

	# load any nodeconf overrides for this node
	my ($errmsg, $override) = get_nodeconf(node => $node)
			if (has_nodeconf(node => $node));
	logMsg("ERROR $errmsg") if $errmsg;
	$override ||= {};

	my $changesweremade = 0;

	my ($session, $error) = Net::SNMP->session(
                           #-hostname      => $NC->{node}{host},
                           #-port          => $NC->{node}{port},
                           #-version       => $NC->{node}{version},
                           #-community     => $NC->{node}{community},   # v1/v2c

                           -hostname      => $LNT->{$node}{host},
                           -port          => $LNT->{$node}{port},
                           -version       => $LNT->{$node}{version},
                           -community     => $LNT->{$node}{community},   # v1/v2c
                        );	

	if ( $error ) {
		dbg("ERROR with SNMP on $node: ". $error);
		return ($changesweremade,undef);
	}

	# Get the SNMP Session going.
	#my $snmp = snmp->new(name => $node);
	#return (2,"Could not open SNMP session to node $node: ".$snmp->error)
	#		if (!$snmp->open(config => $NC->{node}, host_addr => $NI->{system}->{host_addr}));
	#
	#return (2, "Could not retrieve SNMP vars from node $node: ".$snmp->error)
	#		if (!$snmp->testsession);
	
	# remove any old redundant useless and otherwise annoying entries.
	delete $S->{info}{interface};
	delete $V->{interface};

	#asamActiveSoftware1	standby
	#asamActiveSoftware2	active
	#asamSoftwareVersion1	/OSWP/OSWPAA37.432
	#asamSoftwareVersion2	OSWP/66.98.63.71/OSWPAA41.353/OSWPAA41.353
	
	#asamActiveSoftware1	standby
	#asamActiveSoftware2	active
	#asamSoftwareVersion1	OSWP/66.98.63.71/L6GPAA42.413/L6GPAA42.413
	#asamSoftwareVersion2	OSWP/66.98.63.71/OSWPAA42.413/OSWPAA42.413
	
	### 2013-08-09 New Version strings.
	#asamSoftwareVersion1 OSWP/66.98.63.71/OSWPAA41.363/OSWPAA41.363
	#asamSoftwareVersion2 OSWP/66.98.63.71/OSWPAA41.353/OSWPAA41.353
	
	### 2015-06-12 New Version strings.
	#asamSoftwareVersion1 OSWP/66.98.63.71/OSWPAA42.676/OSWPAA42.676
	#asamSoftwareVersion2 10.58.10.137/OSWP/OSWPAA46.588

	### 2015-06-17 New Version strings.
	#asamSoftwareVersion1 OSWP/OSWPAA43.322/OSWPRA43.322
	#asamSoftwareVersion2 OSWPRA41.353

	### 2021-09-22 New vesion strings for ASAM Nokia 6.2
	#asamSoftwareVersion1 OSWP/OSWPAA62.577",
	#asamSoftwareVersion2 OSWP/OSWPAA55.142",

	my $asamVersion41 = qr/OSWPAA41|L6GPAA41|OSWPAA37|L6GPAA37|OSWPRA41/;
	my $asamVersion42 = qr/OSWPAA42|L6GPAA42|OSWPAA46/;
	my $asamVersion43 = qr/OSWPRA43|OSWPAN43/;
	my $asamVersion62 = qr/OSWPAA62|OSWPAA55/;

	# we have been told index 17 of the eqptHolder is the ASAM Model	
	my $asamModel = $NI->{eqptHolder}{17}{eqptHolderPlannedType};

	if ( $asamModel eq "NFXS-A" ) {
		$asamModel = "7302 ($asamModel)";
	}
	elsif ( $asamModel eq "NFXS-B" ) {
		$asamModel = "7330-FD ($asamModel)";
	}
	elsif ( $asamModel eq "ARAM-D" ) {
		$asamModel = "ARAM-D ($asamModel)";
	}
	elsif ( $asamModel eq "ARAM-E" ) {
		$asamModel = "ARAM-E ($asamModel)";
	}

	$NI->{system}{asamModel} = $asamModel;
	$V->{system}{"asamModel_value"} = $asamModel;
	$V->{system}{"asamModel_title"} = "ASAM Model";
	
	my $rack_count = 1;
	my $shelf_count = 1;
	
	my $version;
	
	$rack_count = $LNT->{$node}{rack_count} if $LNT->{$node}{rack_count} ne "";
	$shelf_count = $LNT->{$node}{shelf_count} if $LNT->{$node}{shelf_count} ne "";
	
	$S->{info}{system}{rack_count} = $rack_count;
	$S->{info}{system}{shelf_count} = $shelf_count;
						
	my $asamSoftwareVersion = $S->{info}{system}{asamSoftwareVersion1};
	if ( $S->{info}{system}{asamActiveSoftware2} eq "active" ) 
	{
		$asamSoftwareVersion = $S->{info}{system}{asamSoftwareVersion2};
	}
	my @verParts = split("/",$asamSoftwareVersion);
	$asamSoftwareVersion = $verParts[$#verParts];
			
	my @ifIndexNum = ();
	#"Devices in release 4.1  (ARAM-D y ARAM-E)"
	if( $asamSoftwareVersion =~ /$asamVersion41/ ) {
		# How to identify it is an ARAM-D?
		#"For ARAM-D with extensions "
		$version = 4.1;
		my ($indexes,$rack_count,$shelf_count) = build_interface_indexes(NI => $NI);
		@ifIndexNum = @{$indexes};
		
	}
	#" release 4.2  ( ISAM FD y  ISAM-V) "
	elsif( $asamSoftwareVersion =~ /$asamVersion42/ )
	{
		$version = 4.2;
		my $indexes = build_interface_indexes(NI => $NI);
		@ifIndexNum = @{$indexes};
	}
	elsif( $asamSoftwareVersion =~ /$asamVersion43/ )
	{
		$version = 4.3;
		my ($indexes,$rack_count,$shelf_count) = build_interface_indexes(NI => $NI);
		@ifIndexNum = @{$indexes};
	}
	elsif( $asamSoftwareVersion =~ /$asamVersion62/ )
	{
		$version = 6.2;
		# this gets the ifIndexes of the ATM interfaces.
		my ($indexes) = build_interface_indexes(NI => $NI);
		@ifIndexNum = @{$indexes};
	}
	else {
		logMsg("ERROR: Unknown ASAM Version $node asamSoftwareVersion=$asamSoftwareVersion");
	}
	
	dbg("DEBUG version=$version asamSoftwareVersion=$asamSoftwareVersion");
	
	my $intfTotal = 0;
	my $intfCollect = 0; # reset counters
		
	foreach my $index (@ifIndexNum) {
		$intfTotal++;				
		my $ifDescr = getIfDescr(prefix => "ATM", version => $version, ifIndex => $index, asamModel => $asamModel);
		my $Description = getDescription(version => $version, ifIndex => $index);
		my $ifSpeedIn;
		my $ifSpeedOut;
		my $snmpdata;
		my $xdslIndex = $index;

		my $offset = 12288;
		if ( $version eq "4.2" )  {
			$offset = 6291456;
		}
		elsif ( $version eq "6.2" )  {
			$offset = 393216;
			$xdslIndex = $index - $offset;
		}

		my $offsetIndex = $index - $offset;

		my @atmVclVars = qw(
			asamIfExtCustomerId
			xdslLinkUpMaxBitrateUpstream
			xdslLinkUpMaxBitrateDownstream
		);

		my %atmOidSet = (
			asamIfExtCustomerId => "1.3.6.1.4.1.637.61.1.6.5.1.1.$offsetIndex",
			xdslLinkUpMaxBitrateUpstream =>	"1.3.6.1.4.1.637.61.1.39.12.1.1.11.$xdslIndex",
			xdslLinkUpMaxBitrateDownstream => "1.3.6.1.4.1.637.61.1.39.12.1.1.12.$xdslIndex",
		);

		# build an array combining the atmVclVars and atmOidSet into a single array
		my @oids = map {$atmOidSet{$_}} @atmVclVars;

		if ( $session ) {
			$snmpdata = $session->get_request(
				-varbindlist => \@oids
			);

			if ( $session->error() ) {
				dbg("ERROR with SNMP on $node: ". $session->error());
			}
		}
		else {
			dbg("ERROR some session problem with SNMP on $node");
		}

		if ( $snmpdata ) {
			# get the customer id
			my $oid = "1.3.6.1.4.1.637.61.1.6.5.1.1.$offsetIndex";
			if ( $snmpdata->{$oid} ne "" and $snmpdata->{$oid} !~ /SNMP ERROR/ ) {
				$Description = $snmpdata->{$oid};
			}
			# get the speed out
			$oid = "1.3.6.1.4.1.637.61.1.39.12.1.1.12.$xdslIndex";
			if ( $snmpdata->{$oid} ne "" and $snmpdata->{$oid} !~ /SNMP ERROR/ ) {
				$ifSpeedOut = $snmpdata->{$oid} * 1000;
			}
			# get the speed in
			$oid = "1.3.6.1.4.1.637.61.1.39.12.1.1.11.$xdslIndex";
			if ( $snmpdata->{$oid} ne "" and $snmpdata->{$oid} !~ /SNMP ERROR/ ) {
				$ifSpeedIn = $snmpdata->{$oid} * 1000;
			}

			if ( defined $NI->{Customer_ID} and defined $NI->{Customer_ID}{$offsetIndex} ) {
				$Description = $NI->{Customer_ID}{$offsetIndex}{asamIfExtCustomerId};
				dbg("Customer_ID $node $ifDescr $Description");
			}

			dbg("SNMP $node $ifDescr $Description, index=$index, offset=$offset, offsetIndex=$offsetIndex, customerid=$Description ifSpeedIn=$ifSpeedIn ifSpeedOut=$ifSpeedOut");
		}

		my $maxSpeed = $ifSpeedIn > $ifSpeedOut ? $ifSpeedIn : $ifSpeedOut;

		$S->{info}{interface}{$index} = {
			'Description' => $Description,
			'ifAdminStatus' => 'unknown',
			'ifDescr' => $ifDescr,
			'ifIndex' => $index,
			'ifLastChange' => '0:00:00',
			'ifLastChangeSec' => 0,
			'ifOperStatus' => 'unknown',
			'ifSpeed' => $maxSpeed,
			'ifSpeedIn' => $ifSpeedIn,
			'ifSpeedOut' => $ifSpeedOut,
			'ifType' => 'atm',
			'interface' => convertIfName($ifDescr),
			'real' => 'true',
		};
		
		# preset collect,event to required setting, Node Configuration Will override.
		$S->{info}{interface}{$index}{collect} = "false";
		$S->{info}{interface}{$index}{event} = "false";
		$S->{info}{interface}{$index}{threshold} = "false";
		
		# ifDescr must always be filled
		if ($S->{info}{interface}{$index}{ifDescr} eq "") { $S->{info}{interface}{$index}{ifDescr} = $index; }
		# check for duplicated ifDescr
		foreach my $i (sort {$a <=> $b} keys %{$S->{info}{interface}}) {
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
		else {
			$V->{interface}{"${index}_Description_value"} = $S->{info}{interface}{$index}{Description};
		}
		
		if ($thisintfover->{ifSpeed} ne '') {
			$S->{info}{interface}{$index}{nc_ifSpeed} = $S->{info}{interface}{$index}{ifSpeed}; # save
			$S->{info}{interface}{$index}{ifSpeed} = $V->{interface}{"${index}_ifSpeed_value"} = $thisintfover->{ifSpeed};
			### 2012-10-09 keiths, fixing ifSpeed to be shortened when using nodeConf
			$V->{interface}{"${index}_ifSpeed_value"} = convertIfSpeed($S->{info}{interface}{$index}{ifSpeed});
			info("Manual update of ifSpeed by nodeConf");
		}
		
		if ($thisintfover->{ifSpeedIn} ne '') {
			$S->{info}{interface}{$index}{nc_ifSpeedIn} = $S->{info}{interface}{$index}{ifSpeedIn}; # save
			$S->{info}{interface}{$index}{ifSpeedIn} = $thisintfover->{ifSpeedIn};
			
			### 2012-10-09 keiths, fixing ifSpeed to be shortened when using nodeConf
			$V->{interface}{"${index}_ifSpeedIn_value"} = convertIfSpeed($S->{info}{interface}{$index}{ifSpeedIn});
			info("Manual update of ifSpeedIn by nodeConf");
		}
		
		if ($thisintfover->{ifSpeedOut} ne '') {
			$S->{info}{interface}{$index}{nc_ifSpeedOut} = $S->{info}{interface}{$index}{ifSpeedOut}; # save
			$S->{info}{interface}{$index}{ifSpeedOut} = $thisintfover->{ifSpeedOut};

			### 2012-10-09 keiths, fixing ifSpeed to be shortened when using nodeConf
			$V->{interface}{"${index}_ifSpeedOut_value"} = convertIfSpeed($S->{info}{interface}{$index}{ifSpeedOut});
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
		} else {
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

		# ensuring the ifSpeeds get set.
		$V->{interface}{"${index}_ifSpeed_value"} = $S->{info}{interface}{$index}{ifSpeed};
		$V->{interface}{"${index}_ifSpeedIn_value"} = $S->{info}{interface}{$index}{ifSpeedIn};
		$V->{interface}{"${index}_ifSpeedOut_value"} = $S->{info}{interface}{$index}{ifSpeedOut};

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
	
	return (1,undef);							# happy, changes were made so please save view and nodes files
}

sub getRackShelfMatrix {
	my $version = shift;
	my $eqptHolder = shift;
	my %config;
	
	#ARAM-E , NFXS-A for 7302 FD  and/or NFXS-B  for 7330 FD
	my $shelfMatch = qr/ARAM\-D|ARAM\-E|NFXS\-A|NFXS\-B/;
	my $rackMatch = qr/ALTR\-A|ALTR\-E/;
	
	if ( $version eq "4.1" or $version eq "4.3" ) {	
		#eqptHolderPlannedType
		my $gotOneRack = 0;
		my $rack = 0;
		my $shelf = 0;
		foreach my $eqpt (sort {$a <=> $b} keys %{$eqptHolder} ) {
			dbg("$eqpt = eqptHolderPlannedType=$eqptHolder->{$eqpt}{eqptHolderPlannedType}");
			if ( $eqptHolder->{$eqpt}{eqptHolderPlannedType} =~ /$rackMatch/ ) {
				++$rack;
				$shelf = 0;
			}
			elsif ( $eqptHolder->{$eqpt}{eqptHolderPlannedType} =~ /$shelfMatch/ ) {
				++$shelf;
				$config{$rack}{$shelf} = $eqptHolder->{$eqpt}{eqptHolderPlannedType};
				if ( $gotOneRack ) {
					$gotOneRack = 0;
				}
			}
		}
	}
	elsif ( $version eq "4.2" ) {	
		my $slot = 0;
		my @indexes;
		#foreach my $eqpt (sort {$a <=> $b} keys %{$eqptHolder} ) {
		#	dbg("$eqpt, eqptHolderPlannedType=$eqptHolder->{$eqpt}{eqptHolderPlannedType}");
		#	if ( $eqptHolder->{$eqpt}{eqptHolderPlannedType} =~ /$rackMatch/ ) {
		#		++$slot;
		#	}
		#}
		foreach my $eqpt (sort {$a <=> $b} keys %{$eqptHolder} ) {
			dbg("$eqpt = eqptPortMapping=$eqptHolder->{$eqpt}{eqptPortMappingLSMSlot}");
			if ( $eqptHolder->{$eqpt}{eqptPortMappingLSMSlot} != 65535 ) {
				++$slot;
				push(@indexes,$eqptHolder->{$eqpt}{eqptPortMappingLSMSlot});
			}
		}
		$config{slot}{slots} = $slot;
		$config{slot}{indexes} = \@indexes;
	}
	
	# print Dumper(\%config) if $debug;
		
	return(\%config);
}

sub getIfDescr {
	my %args = @_;
	
	my $oid_value 		= $args{ifIndex};	
	my $prefix 		= $args{prefix};	
	my $asamModel 		= $args{asamModel};	
	
	if ( $args{version} eq "6.2" ) {
		my $slot_mask 		= 0x1FE00000;
		my $level_mask 		= 0x001E0000;	
		my $circuit_mask 	= 0x0001FE00;
			
		my $slot 	= ($oid_value & $slot_mask) 	>> 21;
		my $level 	= ($oid_value & $level_mask) 	>> 17;
		my $circuit = ($oid_value & $circuit_mask) 	>> 9;
		
		# Apparently this needs to be adjusted when going to decimal?
		if ( $slot > 1 ) {
			--$slot;
		}
		++$circuit;	
		
		$prefix = "XDSL" if $level == 16;
		
		my $slotCor = asamSlotCorrection($slot,$asamModel);

		dbg("ASAM getIfDescr: ifIndex=$args{ifIndex} slot=$slot slotCor=$slotCor asamVersion=$args{version} asamModel=$asamModel");

		return "$prefix-1-1-$slotCor-$circuit";	
	}
	elsif ( $args{version} eq "4.1" or $args{version} eq "4.3" ) {
		my $rack_mask 		= 0x70000000;
		my $shelf_mask 		= 0x07000000;
		my $slot_mask 		= 0x00FF0000;
		my $level_mask 		= 0x0000F000;
		my $circuit_mask 	= 0x00000FFF;
	
		my $rack 	= ($oid_value & $rack_mask) 		>> 28;
		my $shelf 	= ($oid_value & $shelf_mask) 		>> 24;
		my $slot 	= ($oid_value & $slot_mask) 		>> 16;
		my $level 	= ($oid_value & $level_mask) 		>> 12;
		my $circuit = ($oid_value & $circuit_mask);

		# Apparently this needs to be adjusted when going to decimal?
		$slot = $slot - 2;
		++$circuit;	
		
		my $slotCor = asamSlotCorrection($slot,$asamModel);

		dbg("ASAM getIfDescr: ifIndex=$args{ifIndex} slot=$slot $slotCor=$slotCor asamVersion=$args{version} asamModel=$asamModel");

		return "$prefix-$rack-$shelf-$slotCor-$circuit";
	}
	else {
		my $slot_mask 		= 0x7E000000;
		my $level_mask 		= 0x01E00000;	
		my $circuit_mask 	= 0x001FE000;
			
		my $slot 		= ($oid_value & $slot_mask) 		>> 25;
		my $level 	= ($oid_value & $level_mask) 		>> 21;
		my $circuit = ($oid_value & $circuit_mask) 	>> 13;
		
		# Apparently this needs to be adjusted when going to decimal?
		if ( $slot > 1 ) {
			--$slot;
		}
		++$circuit;	
		
		$prefix = "XDSL" if $level == 16;
		
		my $slotCor = asamSlotCorrection($slot,$asamModel);

		dbg("ASAM getIfDescr: ifIndex=$args{ifIndex} slot=$slot slotCor=$slotCor asamVersion=$args{version} asamModel=$asamModel");

		return "$prefix-1-1-$slotCor-$circuit";		
	}
}

sub asamSlotCorrection {
	my $slot = shift;
	my $asamModel = shift;
	
	if ( $asamModel =~ /7302/ ) {
		if ( $slot == 17 or $slot == 18 ) {
			$slot = $slot - 7;
		} 
		elsif ( $slot >= 9 ) {
			$slot = $slot + 3;
		} 
	}
	elsif ( $asamModel =~ /ARAM-D/ ) {
		$slot = $slot + 3
	}
	elsif ( $asamModel =~ /ARAM-E/ ) {
		if ( $slot == 17 or $slot == 18 ) {
			$slot = $slot - 9;
		} 
		elsif ( $slot < 7 ) {
			$slot = $slot + 1
		}
		elsif ( $slot >= 7 ) {
			$slot = $slot + 5
		}
	}
	elsif ( $asamModel =~ /7330-FD/ ) {
		if ( $slot < 9 ) {
			$slot = $slot + 3
		}
		elsif ( $slot == 9 or $slot == 10 ) {
			$slot = $slot - 7
		}
	}

	return $slot;
} 

sub getDescription {
	my %args = @_;
	
	my $oid_value 		= $args{ifIndex};	
	
	if ( $args{version} eq "4.1" ) {
		my $rack_mask 		= 0x70000000;
		my $shelf_mask 		= 0x07000000;
		my $slot_mask 		= 0x00FF0000;
		my $level_mask 		= 0x0000F000;
		my $circuit_mask 	= 0x00000FFF;
	
		my $rack 		= ($oid_value & $rack_mask) 		>> 28;
		my $shelf 	= ($oid_value & $shelf_mask) 		>> 24;
		my $slot 		= ($oid_value & $slot_mask) 		>> 16;
		my $level 	= ($oid_value & $level_mask) 		>> 12;
		my $circuit = ($oid_value & $circuit_mask);
		
		# Apparently this needs to be adjusted when going to decimal?
		$slot = $slot - 2;
		++$circuit;	

		return "Rack=$rack, Shelf=$shelf, Slot=$slot, Circuit=$circuit";
	}
	else {
		my $slot_mask 		= 0x7E000000;
		my $level_mask 		= 0x01E00000;	
		my $circuit_mask 	= 0x001FE000;
		
		my $slot 		= ($oid_value & $slot_mask) 		>> 25;
		my $level 	= ($oid_value & $level_mask) 		>> 21;
		my $circuit = ($oid_value & $circuit_mask) 	>> 13;

		if ( $slot > 1 ) {
			--$slot;
		}
		++$circuit;	

		return "Slot=$slot, Level=$level, Circuit=$circuit";		
	}
}

sub build_41_interface_indexes {
	my %args = @_;
	my $NI = $args{NI};

	my $rack_count = 1;
	my $shelf_count = 1;

	my $systemConfig;
	
	#Look at the eqptHolderPlannedType data to see what is planned for this device.
	if ( exists $NI->{eqptHolder} ) {
		$systemConfig = getRackShelfMatrix("4.1",$NI->{eqptHolder});
		$rack_count = 0;
		$shelf_count = 0;
	}

	# For ARAM-D with extensions the shelf value changes to 2 for the first extension (shelf = 010) , 3 for the second (shelf = 11) … and so on, 
	# such that the first port of the first card of the first extension would be:
	my $level = 3;

	my @slots = (3..6);
	my @circuits = (0..47);
		
	my @interfaces = ();
	
	my $gotSysConfig = 0;
	foreach my $rack (sort {$a <=> $b} keys %{$systemConfig} ) {
		$gotSysConfig = 1;
		++$rack_count;
		dbg("  rack=$rack");

		foreach my $shelf (sort {$a <=> $b} keys %{$systemConfig->{$rack}} ) {
			++$shelf_count;

			# This represents slots 1 to 4, a maximum of 4 slots per Shelf.
			@slots = (3..6);
			
			if ( $systemConfig->{$rack}{$shelf} eq "ARAM-E" ) {
				# If this is ARAM-E the slots are not sequential, but oddly numbered and there are 9 slots per shelf
				@slots = (3,5,7,9,11,13,15,17,19);
			}
			
			dbg("    shelf=$shelf type=$systemConfig->{$rack}{$shelf} slots=@slots");
			foreach my $slot (@slots) {
				foreach my $circuit (@circuits) {
					my $index = generate_interface_index_41 ( rack => $rack, shelf => $shelf, slot => $slot, level => $level, circuit => $circuit);
					push( @interfaces, $index );
				}		
			}
		}
	}

	if ( not $gotSysConfig ) {
		my $rack = 1;
		my $shelf = 1;
		foreach my $slot (@slots) {
			foreach my $circuit (@circuits) {
				my $index = generate_interface_index_41 ( rack => $rack, shelf => $shelf, slot => $slot, level => $level, circuit => $circuit);
				push( @interfaces, $index );
			}		
		}
	}
	
	return (\@interfaces,$rack_count,$shelf_count);
}

sub build_42_interface_indexes {
	my %args = @_;
	my $NI = $args{NI};
	my $systemConfig;

	my $level = 3;
	
	#Look at the eqptHolderPlannedType data to see what is planned for this device.
	#if ( exists $NI->{eqptHolder} ) {
	#	$systemConfig = getRackShelfMatrix("4.2",$NI->{eqptHolder});
	#}
	if ( exists $NI->{eqptHolder} ) {
		$systemConfig = getRackShelfMatrix("4.2",$NI->{eqptPortMapping});
	}
	
	my $slot_count = $systemConfig->{slot}{slots};
	# correct the slot_count
	#my $slot_limit = ( $slot_count * 2 ) + 2;
	my $slot_limit = $slot_count + 1;
	#my $slot_limit = $slot_count;
	
	#dbg("DEBUG slot_count=$slot_count slot_limit=$slot_limit");
	dbg("DEBUG slot_count=$slot_count slot_limit=$slot_limit indexes=@{$systemConfig->{slot}{indexes}}");

	#Slot count x 2 + 3? Or + 2
	
	my @slots = (2..$slot_limit);
	my @circuits = (0..47);

	my @interfaces = ();

	foreach my $slot (@slots) {
		foreach my $circuit (@circuits) {
			my $index = generate_interface_index_42 ( slot => $slot, level => $level, circuit => $circuit);
			push( @interfaces, $index );
		}		
	}
	return \@interfaces;
}

sub build_interface_indexes {
	my %args = @_;
	my $NI = $args{NI};
	my $systemConfig;

	my $level = 3;
	
	my @interfaces = ();
	
	if ( exists $NI->{ifTable} ) {
		foreach my $ifIndex (oid_lex_sort(keys(%{$NI->{ifTable}}))) {
			if ( $NI->{ifTable}{$ifIndex}{ifDescr} eq "atm Interface" ) {
				push( @interfaces, $ifIndex );
			}
		}
	}
	
	dbg("DEBUG indexes=@interfaces");

	return \@interfaces;
}

sub generate_interface_index_41 {
	my %args = @_;
	my $rack = $args{rack};
	my $shelf = $args{shelf};
	my $slot = $args{slot};
	my $level = $args{level};
	my $circuit = $args{circuit};

	my $index = 0;
	$index = ($rack << 28) | ($shelf << 24) | ($slot << 16) | ($level << 12) | ($circuit);
	return $index;
}

sub generate_interface_index_42 {
	my %args = @_;
	my $slot = $args{slot};
	my $level = $args{level};
	my $circuit = $args{circuit};

	my $index = 0;
	$index = ($slot << 25) | ($level << 21) | ($circuit << 13);
	return $index;
}

###############################################
#
# 4.1
#
# •	Level = 
# •	0000b for XDSL line, SHDSL Line, Ethernet Line, VoiceFXS Line or IsdnU Line 
# •	0001b for XDSL Channel  

###############################################
sub decode_interface_index_41 {
	my %args = @_;

	my $oid_value 		= 285409280;	
	if( defined $args{oid_value} ) {
		$oid_value = $args{oid_value};
	}
	my $rack_mask 		= 0x70000000;
	my $shelf_mask 		= 0x07000000;
	my $slot_mask 		= 0x00FF0000;
	my $level_mask 		= 0x0000F000;
	my $circuit_mask 	= 0x00000FFF;
	
	my $slot_bitshift = 16;

	print "4.1 Oid value=$oid_value\n";

	my $rack 		= ($oid_value & $rack_mask) 		>> 28;
	my $shelf 	= ($oid_value & $shelf_mask) 		>> 24;
	my $slot 		= ($oid_value & $slot_mask) 		>> $slot_bitshift;
	my $level 	= ($oid_value & $level_mask) 		>> 12;
	my $circuit = ($oid_value & $circuit_mask);

	printf( "\t rack=0x%x, %d\n", $rack, $rack);
	printf( "\t shelf=0x%x, %d\n", $shelf, $shelf);
	printf( "\t slot=0x%x, %d\n", $slot, $slot);
	printf( "\t level=0x%x, %d\n", $level, $level);
	printf( "\t circuit=0x%x, %d\n", $circuit, $circuit);
	
	#print "rack=X, shelf=Y, slot=Z, level=A, circuit=B"

	if( $level == 0xb ) {
		print "XDSL Line\n";
	}
	if( $level == 0x1b ) {
		print "XDSL Channel\n";
	}

}

###############################################
#
# 4.2
#	XDSL/SHDSL line, voiceFXS, IsdnU, XDSL channel, bonding/IMA interface, ATM/EFM interface, LAG interface
# •	Level=0000b….0100b, see Table 1
###############################################
sub decode_interface_index_42 {
	my %args = @_;
	my $oid_value 		= 67108864;
	if( $args{oid_value} ne '' ) {
		$oid_value = $args{oid_value};
	}
	
	my $slot_mask 		= 0x7E000000;
	my $level_mask 		= 0x01E00000;	
	my $circuit_mask 	= 0x001FE000;
	
	my $slot 		= ($oid_value & $slot_mask) 		>> 25;
	my $level 	= ($oid_value & $level_mask) 		>> 21;
	my $circuit = ($oid_value & $circuit_mask) 	>> 13;

	printf("4.2 Oid value=%d, 0x%x, %b\n", $oid_value, $oid_value, $oid_value);
	printf( "\t slot=0x%x, %d\n", $slot, $slot);
	printf( "\t level/card=0x%x, %d\n", $level, $level);
	printf( "\t circuit/port=0x%x, %d\n", $circuit, $circuit);
	if( $level >= 0xB && $level <= 0x100B) {
		print "XDSL/SHDSL line, voiceFXS, IsdnU, XDSL channel, bonding/IMA interface, ATM/EFM interface, LAG interface\n";
	}
}

1;
