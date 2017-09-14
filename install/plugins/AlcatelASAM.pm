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
# a small update plugin for converting the cdp index into interface name.

package AlcatelASAM;
our $VERSION = "1.2.0";

use strict;
use NMIS;												# lnt
use func;												# for the conf table extras
use snmp 1.1.0;									# for snmp-related access
use Net::SNMP qw(oid_lex_sort);
use Data::Dumper;

sub update_plugin
{
	my (%args) = @_;
	my ($node,$S,$C) = @args{qw(node sys config)};

	my $LNT = loadLocalNodeTable(); # fixme required? are rack_count and shelf_count kept in the node's ndinfo section?
	my $NC = $S->ndcfg;
	my $NI = $S->ndinfo;
	my $IF = $S->ifinfo;
	my $ifTable = $NI->{ifTable};
	my $V = $S->view;
	
	# anything to do?
	return (0,undef) if ( $NI->{system}{nodeModel} !~ "AlcatelASAM" 
												or !getbool($NI->{system}->{collect}));
	
	my $asamVersion41 = qr/OSWPAA41|L6GPAA41|OSWPAA37|L6GPAA37|OSWPRA41/;
	my $asamVersion42 = qr/OSWPAA42|L6GPAA42|OSWPAA46/;
	my $asamVersion43 = qr/OSWPRA43|OSWPAN43/;

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
	
	my $asamSoftwareVersion = $NI->{system}{asamSoftwareVersion1};
	if ( $NI->{system}{asamActiveSoftware2} eq "active" ) 
	{
		$asamSoftwareVersion = $NI->{system}{asamSoftwareVersion2};
	}
	my @verParts = split("/",$asamSoftwareVersion);
	$asamSoftwareVersion = $verParts[$#verParts];
			
	my $version;
	if( $asamSoftwareVersion =~ /$asamVersion41/ ) {
		$version = 4.1;		
	}
	#" release 4.2  ( ISAM FD y  ISAM-V) "
	elsif( $asamSoftwareVersion =~ /$asamVersion42/ )
	{
		$version = 4.2;
	}
	elsif( $asamSoftwareVersion =~ /$asamVersion43/ )
	{
		$version = 4.3;
	}
	else {
		logMsg("ERROR: Unknown ASAM Version $node asamSoftwareVersion=$asamSoftwareVersion");
	}

	$NI->{system}{asamVersion} = $version;
	$V->{system}{"asamVersion_value"} = $version;
	$V->{system}{"asamVersion_title"} = "ASAM Version";
	
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
	#return (2, "Could not retrieve SNMP vars from node $node: ".$snmp->error)
	#		if (!$snmp->testsession);
	
	info("Working on $node Customer_ID");
	foreach my $ifIndex (oid_lex_sort(keys %{$NI->{Customer_ID}})) {
		my $entry = $NI->{Customer_ID}{$ifIndex};

		if ( defined $NI->{ifTable}{$ifIndex} ) {
			$entry->{ifDescr} = $NI->{ifTable}{$ifIndex}{ifDescr};
			$entry->{ifAdminStatus} = $NI->{ifTable}{$ifIndex}{ifAdminStatus};
			$entry->{ifOperStatus} = $NI->{ifTable}{$ifIndex}{ifOperStatus};
			$entry->{ifType} = $NI->{ifTable}{$ifIndex}{ifType};
			$changesweremade = 1;
		}
	}

	if ( $session ) {
		# Using the data we collect from the atmVcl we will fill in the details of the DSLAM Port.
		info("Working on $node atmVcl");
	
		my $offset = 12288;
		if ( $version eq "4.2" )  {
			$offset = 6291456;
		}
		
		my @atmVclVars = qw(
			asamIfExtCustomerId
			xdslLineServiceProfileNbr
			xdslLineSpectrumProfileNbr
		);
		
		# the ordered list of SNMP variables I want.
		my @dslamVarList = qw(
			asamIfExtCustomerId
			xdslLineServiceProfileNbr
			xdslLineSpectrumProfileNbr
			xdslLineOutputPowerDownstream
			xdslLineLoopAttenuationUpstream
			xdslFarEndLineOutputPowerUpstream
			xdslFarEndLineLoopAttenuationDownstream
			xdslXturInvSystemSerialNumber
			xdslLinkUpActualBitrateUpstream
			xdslLinkUpActualBitrateDownstream
			xdslLinkUpActualNoiseMarginUpstream
			xdslLinkUpActualNoiseMarginDownstream
			xdslLinkUpAttenuationUpstream
			xdslLinkUpAttenuationDownstream
			xdslLinkUpAttainableBitrateUpstream
			xdslLinkUpAttainableBitrateDownstream
			xdslLinkUpMaxBitrateUpstream
			xdslLinkUpMaxBitrateDownstream
		);
			
		foreach my $key (oid_lex_sort(keys %{$NI->{atmVcl}}))
		{
			my $entry = $NI->{atmVcl}->{$key};
	                    
			if ( my @parts = split(/\./,$entry->{index}) ) 
			{
				my $ifIndex = shift(@parts);
				my $atmVclVpi = shift(@parts);
				my $atmVclVci = shift(@parts);
	
				# the crazy magic of ASAM
				my $offsetIndex = $ifIndex - $offset;
		
				# the set of oids with dynamic index I want.
				my %atmOidSet = (
	 				asamIfExtCustomerId => 											"1.3.6.1.4.1.637.61.1.6.5.1.1.$offsetIndex",
					xdslLineServiceProfileNbr => 								"1.3.6.1.4.1.637.61.1.39.3.7.1.1.$offsetIndex",
					xdslLineSpectrumProfileNbr => 							"1.3.6.1.4.1.637.61.1.39.3.7.1.2.$offsetIndex",					
				);
	
				# build an array combining the atmVclVars and atmOidSet into a single array
				my @oids = map {$atmOidSet{$_}} @atmVclVars;
				#print Dumper \@oids;
	
				# get the snmp data from the thing
				my $snmpdata = $session->get_request(
					-varbindlist => \@oids
				);
								
				if ( $session->error() ) {
					dbg("ERROR with SNMP on $node: ". $session->error());
				}

				# save the data for the atmVcl					
				$entry->{ifIndex} = $ifIndex;
				$entry->{atmVclVpi} = $atmVclVpi;
				$entry->{atmVclVci} = $atmVclVci;
				$entry->{asamIfExtCustomerId} = "N/A";
				$entry->{xdslLineServiceProfileNbr} = "N/A";
				$entry->{xdslLineSpectrumProfileNbr} = "N/A";
				
				if ( $snmpdata ) {

					foreach my $var (@atmVclVars) {
						my $dataKey = $atmOidSet{$var};
						if ( $snmpdata->{$dataKey} ne "" and $snmpdata->{$dataKey} !~ /SNMP ERROR/ ) {
							$entry->{$var} = $snmpdata->{$dataKey};
						}
						else {
							dbg("ERROR with SNMP on $node var=$var: ".$snmpdata->{$dataKey}) if ($snmpdata->{$dataKey} =~ /SNMP ERROR/);
							$entry->{$var} = "N/A";
						}
					}
							
					dbg("atmVcl SNMP Results: ifIndex=$ifIndex atmVclVpi=$atmVclVpi atmVclVci=$atmVclVci asamIfExtCustomerId=$entry->{asamIfExtCustomerId}");
		
					if ( defined $IF->{$ifIndex}{ifDescr} ) {
						$entry->{ifDescr} = $IF->{$ifIndex}{ifDescr};
						$entry->{ifDescr_url} = "/cgi-nmis8/network.pl?conf=$C->{conf}&act=network_interface_view&intf=$ifIndex&node=$node";
						$entry->{ifDescr_id} = "node_view_$node";
					}
					else {
						$entry->{ifDescr} = getIfDescr(prefix => "ATM", version => $version, ifIndex => $ifIndex, asamModel => $asamModel);
					}

					$changesweremade = 1;
				}
			}
		}

		#"xdslLinkUp"																	"1.3.6.1.4.1.637.61.1.39.12"
		#"xdslLinkUpTable"														"1.3.6.1.4.1.637.61.1.39.12.1"
		#"xdslLinkUpEntry"														"1.3.6.1.4.1.637.61.1.39.12.1.1"
		#"xdslLinkUpTimestampDown"										"1.3.6.1.4.1.637.61.1.39.12.1.1.1"
		#"xdslLinkUpTimestampUp"											"1.3.6.1.4.1.637.61.1.39.12.1.1.2"
		#"xdslLinkUpThresholdBitrateUpstream"					"1.3.6.1.4.1.637.61.1.39.12.1.1.13"
		#"xdslLinkUpThresholdBitrateDownstream"				"1.3.6.1.4.1.637.61.1.39.12.1.1.14"
		#"xdslLinkUpMaxDelayUpstream"									"1.3.6.1.4.1.637.61.1.39.12.1.1.15"
		#"xdslLinkUpMaxDelayDownstream"								"1.3.6.1.4.1.637.61.1.39.12.1.1.16"
		#"xdslLinkUpTargetNoiseMarginUpstream"				"1.3.6.1.4.1.637.61.1.39.12.1.1.17"
		#"xdslLinkUpTargetNoiseMarginDownstream"			"1.3.6.1.4.1.637.61.1.39.12.1.1.18"
		#"xdslLinkUpTimestamp"												"1.3.6.1.4.1.637.61.1.39.12.2"
		#"xdslLinkUpLineBitmapTable"									"1.3.6.1.4.1.637.61.1.39.12.3"
		#"xdslLinkUpLineBitmapEntry"									"1.3.6.1.4.1.637.61.1.39.12.3.1"
		#"xdslLinkUpLineBitmap"												"1.3.6.1.4.1.637.61.1.39.12.3.1.1"    
	
		#"asamIfExtCustomerId"												"1.3.6.1.4.1.637.61.1.6.5.1.1"
		#"xdslLineServiceProfileNbr"									"1.3.6.1.4.1.637.61.1.39.3.7.1.1"
		
		#"xdslLineOutputPowerDownstream"							"1.3.6.1.4.1.637.61.1.39.3.8.1.1.3"
		#"xdslLineLoopAttenuationUpstream"						"1.3.6.1.4.1.637.61.1.39.3.8.1.1.5"
		#"xdslFarEndLineOutputPowerUpstream"					"1.3.6.1.4.1.637.61.1.39.4.1.1.1.3"
		#"xdslFarEndLineLoopAttenuationDownstream"		"1.3.6.1.4.1.637.61.1.39.4.1.1.1.5"
	
		#"xdslXturInvSystemSerialNumber"							"1.3.6.1.4.1.637.61.1.39.8.1.1.2"
	
		#"xdslLinkUpActualBitrateUpstream"						"1.3.6.1.4.1.637.61.1.39.12.1.1.3"
		#"xdslLinkUpActualBitrateDownstream"					"1.3.6.1.4.1.637.61.1.39.12.1.1.4"
		#"xdslLinkUpActualNoiseMarginUpstream"				"1.3.6.1.4.1.637.61.1.39.12.1.1.5"
		#"xdslLinkUpActualNoiseMarginDownstream"			"1.3.6.1.4.1.637.61.1.39.12.1.1.6"
		#"xdslLinkUpAttenuationUpstream"							"1.3.6.1.4.1.637.61.1.39.12.1.1.7"
		#"xdslLinkUpAttenuationDownstream"						"1.3.6.1.4.1.637.61.1.39.12.1.1.8"
		#"xdslLinkUpAttainableBitrateUpstream"				"1.3.6.1.4.1.637.61.1.39.12.1.1.9"
		#"xdslLinkUpAttainableBitrateDownstream"			"1.3.6.1.4.1.637.61.1.39.12.1.1.10"
		#"xdslLinkUpMaxBitrateUpstream"								"1.3.6.1.4.1.637.61.1.39.12.1.1.11"
		#"xdslLinkUpMaxBitrateDownstream"							"1.3.6.1.4.1.637.61.1.39.12.1.1.12"
	
		info("Working on $node ifTable for DSLAM Port Data");
		
		for my $ifIndex (oid_lex_sort(keys %{$NI->{ifTable}})) {
			my $entry = $NI->{ifTable}->{$ifIndex};
			my $dslamPort = $NI->{DSLAM_Ports}->{$ifIndex};
			if ( $entry->{ifDescr} eq "XDSL Line" ) {					
				# the crazy magic of ASAM
				my $atmOffsetIndex = $ifIndex + $offset;
		
				# the set of oids with dynamic index I want.
				my %dslamOidSet = (
	 				asamIfExtCustomerId => 											"1.3.6.1.4.1.637.61.1.6.5.1.1.$ifIndex",
					xdslLineServiceProfileNbr => 								"1.3.6.1.4.1.637.61.1.39.3.7.1.1.$ifIndex",
					xdslLineSpectrumProfileNbr => 							"1.3.6.1.4.1.637.61.1.39.3.7.1.2.$ifIndex",					
					xdslLineOutputPowerDownstream =>						"1.3.6.1.4.1.637.61.1.39.3.8.1.1.3.$ifIndex",
					xdslLineLoopAttenuationUpstream =>					"1.3.6.1.4.1.637.61.1.39.3.8.1.1.5.$ifIndex",
					xdslFarEndLineOutputPowerUpstream =>				"1.3.6.1.4.1.637.61.1.39.4.1.1.1.3.$ifIndex",
					xdslFarEndLineLoopAttenuationDownstream =>	"1.3.6.1.4.1.637.61.1.39.4.1.1.1.5.$ifIndex",
					xdslXturInvSystemSerialNumber =>						"1.3.6.1.4.1.637.61.1.39.8.1.1.2.$ifIndex",
					xdslLinkUpActualBitrateUpstream =>					"1.3.6.1.4.1.637.61.1.39.12.1.1.3.$ifIndex",
					xdslLinkUpActualBitrateDownstream =>				"1.3.6.1.4.1.637.61.1.39.12.1.1.4.$ifIndex",
					xdslLinkUpActualNoiseMarginUpstream =>			"1.3.6.1.4.1.637.61.1.39.12.1.1.5.$ifIndex",
					xdslLinkUpActualNoiseMarginDownstream =>		"1.3.6.1.4.1.637.61.1.39.12.1.1.6.$ifIndex",
					xdslLinkUpAttenuationUpstream =>						"1.3.6.1.4.1.637.61.1.39.12.1.1.7.$ifIndex",
					xdslLinkUpAttenuationDownstream =>					"1.3.6.1.4.1.637.61.1.39.12.1.1.8.$ifIndex",
					xdslLinkUpAttainableBitrateUpstream =>			"1.3.6.1.4.1.637.61.1.39.12.1.1.9.$ifIndex",
					xdslLinkUpAttainableBitrateDownstream =>		"1.3.6.1.4.1.637.61.1.39.12.1.1.10.$ifIndex",
					xdslLinkUpMaxBitrateUpstream =>							"1.3.6.1.4.1.637.61.1.39.12.1.1.11.$ifIndex",
					xdslLinkUpMaxBitrateDownstream =>						"1.3.6.1.4.1.637.61.1.39.12.1.1.12.$ifIndex",
				);
	
				# build an array combining the dslamVarList and dslamOidSet into a single array
				my @oids = map {$dslamOidSet{$_}} @dslamVarList;
				#print Dumper \@oids;
	
				# get the snmp data from the thing
				my $snmpdata = $session->get_request(
					-varbindlist => \@oids
				);
								
				if ( $session->error() ) {
					dbg("ERROR with SNMP on $node: ". $session->error());
				}

				# save the data for the dslamPort					
				$dslamPort->{ifIndex} = $ifIndex;
				$dslamPort->{atmIfIndex} = $atmOffsetIndex;
				
				if ( $snmpdata ) {
															
					# now get each of the required vars snmp data into the entry for saving.
					foreach my $var (@dslamVarList) {
						my $dataKey = $dslamOidSet{$var};
						if ( $snmpdata->{$dataKey} ne "" and $snmpdata->{$dataKey} !~ /SNMP ERROR/ ) {
							$dslamPort->{$var} = $snmpdata->{$dataKey};
						}
						else {
							dbg("ERROR with SNMP on $node var=$var: ".$snmpdata->{$dataKey}) if ($snmpdata->{$dataKey} =~ /SNMP ERROR/);
							$dslamPort->{$var} = "N/A";
						}
					}

					$dslamPort->{ifDescr} = getIfDescr(prefix => "ATM", version => $version, ifIndex => $atmOffsetIndex, asamModel => $asamModel);
		
					dbg("DSLAM SNMP Results: ifIndex=$ifIndex ifDescr=$dslamPort->{ifDescr} asamIfExtCustomerId=$dslamPort->{asamIfExtCustomerId}");
								
					if ( $entry->{ifLastChange} ) { 
						$dslamPort->{ifLastChange} = convUpTime(int($entry->{ifLastChange}/100));
					}
					else {
						$dslamPort->{ifLastChange} = '0:00:00',
					}
					$dslamPort->{ifOperStatus} = $entry->{ifOperStatus} ? $entry->{ifOperStatus} : "N/A";
					$dslamPort->{ifAdminStatus} = $entry->{ifAdminStatus} ? $entry->{ifAdminStatus} : "N/A";


					# get the Service Profile Name based on the xdslLineServiceProfileNbr
					if ( defined $NI->{xdslLineServiceProfile} and defined $dslamPort->{xdslLineServiceProfileNbr} ) {
						my $profileNumber = $dslamPort->{xdslLineServiceProfileNbr};
						$dslamPort->{xdslLineServiceProfileName}  = $NI->{xdslLineServiceProfile}{$profileNumber}{xdslLineServiceProfileName} ? $NI->{xdslLineServiceProfile}{$profileNumber}{xdslLineServiceProfileName} : "N/A";						
					}

					$changesweremade = 1;
				}
			}
			else {
				delete $NI->{DSLAM_Ports}->{$ifIndex};
			}
		}
	}
	else {
		dbg("ERROR some session problem with SNMP on $node");
	}

	info("Working on $node ifStack");

	for my $key (oid_lex_sort(keys %{$NI->{ifStack}}))
	{
		my $entry = $NI->{ifStack}->{$key};
          
		if ( my @parts = split(/\./,$entry->{index}) ) {
			my $ifStackHigherLayer = shift(@parts);
			my $ifStackLowerLayer = shift(@parts);
			
			$entry->{ifStackHigherLayer} = $ifStackHigherLayer;
			$entry->{ifStackLowerLayer} = $ifStackLowerLayer;

			if ( defined $IF->{$ifStackHigherLayer}{ifDescr} ) {
				$entry->{ifDescrHigherLayer} = $IF->{$ifStackHigherLayer}{ifDescr};
				$entry->{ifDescrHigherLayer_url} = "/cgi-nmis8/network.pl?conf=$C->{conf}&act=network_interface_view&intf=$ifStackHigherLayer&node=$node";
				$entry->{ifDescrHigherLayer_id} = "node_view_$node";
			}

			if ( defined $IF->{$ifStackLowerLayer}{ifDescr} ) {
				$entry->{ifDescrLowerLayer} = $IF->{$ifStackLowerLayer}{ifDescr};
				$entry->{ifDescrLowerLayer_url} = "/cgi-nmis8/network.pl?conf=$C->{conf}&act=network_interface_view&intf=$ifStackLowerLayer&node=$node";
				$entry->{ifDescrLowerLayer_id} = "node_view_$node";
			}

			dbg("WHAT: ifDescr=$IF->{$ifStackHigherLayer}{ifDescr} ifStackHigherLayer=$entry->{ifStackHigherLayer} ifStackLowerLayer=$entry->{ifStackLowerLayer} ");

			$changesweremade = 1;
		}
	}

	return ($changesweremade,undef); # report if we changed anything
}

sub getIfDescr {
	my %args = @_;
	
	my $oid_value 		= $args{ifIndex};	
	my $prefix 		= $args{prefix};	
	my $asamModel 		= $args{asamModel};	
	
	if ( $args{version} eq "4.1" or $args{version} eq "4.3" ) {
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
	
	if ( $asamModel =~ /7302/ and $slot >= 9 ) {
		$slot = $slot + 1;
	}
	elsif ( $asamModel =~ /ARAM-D/ ) {
		$slot = $slot + 3
	}
	elsif ( $asamModel =~ /ARAM-E/ and $slot < 9 ) {
		$slot = $slot + 1
	}
	elsif ( $asamModel =~ /ARAM-E/ and $slot >= 9 ) {
		$slot = $slot + 3
	}
	elsif ( $asamModel =~ /7330-FD/ ) {
		$slot = $slot + 3
	}
	return $slot;
} 

1;
