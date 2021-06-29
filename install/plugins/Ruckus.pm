# a small update plugin for discovering interfaces on FutureSoftware devices
# which requires custom snmp accesses
package Ruckus;
our $VERSION = "1.0.0";

use strict;

use lib "/usr/local/nmis8/conf/plugins";
use RuckusCloudNoPlugin;

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

$Data::Dumper::Indent = 1;

my $nodeinfo = loadLocalNodeTable();

sub collect_plugin
{
	my (%args) = @_;
	my ($node, $S, $C) = @args{qw(node sys config)};

	my $NI = $S->ndinfo;
	my $V = $S->view;
	# my $RD = $S->reachdata;

	logMsg("Working on $node $NI->{system}{nodeModel}");

	if ( $NI->{system}{model} ne $NI->{system}{nodeModel} ) {
		logMsg("ERROR Model inconsistency on $node $NI->{system}{model} vs $NI->{system}{nodeModel}");
	}

	# this plugin deals only with RuckusCloud
	return (0,undef) if ( $NI->{system}{nodeModel} ne "Ruckus" );

	# this plugin will run every minute so lets not poll the API too often.
	#here 300 por 1
	if ( defined $NI->{system}{last_poll} and time() - $NI->{system}{last_poll} < 1 ) {
		info("Skipping, plugin ran for $node less than 300 seconds ago.");
		return (0,undef);
	}

	my $changesweremade = 0;

	my $ruckusConfig = loadJsonFile("/usr/local/nmis8/conf/RuckusCloud.json");
	my $databaseDir = $ruckusConfig->{databaseDir};
	my $historySeconds = $ruckusConfig->{historySeconds};

	foreach my $key (keys %{$NI->{SmartCell}}) {
		print Dumper $key;
		if ($NI->{SmartCell}->{$key}->{ruckusSCGAPName} =~ m|^cpe\-.+|) {
			next;
		}
		my $scgapName = $NI->{SmartCell}->{$key}->{ruckusSCGAPName};
		$scgapName =~ s/[^a-zA-Z0-9,]/_/g;

		# ==========================================================================
		my $noderec = $nodeinfo->{$scgapName};
		if ( $noderec ) {
			print "ABR This node exists: $scgapName \n";

			saveJsonFile("$databaseDir/devices/$scgapName.json", $NI->{SmartCell}->{$key} );
			collect_plugin_ruckuscloud(node => $scgapName, sys => $S, config => $C);
		}
		# ==========================================================================

		# $changesweremade = 1;
	}

	print "ABR Collect end ...\n";

	return (1,undef);							# happy, changes were made so save view and nodes files
}

sub update_plugin
{
	my (%args) = @_;
	my ($node,$S,$C) = @args{qw(node sys config)};

	my $NI = $S->ndinfo;
	my $IF = $S->ifinfo;
	# anything to do?

	return (0,undef) if ( $NI->{system}{nodeModel} ne "Ruckus"
												or !getbool($NI->{system}->{collect}));

	my $changesweremade = 0;

	info("ABR Working on $node Ruckus");

	# print Dumper $NI->{SmartCell};

	my $ruckusConfig = loadJsonFile("/usr/local/nmis8/conf/RuckusCloud.json");
	my $databaseDir = $ruckusConfig->{databaseDir};
	my $historySeconds = $ruckusConfig->{historySeconds};

	print "ABR CSV Data\n";
	my $csvData = "";
	print "name,host,group,role,community" . "\n";
	$csvData = $csvData . "name,host,group,role,community" . "\n";
	foreach my $key (keys %{$NI->{SmartCell}}) {
		# print Dumper $key;
		if ($NI->{SmartCell}->{$key}->{ruckusSCGAPName} =~ m|^cpe\-.+|) {
			next;
		}
		my $scgapName = $NI->{SmartCell}->{$key}->{ruckusSCGAPName};
		$scgapName =~ s/[^a-zA-Z0-9,]/_/g;

		print $scgapName . ",";
		print $NI->{SmartCell}->{$key}->{ruckusSCGAPExtIP} . ",";
		print "NMIS8,core,public" . "\n";

		$csvData = $csvData . $scgapName . ",";
		$csvData = $csvData . $NI->{SmartCell}->{$key}->{ruckusSCGAPExtIP} . ",";
		$csvData = $csvData . "NMIS8,core,public" . "\n";

		saveJsonFile("$databaseDir/devices/$scgapName.json", $NI->{SmartCell}->{$key} );

		$changesweremade = 1;
	}

	saveCsvFile("$databaseDir/import/ruckusdevs_$node.csv", $csvData);

	return ($changesweremade,undef); # report if we changed anything
}

# ==============================================================================
# ==============================================================================

sub saveCsvFile {
	my $file = shift;
	my $data = shift;
	my $error;

	open(FILE, ">$file") or $error = "ERROR with file $file: $!";
	if ( not $error ) {
		# json files must be utf-8 encoded
		print FILE $data;
		close(FILE);
	}
	chmod (0660, $file);

	return $error;
}

sub hashToJson {
	my $hash = shift;
	my $pretty = shift || 0;

	# my $json_str = encode_json(\%{$hash});
	my $json_str = JSON::XS->new->pretty($pretty)->utf8(1)->encode($hash);
	print "JSON data converting ...\n";
	print "$json_str\n";
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

	print "Opening json file ...\n";

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

	print "Json file read ...\n";

	return ($error,$data);
}
