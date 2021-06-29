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
# a small update plugin for discovering interfaces on FutureSoftware devices
# which requires custom snmp accesses
package RuckusCloudNoPlugin;
our $VERSION = "1.0.0";

use strict;

use func;												# for loading extra tables
use NMIS;												# iftypestable
use rrdfunc;										# for updateRRD
use JSON::XS;
use LWP::UserAgent;
use File::Path qw(make_path);
use Data::Dumper;
use Time::HiRes qw(usleep nanosleep gettimeofday);
#nanosleep(1000000);

use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

use Exporter;

@ISA = qw(Exporter);

@EXPORT = qw(
	collect_plugin_ruckuscloud
	getRuckusData
);

my $debug = 0;

# sub collect_plugin
sub collect_plugin_ruckuscloud
{
	my (%args) = @_;
	my ($node, $S, $C) = @args{qw(node sys config)};

	#
	$S = Sys->new; $S->init(name => $node, snmp => "false");
	#

	my $NI = $S->ndinfo;
	my $V = $S->view;
	# my $RD = $S->reachdata;

	print "Reachdata: \n";
	print Dumper $S->reachdata;

	logMsg("Working on $node $NI->{system}{nodeModel}");

	if ( $NI->{system}{model} ne $NI->{system}{nodeModel} ) {
		logMsg("ERROR Model inconsistency on $node $NI->{system}{model} vs $NI->{system}{nodeModel}");
	}

	# this plugin deals only with RuckusCloud
	return (0,undef) if ( $NI->{system}{nodeModel} ne "RuckusCloud" );

	# this plugin will run every minute so lets not poll the API too often.
	#here 300 por 1
	if ( defined $NI->{system}{last_poll} and time() - $NI->{system}{last_poll} < 1 ) {
		info("Skipping, plugin ran for $node less than 300 seconds ago.");
		return (0,undef);
	}

	my $ruckusData = getRuckusData(name => $node);
	if ( defined $ruckusData->{error} ) {
		logMsg("ERROR with $node: $ruckusData->{error}");
	}

	my $connStatus = 100;
	if ($ruckusData->{ruckusSCGAPConnStatus} eq "Disconnect") {
		$connStatus = 0;
	}

	my $rrddata = {
		'ruckusconnstatus' => { "option" => "GAUGE,0:U", "value" => $connStatus},
		'ruckusaprxbytes' => { "option" => "COUNTER,0:U", "value" => $ruckusData->{ruckusSCGAPRXBytes}},
		'ruckusaptxbytes' => { "option" => "COUNTER,0:U", "value" => $ruckusData->{ruckusSCGAPTXBytes}},
	};

	# updateRRD subrutine is called from rrdfunc.pm module
	my $updatedrrdfileref = updateRRD(data=>$rrddata, sys=>$S, type=>"ruckuscloud", index => undef);

	# if the graphtype we make is not there, lets add it.
	if ( not defined $NI->{graphtype}{ruckuscloud} ) {
		$NI->{graphtype}{ruckuscloud} = "RuckusCloud_Health"
	}

	print "ABR RRD updated ...\n";

=pod
	EVENTS AND LOCATION NOT CONSIDERED YET 
=cut

	# ============================================================================
	$NI->{system}{last_poll} = time();
	# ============================================================================
	$NI->{system}{'nodeVendor'} = "Universal";
	$V->{system}{nodeVendor_value} = $NI->{system}{nodeVendor};
	$V->{system}{nodeVendor_title} = 'Vendor';
	$V->{system}{group_value} = $NI->{system}{group};
	$V->{system}{group_title} = 'Group';
	$V->{system}{customer_value} = $NI->{system}{customer};
	$V->{system}{customer_title} = 'Customer';
	$V->{system}{location_value} = $NI->{system}{location};
	$V->{system}{location_title} = 'Location';
	$V->{system}{businessService_value} = $NI->{system}{businessService};
	$V->{system}{businessService_title} = 'Business Service';
	$V->{system}{serviceStatus_value} = $NI->{system}{serviceStatus};
	$V->{system}{serviceStatus_title} = 'Service Status';
	$V->{system}{notes_value} = $NI->{system}{notes};
	$V->{system}{notes_title} = 'Notes';
	# ============================================================================
	# Store the results for the GUI to display
	# ============================================================================
	$V->{system}{"apconnstatus_value"} = $ruckusData->{ruckusSCGAPConnStatus};
	$V->{system}{"apconnstatus_title"} = 'AP Status';
	$V->{system}{"apconnstatus_color"} = '#00FF00';
	$V->{system}{"apconnstatus_color"} = '#FF0000' if $ruckusData->{ruckusSCGAPConnStatus} eq "Disconnect";

	$V->{system}{"apdescription_value"} = $ruckusData->{ruckusSCGAPDescription};
	$V->{system}{"apdescription_title"} = 'AP Description';

	$V->{system}{"apdomain_value"} = $ruckusData->{ruckusSCGAPDomain};
	$V->{system}{"apdomain_title"} = 'AP Domain';

	$V->{system}{"apextip_value"} = $ruckusData->{ruckusSCGAPExtIP};
	$V->{system}{"apextip_title"} = 'AP Ext IP';

	$V->{system}{"apfwversion_value"} = $ruckusData->{ruckusSCGAPFWversion};
	$V->{system}{"apfwversion_title"} = 'AP FW version';

	$V->{system}{"apgpsinfo_value"} = $ruckusData->{ruckusSCGAPGPSInfo};
	$V->{system}{"apgpsinfo_title"} = 'AP GPS Info';

	$V->{system}{"apip_value"} = $ruckusData->{ruckusSCGAPIP};
	$V->{system}{"apip_title"} = 'AP IP';

	$V->{system}{"apmac_value"} = $ruckusData->{ruckusSCGAPMac};
	$V->{system}{"apmac_title"} = 'AP MAC';

	$V->{system}{"aplocation_value"} = $ruckusData->{ruckusSCGAPLocation};
	$V->{system}{"aplocation_title"} = 'AP Location';

	$V->{system}{"apmeshrole_value"} = $ruckusData->{ruckusSCGAPMeshRole};
	$V->{system}{"apmeshrole_title"} = 'AP Mesh Role';

	$V->{system}{"apname_value"} = $ruckusData->{ruckusSCGAPName};
	$V->{system}{"apname_title"} = 'AP Name';

	$V->{system}{"apserial_value"} = $ruckusData->{ruckusSCGAPSerial};
	$V->{system}{"apserial_title"} = 'AP Serial';

	$V->{system}{"apuptime_value"} = $ruckusData->{ruckusSCGAPUptime};
	$V->{system}{"apuptime_title"} = 'AP Uptime';

	$V->{system}{"apzone_value"} = $ruckusData->{ruckusSCGAPZone};
	$V->{system}{"apzone_title"} = 'AP Zone';

	$V->{system}{"apmodel_value"} = $ruckusData->{ruckusSCruckusSCGAPModelGAPMac};
	$V->{system}{"apmodel_title"} = 'AP Model GAP Mac';
	# ============================================================================

	# ============================================================================
	# system('/usr/local/nmis8/admin/node_admin.pl act=set node=' . $node . ' entry.mac_value="' . $merakiData->{mac} . '" info=1');
	# system('/usr/local/nmis8/admin/node_admin.pl act=set node=' . $node . ' entry.networkId_value="' . $merakiData->{networkId} . '" info=1');
	# system('/usr/local/nmis8/admin/node_admin.pl act=set node=' . $node . ' entry.publicIp_value="' . $merakiData->{publicIp} . '" info=1');
	# system('/usr/local/nmis8/admin/node_admin.pl act=set node=' . $node . ' entry.wan2Ip_value="' . $merakiData->{wan2Ip} . '" info=1');
	# system('/usr/local/nmis8/admin/node_admin.pl act=set node=' . $node . ' entry.wan1Ip_value="' . $merakiData->{wan1Ip} . '" info=1');
	# system('/usr/local/nmis8/admin/node_admin.pl act=set node=' . $node . ' entry.wan2IpStatus_value="' . $merakiData->{wan2IpStatus} . '" info=1');
	# system('/usr/local/nmis8/admin/node_admin.pl act=set node=' . $node . ' entry.wan1IpStatus_value="' . $merakiData->{wan1IpStatus} . '" info=1');
	# system('/usr/local/nmis8/admin/node_admin.pl act=set node=' . $node . ' entry.lanIp_value="' . $merakiData->{lanIp} . '" info=1');
	# system('/usr/local/nmis8/admin/node_admin.pl act=set node=' . $node . ' entry.serial_value="' . $merakiData->{serial} . '" info=1');
	# ============================================================================

	return (1,undef);							# happy, changes were made so save view and nodes files
}

sub getRuckusData {
	my %args = @_;
	my $deviceName = $args{name};

	my $ruckusConfig = loadJsonFile("/usr/local/nmis8/conf/RuckusCloud.json");

	my $databaseDir = $ruckusConfig->{databaseDir};
	my $historySeconds = $ruckusConfig->{historySeconds};

	make_path("$databaseDir/devices");
	my $ruckusData;

	print "Obtaining data for device: $deviceName\n";

	my $deviceFile = "$databaseDir/devices/$deviceName.json";
	if ( -r $deviceFile ) {
		my $deviceData = loadJsonFile("$databaseDir/devices/$deviceName.json");
		# get all the data from the cache.
		$ruckusData = $deviceData;
	}
	else {
		$ruckusData->{error} = "No Device Status file found: $deviceFile";
	}

	print "Dumping ruckusData ...\n";
	print Dumper $ruckusData;
	# save the ruckus state info for caching
	# saveJsonFile("$ruckusStateFile",$ruckusState);

	# send back the results.
	return $ruckusData;
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

sub println
{
        print ((@_? join($/, @_) : $_), $/);
}

1;
