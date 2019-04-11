# a small update plugin for discovering interfaces on FutureSoftware devices
# which requires custom snmp accesses
package CiscoMerakiCloud;
our $VERSION = "1.0.0";

use strict;

use func;												# for loading extra tables
use NMIS;												# iftypestable
use rrdfunc;										# for updateRRD
use JSON::XS;
use LWP::UserAgent;
use File::Path qw(make_path);
use Data::Dumper;


use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

use Exporter;

@ISA = qw(Exporter);

@EXPORT = qw(
	getMerakiData
);

my $debug = 1;

sub collect_plugin
{
	my (%args) = @_;
	my ($node, $S, $C) = @args{qw(node sys config)};

	my $NI = $S->ndinfo;
	my $V = $S->view;
	
	logMsg("Wprking on $node $NI->{system}{nodeModel}");

	# this plugin deals only with CiscoMerakiCloud
	return (0,undef) if ( $NI->{system}{nodeModel} ne "CiscoMerakiCloud" );

	my $merakiData = getMerakiData(name => $node);
	if ( defined $merakiData->{error} ) {
		logMsg("ERROR with $node: $merakiData->{error}");
	}
	logMsg("$node: status=$merakiData->{status} perfScore=$merakiData->{perfScore} avgLatency=$merakiData->{avgLatency} avgLossPercent=$merakiData->{avgLossPercent} maxLossPercent=$merakiData->{maxLossPercent}");

	my $rrddata = {
		'perfScore' => { "option" => "GAUGE,0:U", "value" => $merakiData->{perfScore}},
		'avgLatency' => { "option" => "GAUGE,0:U", "value" => $merakiData->{avgLatency}},
		'avgLossPercent' => { "option" => "GAUGE,0:U", "value" => $merakiData->{avgLossPercent}},
		'maxLossPercent' => { "option" => "GAUGE,0:U", "value" => $merakiData->{maxLossPercent}},	
	};
	
	# updateRRD subrutine is called from rrdfunc.pm module
	my $updatedrrdfileref = updateRRD(data=>$rrddata, sys=>$S, type=>"meraki", index => undef);

	# Store the results for the GUI to display
	$V->{system}{"merakistatus_value"} = $merakiData->{status};
	$V->{system}{"merakistatus_title"} = 'Status';
	$V->{system}{"merakistatus_color"} = '#00FF00';
	$V->{system}{"merakistatus_color"} = '#FF0000' if $merakiData->{status} eq "offline";

	$V->{system}{"perfScore_value"} = $merakiData->{perfScore};
	$V->{system}{"perfScore_title"} = 'Performance Score';

	$V->{system}{"loss_value"} = $merakiData->{avgLossPercent};
	$V->{system}{"loss_title"} = 'AVG Loss Percent';

	$V->{system}{"serial_value"} = $merakiData->{serial};
	$V->{system}{"serial_title"} = 'Serial';

	$V->{system}{"lanIp_value"} = $merakiData->{lanIp};
	$V->{system}{"lanIp_title"} = 'lanIp';

	$V->{system}{"wan1Ip_value"} = $merakiData->{wan1Ip};
	$V->{system}{"wan1Ip_title"} = 'wan1Ip';

	$V->{system}{"publicIp_value"} = $merakiData->{publicIp};
	$V->{system}{"publicIp_title"} = 'publicIp';

	$V->{system}{"networkId_value"} = $merakiData->{networkId};
	$V->{system}{"networkId_title"} = 'networkId';

	$V->{system}{"mac_value"} = $merakiData->{mac};
	$V->{system}{"mac_title"} = 'mac';

	return (1,undef);							# happy, changes were made so save view and nodes files
}

sub getMerakiData {
	my %args = @_;
	my $deviceName = $args{name};
	
	my $merakiConfig = loadJsonFile("/usr/local/nmis8/conf/CiscoMerakiCloud.json");

	my $apiKey = $merakiConfig->{apiKey};
	my $apiBase = $merakiConfig->{apiBase};
	my $databaseDir = $merakiConfig->{databaseDir};
	my $historySeconds = $merakiConfig->{historySeconds};
	
	make_path("$databaseDir/devices");

	my $merakiData;
	my $merakiStateFile = "$databaseDir/meraki.json";
	my $merakiState;
	if ( -f $merakiStateFile ) {
		$merakiState = loadJsonFile($merakiStateFile);
	}
	
	# create the user agent all the queries will use.
	my $ua = getApiAgent();
	
	# if we have not got the orgId, get it.
	if ( not defined $merakiState->{orgId} ) {
		my $data = getApiData(url => "$apiBase/organizations", ua => $ua, apiKey => $apiKey, debug => 0);

		print "Saving organizations data\n" if $debug;
		saveJsonFile("$databaseDir/organizations.json",$data);
		
		my $count = 0;	
		foreach my $org (@$data) {
			$merakiState->{orgId} = $org->{'id'};
		}
	}
	print "orgId = $merakiState->{orgId}\n" if $debug;
	
	# have we got device status data recently?
	if ( not defined $merakiState->{lastDeviceStatuses}
		or time() - $merakiState->{lastDeviceStatuses} > 300 
	) {	
		print "deviceStatuses is old, refreshing the cache\n" if $debug;
		my $data = getApiData(url => "$apiBase/organizations/$merakiState->{orgId}/deviceStatuses", ua => $ua, apiKey => $apiKey, debug => 0);
		my $count = 0;	
		foreach my $device (@$data) {
			++$count;
			saveJsonFile("$databaseDir/devices/$device->{name}.json",$device);	
		}
		$merakiState->{lastDeviceStatuses} = time;
		print "there were $count devices\n" if $debug;
	}

	# get the lossAndLatencyHistory for one deviceName
	# first load the deviceStatus for this device.
	my $deviceFile = "$databaseDir/devices/$deviceName.json";
	if ( -r $deviceFile ) {
		my $deviceData = loadJsonFile("$databaseDir/devices/$deviceName.json");
		# get all the data from the cache.
		$merakiData = $deviceData;

		#"status":"offline"}
		
		if ( $deviceData->{status} ne "offline" ) {
			print Dumper $deviceData if $debug > 1;
			
			# build a query to get the lossAndLatencyHistory data.
			my $networkId = $deviceData->{networkId};
			my $serial = $deviceData->{serial};
			my $apiCall = "$apiBase/organizations/$merakiState->{orgId}/networks/$networkId/devices/$serial/lossAndLatencyHistory?ip=8.8.8.8&timespan=$historySeconds";
			
			print "about to run $apiCall\n" if $debug > 1;
			my $lossAndLatencyHistory = getApiData(url => $apiCall, ua => $ua, apiKey => $apiKey, debug => 0);
		
			my $apiCall = "$apiBase/organizations/$merakiState->{orgId}/networks/$networkId/devices/$serial/performance";
			print "about to run $apiCall\n" if $debug > 1;
			my $performance = getApiData(url => $apiCall, ua => $ua, apiKey => $apiKey, debug => 0);

			my $apiCall = "$apiBase/organizations/$merakiState->{orgId}/networks/$networkId/devices/$serial";
			print "about to run $apiCall\n" if $debug > 1;
			my $device = getApiData(url => $apiCall, ua => $ua, apiKey => $apiKey, debug => 0);
			foreach my $key (keys %$device) {
				$merakiData->{$key} = $device->{$key} if not defined $merakiData->{$key};
			}
		
			print Dumper $lossAndLatencyHistory if $debug > 1;
		
			my $totalLatency = 0;
			my $totalLoss = 0;
			my $count = 0;
			$merakiData->{maxLossPercent} = 0;
			# latency will be the average latency for the sample
			# loss will be the max loss for the sample
			foreach my $record (@$lossAndLatencyHistory) {
				++$count;
				$totalLatency += $record->{latencyMs};
				$totalLoss += $record->{lossPercent};
				if ( $record->{lossPercent} > $merakiData->{maxLossPercent} ) {
					$merakiData->{maxLossPercent} = $record->{lossPercent};
				}
			}
		
			$merakiData->{avgLatency} = sprintf("%.2f", $totalLatency / $count);
			$merakiData->{avgLossPercent} = sprintf("%.2f", $totalLoss / $count);
			$merakiData->{perfScore} = $performance->{perfScore};
		}
		else {
			$merakiData->{error} = "Device Status not online: $deviceData->{status}";
			$merakiData->{maxLossPercent} = "U";
			$merakiData->{avgLatency} = "U";
			$merakiData->{avgLossPercent} = "U";
			$merakiData->{perfScore} = "U";
		}			
	}
	else {
		$merakiData->{error} = "No Device Status file found: $deviceFile";
	}
	
	# save the meraki state info for caching
	saveJsonFile("$merakiStateFile",$merakiState);
	
	# send back the results.
	return $merakiData;
}

sub getApiAgent {
	my $ua = LWP::UserAgent->new();
	$ua->agent("$0/0.1 " . $ua->agent);
	$ua->agent("Mozilla/8.0"); # pretend we are very capable browser
	return $ua;
}	

sub getApiData {
	my %args = @_;

	my $ua = $args{ua};
	my $apiKey = $args{apiKey};
	my $url = $args{url};
	my $debugCall = $args{debug};
	
	my $data;

	my $req = HTTP::Request->new(GET => $url);
	$req->header(
		'X-Cisco-Meraki-API-Key' => $apiKey,
		'Content-Type' => 'application/json',
		'Accept' => '*/*'
	);
	      
	# send request
	print Dumper $req if $debugCall;
	my $res = $ua->request($req);
	
	print Dumper $res if $debugCall;
	if ($res->is_success) {
		$data = decode_json($res->decoded_content);
	}
	else {
		print "ERROR: " . $res->status_line . "\n";
	}	
	return $data;
}


sub saveJsonFile {
	my $file = shift;
	my $data = shift;
	my $pretty = shift || 0;
	my $error;

	open(FILE, ">$file") or $error = "ERROR with file $file: $!";
	if ( not $error ) {
		# json files must be utf-8 encoded
		print FILE JSON::XS->new->pretty($pretty)->utf8(1)->encode($data);
		close(FILE);
	}
	chmod (0660, $file); 
	
	return $error;
}

sub loadJsonFile {
	my $file = shift;
	my $data = undef;
	my $error;

	open(FILE, $file) or $error = "ERROR with file $file: $!";
	if ( not $error ) {
		local $/ = undef;
		my $JSON = <FILE>;
	
		# fallback between utf8 (correct) or latin1 (incorrect but not totally uncommon)
		$data = eval { decode_json($JSON); };
		$data = eval { JSON::XS->new->latin1(1)->decode($JSON); } if ($@);
		if ( $@ ) {
			print STDERR "ERROR convert $file to hash table (neither utf-8 nor latin-1), $@\n";
		}
		close(FILE);
	}

	return ($error,$data);
}


1;
