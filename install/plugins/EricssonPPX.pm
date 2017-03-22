# a small update plugin for discovering interfaces on FutureSoftware devices
# which requires custom snmp accesses
package EricssonPPX;
our $VERSION = "1.0.1";

use strict;

use NMIS;												# lnt
use func;												# for the conf table extras
use rrdfunc;										# for updateRRD
# Customer not running latest code, can not use this
#use snmp 1.1.0;									# for snmp-related access
use Net::SNMP qw(oid_lex_sort);
use Data::Dumper;

sub collect_plugin
{
	my (%args) = @_;
	my ($node, $S, $C) = @args{qw(node sys config)};

	my $NC = $S->ndcfg;
	my $NI = $S->ndinfo;
	
	# this plugin deals only with things containing the right data ppxCardMEM
	if ( not defined $NI->{ppxCardMEM} ) {
		info("Prerequisite ppxCardMEM not found in $node");
		return (0,undef) 
	}

	info("Working on $node ppxCardMEM");

	# Get the SNMP Session going.
	#my $snmp = snmp->new(name => $node);

	my ($session, $error) = Net::SNMP->session(
                           -hostname      => $NC->{node}{host},
                           -port          => $NC->{node}{port},
                           -version       => $NC->{node}{version},
                           -community     => $NC->{node}{community},   # v1/v2c
                        );	
	
	#return (2,"Could not open SNMP session to node $node: ".$snmp->error)
	#		if (!$snmp->open(config => $NC->{node}, host_addr => $NI->{system}->{host_addr}));
	#return (2, "Could not retrieve SNMP vars from node $node: ".$snmp->error)
	#		if (!$snmp->testsession);
	
	my $changesweremade = 0;

	if ( $session ) {
		#Nortel-MsCarrier-MscPassport-BaseShelfMIB::mscShelfCardMemoryCapacityValue.present.0.fastRam = Gauge32: 0
		#Nortel-MsCarrier-MscPassport-BaseShelfMIB::mscShelfCardMemoryCapacityValue.present.0.normalRam = Gauge32: 65536
		#Nortel-MsCarrier-MscPassport-BaseShelfMIB::mscShelfCardMemoryCapacityValue.present.0.sharedRam = Gauge32: 2048
		#Nortel-MsCarrier-MscPassport-BaseShelfMIB::mscShelfCardMemoryUsageValue.present.0.fastRam = Gauge32: 0
		#Nortel-MsCarrier-MscPassport-BaseShelfMIB::mscShelfCardMemoryUsageValue.present.0.normalRam = Gauge32: 37316
		#Nortel-MsCarrier-MscPassport-BaseShelfMIB::mscShelfCardMemoryUsageValue.present.0.sharedRam = Gauge32: 2048  
				
		#"mscShelfCardMemoryCapacityValue"			"1.3.6.1.4.1.562.36.2.1.13.2.244.1.2"
		#"mscShelfCardMemoryUsageValue"			"1.3.6.1.4.1.562.36.2.1.13.2.245.1.2"
		#"mscShelfCardMemoryUsageAvgValue"			"1.3.6.1.4.1.562.36.2.1.13.2.276.1.2"
		#"mscShelfCardMemoryUsageAvgMinValue"			"1.3.6.1.4.1.562.36.2.1.13.2.277.1.2"
		#"mscShelfCardMemoryUsageAvgMaxValue"			"1.3.6.1.4.1.562.36.2.1.13.2.278.1.2"
	
		my $memCapacityOid = ".1.3.6.1.4.1.562.36.2.1.13.2.244.1.2";
		my $memUsageOid = ".1.3.6.1.4.1.562.36.2.1.13.2.245.1.2";
		my $memUsageAvgOid = ".1.3.6.1.4.1.562.36.2.1.13.2.276.1.2";
		my $memUsageMinOid = ".1.3.6.1.4.1.562.36.2.1.13.2.277.1.2";
		my $memUsageMaxOid = ".1.3.6.1.4.1.562.36.2.1.13.2.278.1.2";
	
		my $fastRam = "0";
		my $normalRam = "1";
		my $sharedRam = "2";
			
		# based on each of the cards we know about from CPU, we are going to look for each of the memory value.
		foreach my $card (sort keys %{$NI->{ppxCardMEM}}) {
			info("ppxCardMEM card $card");
			
			my $snmpdata = $session->get_request(
				-varbindlist => [
					"$memCapacityOid.$card.$fastRam",
					"$memCapacityOid.$card.$normalRam",
					"$memCapacityOid.$card.$sharedRam",
					"$memUsageOid.$card.$fastRam",
					"$memUsageOid.$card.$normalRam",
					"$memUsageOid.$card.$sharedRam",
					
					"$memUsageAvgOid.$card.$fastRam",
					"$memUsageAvgOid.$card.$normalRam",
					"$memUsageAvgOid.$card.$sharedRam",
					"$memUsageMinOid.$card.$fastRam",
					"$memUsageMinOid.$card.$normalRam",
					"$memUsageMinOid.$card.$sharedRam",
					"$memUsageMaxOid.$card.$fastRam",
					"$memUsageMaxOid.$card.$normalRam",
					"$memUsageMaxOid.$card.$sharedRam",
				],
			);
	                       
			if ( $snmpdata ) {
				#print Dumper $snmpdata;
				my $data = { 
					'memCapFastRam' => { "option" => "GAUGE,0:U", "value" => $snmpdata->{"$memCapacityOid.$card.$fastRam"} },
					'memCapNormalRam' => { "option" => "GAUGE,0:U", "value" => $snmpdata->{"$memCapacityOid.$card.$normalRam"} },					
					'memCapSharedRam' => { "option" => "GAUGE,0:U", "value" => $snmpdata->{"$memCapacityOid.$card.$sharedRam"} },
	
					'memUsageFastRam' => { "option" => "GAUGE,0:U", "value" => $snmpdata->{"$memUsageOid.$card.$fastRam"} },
					'memUsageNormalRam' => { "option" => "GAUGE,0:U", "value" => $snmpdata->{"$memUsageOid.$card.$normalRam"} },					
					'memUsageSharedRam' => { "option" => "GAUGE,0:U", "value" => $snmpdata->{"$memUsageOid.$card.$sharedRam"} },

					'memAvgFastRam' => { "option" => "GAUGE,0:U", "value" => $snmpdata->{"$memUsageAvgOid.$card.$fastRam"} },
					'memAvgNormalRam' => { "option" => "GAUGE,0:U", "value" => $snmpdata->{"$memUsageAvgOid.$card.$normalRam"} },					
					'memAvgSharedRam' => { "option" => "GAUGE,0:U", "value" => $snmpdata->{"$memUsageAvgOid.$card.$sharedRam"} },

					'memMinFastRam' => { "option" => "GAUGE,0:U", "value" => $snmpdata->{"$memUsageMinOid.$card.$fastRam"} },
					'memMinNormalRam' => { "option" => "GAUGE,0:U", "value" => $snmpdata->{"$memUsageMinOid.$card.$normalRam"} },					
					'memMinSharedRam' => { "option" => "GAUGE,0:U", "value" => $snmpdata->{"$memUsageMinOid.$card.$sharedRam"} },

					'memMaxFastRam' => { "option" => "GAUGE,0:U", "value" => $snmpdata->{"$memUsageMaxOid.$card.$fastRam"} },
					'memMaxNormalRam' => { "option" => "GAUGE,0:U", "value" => $snmpdata->{"$memUsageMaxOid.$card.$normalRam"} },					
					'memMaxSharedRam' => { "option" => "GAUGE,0:U", "value" => $snmpdata->{"$memUsageMaxOid.$card.$sharedRam"} },
				};
				
				# save the results to the node file.
				$NI->{ppxCardMEM}{$card}{'memCapFastRam'} = $snmpdata->{"$memCapacityOid.$card.$fastRam"};
				$NI->{ppxCardMEM}{$card}{'memCapNormalRam'} = $snmpdata->{"$memCapacityOid.$card.$normalRam"};
				$NI->{ppxCardMEM}{$card}{'memCapSharedRam'} = $snmpdata->{"$memCapacityOid.$card.$sharedRam"};

				if ( $snmpdata->{"$memCapacityOid.$card.$fastRam"} == 0
					and $snmpdata->{"$memCapacityOid.$card.$normalRam"} == 0
					and $snmpdata->{"$memCapacityOid.$card.$sharedRam"} == 0
				) {
					info ("Card has no memory information, removing from display");
					delete $NI->{ppxCardMEM}{$card};
				}
				
				my $filename = updateRRD(data=>$data, sys=>$S, type=>"ppxCardMEM", index => $card);
				if (!$filename)
				{
					return (2, "UpdateRRD failed!");
				}		
			}
			else {
				info ("Problem with SNMP session to $node: ".$session->error());
	
			}
		}

		$changesweremade = 1;
		return ($changesweremade,undef); # report if we changed anything

	}
	else {
		info ("Could not open SNMP session to node $node: ".$error);
		return (2, "Could not open SNMP session to node $node: ".$error)
	}

}
