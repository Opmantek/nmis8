# a small update plugin for discovering interfaces on FutureSoftware devices
# which requires custom snmp accesses
package CiscoViptelaCloud;
our $VERSION = "1.0.0";

use strict;

use func;												# for loading extra tables
use NMIS;												# iftypestable
use rrdfunc;										# for updateRRD
use JSON::XS;
use LWP::UserAgent;
use File::Path qw(make_path);
use Data::Dumper;
use WWW::Mechanize;
use IO::Socket::SSL qw( SSL_VERIFY_NONE );
use Date::Format;

use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

use Exporter;

@ISA = qw(Exporter);

@EXPORT = qw(
	getViptelaData
);

my $debug = 0;

# ==============================================================================
# EWING Comments
# I was not able to work in this integration with LWP and normal requests
# because the API requires the login access each time. I ended using
# WWW::Mechanize.
#
# In the sub getViptelaData, besides the request used to obtain the demo data,
# there are some others commented, because they do not have information or the
# same is not relevant in this specific case.
#
# A cheat for the model is market below. I am missing something somewhere else.
#
# PS. Not totally cleaned nor commented code.
# ==============================================================================

sub collect_plugin
{
	my (%args) = @_;
	my ($node, $S, $C) = @args{qw(node sys config)};

	my $NI = $S->ndinfo;
	my $V = $S->view;
	my $RD = $S->reachdata;

	logMsg(">> Working on $node $NI->{system}{nodeModel}");

	# this plugin deals only with CiscoViptelaCloud
	return (0,undef) if ( $NI->{system}{nodeModel} ne "CiscoViptelaCloud" );

	my $viptelaData = getViptelaData(name => $node);
	if ( defined $viptelaData->{error} ) {
		logMsg("ERROR with $node: $viptelaData->{error}");
	}

	my $rrddata = {
		'cpuIdle' => { "option" => "GAUGE,0:U", "value" => $viptelaData->{cpu_idle}},
		'cpuSystem' => { "option" => "GAUGE,0:U", "value" => $viptelaData->{cpu_system}},
		'cpuUser' => { "option" => "GAUGE,0:U", "value" => $viptelaData->{cpu_user}},
		'cpuUsage' => { "option" => "GAUGE,0:U", "value" => $viptelaData->{cpu_usage}},
	};

	# updateRRD subrutine is called from rrdfunc.pm module
	my $updatedrrdfileref = updateRRD(data=>$rrddata, sys=>$S, type=>"viptelacpu", index => undef);

	if ( not defined $NI->{graphtype}{viptelacpu} ) {
		$NI->{graphtype}{viptelacpu} = "Viptela_CPU"
	}

	my $rrddataMem = {
		'memUsed' => { "option" => "GAUGE,0:U", "value" => $viptelaData->{mem_used}},
		'memFree' => { "option" => "GAUGE,0:U", "value" => $viptelaData->{mem_free}},
		'memCached' => { "option" => "GAUGE,0:U", "value" => $viptelaData->{mem_cached}},
		'memBuffers' => { "option" => "GAUGE,0:U", "value" => $viptelaData->{mem_buffers}}
	};

	# updateRRD subrutine is called from rrdfunc.pm module
	$updatedrrdfileref = updateRRD(data=>$rrddataMem, sys=>$S, type=>"viptelamem", index => undef);

	# if the graphtype we make is not there, lets add it.
	if ( not defined $NI->{graphtype}{viptelamem} ) {
		$NI->{graphtype}{viptelamem} = "Viptela_MEM"
	}
	
	# lets give it some health
	my $health = 100;
	my $reachability = undef;

	######### what events do we want to raise?
	# if the thing is offline, then the node is down, online and alerting are Node Up
	if ( $viptelaData->{reachability} eq "unreachable" ) {
		# raise a new event.
		notify(sys => $S, event => "Node Down", element => "", details => "Viptela Cloud Reporting device offline");
		$reachability = 0;
		# take off the reachability part of health
		$health = $health - ($C->{weight_reachability} * 100);
	}
	else {
		# check if event exists and clear it
		checkEvent(sys => $S, event => "Node Down", level => "Normal", element => undef, details => "");
		$reachability = 100;
	}

	# get some OMP and BFD data and events happening.
	my $ompPeersTotal = $viptelaData->{ompPeersUp} + $viptelaData->{ompPeersDown};
	my $bfdSessionsTotal = $viptelaData->{bfdSessionsUp} + $viptelaData->{bfdSessionsDown};

	# if the thing is offline, then the node is down, online and alerting are Node Up
	if ( $viptelaData->{ompPeersDown} ) {
		# raise a new event.
		notify(sys => $S, event => "OMP Peers Down", element => "", details => "Viptela Cloud Reporting OMP Peers are Down");
		# reduce the health a bit
		$health = $health - 5;
	}
	else {
		# check if event exists and clear it
		checkEvent(sys => $S, event => "OMP Peers Down", level => "Normal", element => undef, details => "");
	}

	if ( $viptelaData->{bfdSessionsDown} ) {
		# raise a new event.
		notify(sys => $S, event => "BFD Sessions Down", element => "", details => "Viptela Cloud Reporting BFD Sessions are Down");
		# reduce the health a bit
		$health = $health - 5;
	}
	else {
		# check if event exists and clear it
		checkEvent(sys => $S, event => "BFD Sessions Down", level => "Normal", element => undef, details => "");
	}
		
	$RD->{health} = { value =>  $health, option => "gauge,0:U" };
	$RD->{reachability} = { value =>  $reachability, option => "gauge,0:U" };

	# set the lat and log based on the API data.
	if ( defined $viptelaData->{'latitude'} and defined $viptelaData->{'longitude'}
		and ( $viptelaData->{'latitude'} ne $NI->{system}{'location_latitude'}
		or $viptelaData->{'longitude'} ne $NI->{system}{'location_longitude'} ) )
	{
		info("$node Update Location Lat-Long: lat $viptelaData->{'latitude'} long $viptelaData->{'longitude'}");
		my $output = `/usr/local/nmis8/admin/node_admin.pl act=set node=$node entry.location_latitude=$viptelaData->{'latitude'} entry.location_longitude=$viptelaData->{'longitude'}`;
		$NI->{system}{'location_latitude'} = $viptelaData->{'latitude'};
		$NI->{system}{'location_longitude'} = $viptelaData->{'longitude'};
	}

	$NI->{system}{'nodeVendor'} = "Cisco Systems, Inc.";

	$V->{system}{"systemIp_value"} = $viptelaData->{'system-ip'};
	$V->{system}{"systemIp_title"} = 'Viptela IP Address';

	# $V->{system}{"loss_value"} = $viptelaData->{avgLossPercent};
	# $V->{system}{"loss_title"} = 'Viptela AVG Loss Percent';

	# $V->{system}{"mac_value"} = $viptelaData->{mac};
	# $V->{system}{"mac_title"} = 'Viptela MAC Address';

	# Store the results for the GUI to display
	$V->{system}{"viptelastatus_value"} = $viptelaData->{status};
	$V->{system}{"viptelastatus_title"} = 'Viptela Status';
	$V->{system}{"viptelastatus_color"} = '#00FF00';
	$V->{system}{"viptelastatus_color"} = '#FF0000' if $viptelaData->{reachability} eq "unreachable";

	$V->{system}{"boardserial_value"} = $viptelaData->{'board-serial'};
	$V->{system}{"boardserial_title"} = 'Viptela Board Serial';

	# $V->{system}{"perfScore_value"} = $viptelaData->{perfScore};
	# $V->{system}{"perfScore_title"} = 'Viptela Performance Score';

	# $V->{system}{"publicIp_value"} = $viptelaData->{publicIp};
	# $V->{system}{"publicIp_title"} = 'Viptela Public IP';

	$V->{system}{"uuid_value"} = $viptelaData->{uuid};
	$V->{system}{"uuid_title"} = 'Viptela UUID';

	$V->{system}{"personality_value"} = $viptelaData->{personality};
	$V->{system}{"personality_title"} = 'Viptela Personality';

	$V->{system}{"siteid_value"} = $viptelaData->{'site-id'};
	$V->{system}{"siteid_title"} = 'Viptela Site ID';

	$V->{system}{"ompPeers_value"} = "$viptelaData->{ompPeersDown} of $ompPeersTotal";
	$V->{system}{"ompPeers_title"} = 'OMP Peers Down';
	$V->{system}{"ompPeers_color"} = '#00FF00';
	$V->{system}{"ompPeers_color"} = '#ffd700' if $viptelaData->{ompPeersDown};

	$V->{system}{"bfdSessions_value"} = "$viptelaData->{bfdSessionsDown} of $bfdSessionsTotal";
	$V->{system}{"bfdSessions_title"} = 'BFD Sessions Down';
	$V->{system}{"bfdSessions_color"} = '#00FF00';
	$V->{system}{"bfdSessions_color"} = '#ffd700' if $viptelaData->{bfdSessionsDown};

	return (1,undef);							# happy, changes were made so save view and nodes files
}

sub getViptelaData {
	my %args = @_;
	my $deviceName = $args{name};

	my ($err, $viptelaConfig) = loadJsonFile("/usr/local/nmis8/conf/CiscoViptelaCloud.json");

	# print Dumper($viptelaConfig);

	my $apiBase = $viptelaConfig->{apiBase};
	my $username = $viptelaConfig->{username};
	my $password = $viptelaConfig->{password};
	my $databaseDir = $viptelaConfig->{databaseDir};
	my $historySeconds = $viptelaConfig->{historySeconds};
	
	if ( not $apiBase or not $username or not $password or not $databaseDir or not $historySeconds ) {
		print "ERROR with configuration, something is not working\n";
		return;
	}

	make_path("$databaseDir/devices");

	my $viptelaData;
	my $viptelaStateFile = "$databaseDir/viptela.json";
	my $viptelaState;
	if ( -f $viptelaStateFile ) {
		($err, $viptelaState) = loadJsonFile($viptelaStateFile);
	}

	# create the user agent all the queries will use.
	# my $ua = getApiAgent();

	my $apiCall;
	my $deviceFound = 0;

	# print "LastDevStatuses: $viptelaState->{lastDeviceStatuses}\n";

	# have we got device status data recently?
	if ( not defined $viptelaState->{lastDeviceStatuses}
	 	or time() - $viptelaState->{lastDeviceStatuses} > 300
	) {
		info("deviceStatuses is old, refreshing the cache");

		$apiCall = "$apiBase/dataservice/device";
		info("about to run $apiCall");
		my $data = getApiData(loginUrl => "$apiBase/j_security_check", url => $apiCall, username => $username, password => $password, debug => 0);
		my $count = 0;
		$deviceFound = 0;
		foreach my $device (@$data) {
			++$count;
			saveJsonFile("$databaseDir/devices/$device->{'host-name'}.json",$device);
			$deviceFound = 1;
		}
		$viptelaState->{lastDeviceStatuses} = time;
		info("there were $count devices");
	}

	# get the lossAndLatencyHistory for one deviceName
	# first load the deviceStatus for this device.
	my $deviceFile = "$databaseDir/devices/$deviceName.json";

	if ( -r $deviceFile ) {
		my $deviceData = loadJsonFile("$databaseDir/devices/$deviceName.json");
		# get all the data from the cache.
		$viptelaData = $deviceData;

		#"status":"offline"}

		# if ( $deviceData->{status} ne "offline" ) {
		if ( $deviceData->{reachability} ne "unreachable" ) {
			print Dumper $deviceData if $debug > 1;

			# build a query to get the lossAndLatencyHistory data.
			# my $currentTime = time();
			# my $timeStart = time2str("%Y-%m-%dT%T", $currentTime-18000-300);
			# my $timeEnd = time2str("%Y-%m-%dT%T", $currentTime-18000);
			# $apiCall = "$apiBase/dataservice/data/device/state/interfacestatistics?startDate=$timeStart&endDate=$timeEnd";
			# $apiCall = "$apiBase/dataservice/data/device/state/devicesystemstatusstatistics?startDate=$timeStart&endDate=$timeEnd";
			# $apiCall = "$apiBase/dataservice/system/device/vedges";
			# $apiCall = "$apiBase/dataservice/data/device/state/ControlConnection?count=1";
			# $apiCall = "$apiBase/dataservice/device/ip/mfibstats?deviceId=$deviceData->{deviceId}";  # OK
			# $apiCall = "$apiBase/dataservice/device/ip/nat/interfacestatistics?deviceId=$deviceData->{deviceId}";  # OK
			$apiCall = "$apiBase/dataservice/device/system/status?deviceId=$deviceData->{deviceId}";  # OK
			# $apiCall = "$apiBase/dataservice/device/hardware/synced/environment?deviceId=$deviceData->{deviceId}";
			# $apiCall = "$apiBase/dataservice/statistics/approute/transport/summary/latency"; # SUMA TODOS
			# $apiCall = "$apiBase/dataservice/device/hardwarehealth/summary";
			# $apiCall = "$apiBase/dataservice/device/hardware/status/summary?deviceId=$deviceData->{deviceId}";
			# $apiCall = "$apiBase/dataservice/statistics/interface/aggregation";
			# $apiCall = "$apiBase/dataservice/statistics/system/fields";  # OK - fields de estadísticas

			# my $query = '{"query":{"condition":"AND","rules":[{"value":["1"],"field":"entry_time","type":"date","operator":"last_n_hours"},{"value":["' . $deviceData->{deviceId} . '"],"field":"vdevice_name","type":"string","operator":"in"}]},"fields":["entry_time","count","mem_util"],"sort":[{"field":"entry_time","type":"date","order":"asc"}]}';
			# $apiCall = "$apiBase/dataservice/statistics/system?query=$query";  # GET OK

			# my $query = {"query"=>{"condition"=>"AND","rules"=>[{"value"=>["1"],"field"=>"entry_time","type"=>"date","operator"=>"last_n_hours"},{"value"=>["$deviceData->{deviceId}"],"field"=>"vdevice_name","type"=>"string","operator"=>"in"}]},"fields"=>["entry_time","count","mem_util"],"sort"=>[{"field"=>"entry_time","type"=>"date","order"=>"asc"}]};
			# my $query = {"query"=>{"condition"=>"AND","rules"=>[{"value"=>["$deviceData->{deviceId}"],"field"=>"vdevice_name","type"=>"string","operator"=>"equal"}]},"fields"=>["entry_time","count","mem_util"],"sort"=>[{"field"=>"entry_time","type"=>"date","order"=>"asc"}]};
			# $apiCall = "$apiBase/dataservice/statistics/system";  # POST OK

			# my $query = {"query"=>{"condition"=>"AND","rules"=>[{"value"=>["1"],"field"=>"entry_time","type"=>"date","operator"=>"last_n_hours"},{"value"=>["100"],"field"=>"loss_percentage","type"=>"number","operator"=>"less"},{"value"=>["$deviceData->{deviceId}"],"field"=>"vdevice_name","type"=>"string","operator"=>"in"}]},"aggregation"=>{"field"=>[{"property"=>"local_color","order"=>"asc","sequence"=>1}],"metrics"=>[{"property"=>"loss_percentage","type"=>"avg"},{"property"=>"latency","type"=>"avg"},{"property"=>"jitter","type"=>"avg"}]}};
			# $apiCall = "$apiBase/dataservice/statistics/approute/aggregation";

			info("about to run $apiCall");
			my $statisticData = getApiData(loginUrl => "$apiBase/j_security_check", url => $apiCall, username => $username, password => $password, debug => 0);
			# my $statisticData = postApiData(loginUrl => "$apiBase/j_security_check", url => $apiCall, query => $query, username => $username, password => $password, debug => 0);

			$viptelaData->{cpu_idle} = @$statisticData[0]->{cpu_idle};
			$viptelaData->{cpu_system} = @$statisticData[0]->{cpu_system};
			$viptelaData->{cpu_user} = @$statisticData[0]->{cpu_user};
			$viptelaData->{cpu_usage} = 100 - @$statisticData[0]->{cpu_idle};
			#
			$viptelaData->{mem_used} = @$statisticData[0]->{mem_used};
			$viptelaData->{mem_free} = @$statisticData[0]->{mem_free};
			$viptelaData->{mem_cached} = @$statisticData[0]->{mem_cached};
			$viptelaData->{mem_buffers} = @$statisticData[0]->{mem_buffers};

			$apiCall = "$apiBase/dataservice/device/counters?deviceId=$deviceData->{deviceId}";  # OK
			info("about to run $apiCall");

			my $counterData = getApiData(loginUrl => "$apiBase/j_security_check", url => $apiCall, username => $username, password => $password, debug => 0);
			# my $statisticData = postApiData(loginUrl => "$apiBase/j_security_check", url => $apiCall, query => $query, username => $username, password => $password, debug => 0);

			$viptelaData->{ompPeersUp} = @$counterData[0]->{ompPeersUp};
			$viptelaData->{ompPeersDown} = @$counterData[0]->{ompPeersDown};
			$viptelaData->{bfdSessionsUp} = @$counterData[0]->{bfdSessionsUp};
			$viptelaData->{bfdSessionsDown} = @$counterData[0]->{bfdSessionsDown};
			$viptelaData->{rebootCount} = @$counterData[0]->{rebootCount};
			
			# NOT RETURNING ANY DATA IN DEMO
			# $apiCall = "$apiBase/dataservice/device/ip/mfibstats?deviceId=$deviceData->{deviceId}";  # OK
			# $apiCall = "$apiBase/dataservice/device/ip/nat/interfacestatistics?deviceId=$deviceData->{deviceId}";  # OK
			# print "about to run $apiCall\n";
			# my $ipStatisticData = getApiData(loginUrl => "$apiBase/j_security_check", url => $apiCall, username => $username, password => $password, debug => 0);
		}
		else {
			$viptelaData->{error} = "Device Status not online: $deviceData->{status}";
			$viptelaData->{cpu_idle} = "U";
			$viptelaData->{cpu_system} = "U";
			$viptelaData->{cpu_user} = "U";
			$viptelaData->{cpu_usage} = "U";
			#
			$viptelaData->{mem_used} = "U";
			$viptelaData->{mem_free} = "U";
			$viptelaData->{mem_cached} = "U";
			$viptelaData->{mem_buffers} = "U";

			$viptelaData->{ompPeersUp} = "U";
			$viptelaData->{ompPeersDown} = "U";
			$viptelaData->{bfdSessionsUp} = "U";
			$viptelaData->{bfdSessionsDown} = "U";
			$viptelaData->{rebootCount} = "U";
		}
		saveJsonFile("$databaseDir/devices/$deviceName-data.json",$viptelaData);
	}	else {
		$viptelaData->{error} = "No Device Status file found: $deviceFile";
	}

	# save the viptela state info for caching
	saveJsonFile("$viptelaStateFile", $viptelaState);

	# send back the results.
	return $viptelaData;
}

sub getLoginData {
	my %args = @_;

	my $username = $args{username};
	my $password = $args{password};
	my $loginUrl = $args{loginUrl};
	my $url = $args{url};
	my $debugCall = $args{debug};

	my $data;

	my $cookie_file = "/tmp/cookies";
	my $mech = WWW::Mechanize->new(
		ssl_opts => {
    	SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE,
    	verify_hostname => 0
  	} 
  );
	$mech->get($url);
	$mech->submit_form(
    with_fields => {
      'j_username'  => $username,
      'j_password'  => $password,
    }
	);

	# print Dumper($mech->response()->headers) . "\n";
	my $c = $mech->content();

	if( $c =~ m/\{(.*?)\}/s ) {
		$data = decode_json($c);
	}	else {
		print "ERROR: " . "not json data" . "\n";
	}
	return $data->{data};
}

sub getApiData {
	my %args = @_;

	my $username = $args{username};
	my $password = $args{password};
	my $loginUrl = $args{loginUrl};
	my $url = $args{url};
	my $debugCall = $args{debug};

	my $data;

	my $mech = WWW::Mechanize->new(
		ssl_opts => {
    	SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE,
    	verify_hostname => 0
  	} 
  );
  $mech->get($url);

	$mech->submit_form(
    with_fields => {
      'j_username'  => $username,
      'j_password'  => $password,
    }
	);

	# print $mech->content();
	my $c = $mech->content();

	if( $c =~ m/\{(.*?)\}/s ) {
		$data = decode_json($c);
	}	else {
		print "ERROR: " . "not json data" . "\n";
	}
	# print Dumper($data->{data});
	return $data->{data};
}

sub postApiData {
	my %args = @_;

	my $username = $args{username};
	my $password = $args{password};
	my $loginUrl = $args{loginUrl};
	my $url = $args{url};
	my $query = $args{query};
	my $debugCall = $args{debug};

	my $data;

	my $content = encode_json($query);
	# print Dumper($content);

	my $mech = WWW::Mechanize->new(
		ssl_opts => {
    	SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE,
    	verify_hostname => 0
  	} 
  );
  
	$mech->post( $url,
		Content_Type => 'application/json',
		Content      => $content,
	);

	$mech->submit_form(
    with_fields => {
      'j_username'  => $username,
      'j_password'  => $password,
    }
	);

	print $mech->content();
	my $c = $mech->content();

	if( $c =~ m/\{(.*?)\}/s ) {
		$data = decode_json($c);
	}	else {
		print "ERROR: " . "not json data" . "\n";
	}
	# print Dumper($data->{pageInfo});
	return $data->{data};
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

=pod
my $viptelaData;
# getViptelaData( name => "test" );
$viptelaData = getViptelaData( name => "vedge-001" );
# getViptelaData( name => "vedge-002" );
# $viptelaData = getViptelaData( name => "vedge-003" );
# getViptelaData( name => "vsmart-01" );

# print ">>>$viptelaData->{'system-ip'}\n";
print Dumper($viptelaData);
=cut

1;
