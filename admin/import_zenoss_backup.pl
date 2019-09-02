#!/usr/bin/perl
#
#  Copyright (C) Opmantek Limited (www.opmantek.com)
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

use FindBin;
use lib "$FindBin::Bin/../lib";

use strict;
use func;
use Array::Utils;
use Data::Dumper;
use NMIS;
use NMIS::Timing;

use Fcntl qw(:DEFAULT :flock);

use constant {
	CONST_PATIENCE => "This procedure is slow to be accurate. Please be patient ...",
	CONST_ALL_LOCATIONS => "all", # parameter value used by arg setlocation
	CONST_SET_LOCATION_SET_TITLE => "setTitle", # parameter value used by arg setlocation
	CONST_SET_LOCATION_SET_ADDRESS => "setAddress", # parameter value used by arg setlocation
	CONST_NODE_EXPECTED_PROP => "setTitle",
	CONST_NODE_ROLE_DEFAULT => "access",
	CONST_NODE_GROUP_DEFAULT => "NMIS8",
};

my $t = NMIS::Timing->new();

print $t->elapTime(). " Begin\n";

# Variables for command line munging
my %arg = getArguements(@ARGV);

# Set debugging level.
my $debug = setDebug($arg{debug});


# load configuration table
my $C = loadConfTable(conf=>$arg{conf},debug=>$arg{debug});

my $overwrite = setDebug($arg{overwrite});

if ( $ARGV[0] eq "" ) {
	my $all_locations = CONST_ALL_LOCATIONS;
	my $set_location_setTitle = CONST_SET_LOCATION_SET_TITLE;
	my $set_location_setAddress = CONST_SET_LOCATION_SET_ADDRESS;
	my $node_role_default = CONST_NODE_ROLE_DEFAULT;
	my $node_group_default = CONST_NODE_GROUP_DEFAULT;
	
	print <<EO_TEXT;
$0 will import nodes to NMIS.
ERROR: need some files to work with

usage example:
$0 \\
	zenbatchdump=/usr/local/nmis8/admin/samples/zenbatchdump.txt \\
	nodes=/usr/local/nmis8/conf/Nodes.nmis.new \\
	locations=/usr/local/nmis8/conf/Locations.nmis.new \\
	customers=/usr/local/nmis8/conf/Customers.nmis.new \\
	role=$node_role_default group=$node_group_default customer_is_imported_group=0|1 fixNames=0|1 setlocation=$all_locations|$set_location_setAddress|$set_location_setTitle verbose=0|1

EO_TEXT
	exit 1;
}

my $verbose = (defined $arg{verbose})? getbool($arg{verbose}): 1;

my $defined_role = $arg{role};
my $defined_group = $arg{group};
my $customer_is_imported_group = $arg{customer_is_imported_group};
my $fixNames = getbool($arg{fixNames});
my $setlocation = $arg{setlocation};
# we only allow the 3 options:
if ( $setlocation ne CONST_SET_LOCATION_SET_ADDRESS and $setlocation ne CONST_SET_LOCATION_SET_TITLE and $setlocation ne CONST_ALL_LOCATIONS) {
	$setlocation = CONST_ALL_LOCATIONS;
}

my $rec_delim_char = "\n";
# strictly no capturing within these compiled regexes: use (?:pattern) to group without capture
my $rec_delimiter = qr/$rec_delim_char{1}/; # split records on '\n' at beginning and end
my $any_chars_ungreedy_pattern = qr/.*?/;
my $quoted_any_chars_pattern = qr/(?:'$any_chars_ungreedy_pattern')|(?:"$any_chars_ungreedy_pattern")/; # any text between single or double quotes


if ( -r $arg{zenbatchdump} ) {
	my $zenbatchdumpfile = $arg{zenbatchdump};
	my $file_content = myLoadFile($zenbatchdumpfile);
	if (defined $file_content) {
		my $finalstr;
		$finalstr .= loadLocations($file_content,$arg{locations});
		print "\n\n";
		$finalstr .= loadCustomers($file_content,$arg{customers});
		print "\n\n";
		$finalstr .= loadNodes($file_content,$arg{nodes});

		print "\n\nRESULTS:\n\n$finalstr";
	}
	else {
		print "ERROR: zenbatchdump \"$arg{zenbatchdump}\" file contents could not be read\n";
	}
	
}
else {
	print "ERROR: zenbatchdump \"$arg{zenbatchdump}\" is an invalid file\n";
}

exit 1;


sub stripQuotes {
	my $instr = shift;

	# we must be removing matching quote chars when stripping quotes:
	if (substr($instr, 0, 1) eq substr($instr, -1)) {
		return substr($instr,1,-1);
	}
	return $instr;
}

sub stripQuotesUsingFirstLastChars {
	my $instr = shift;
	my $quoteFirst = shift;
	my $quoteLast = shift;
	
	if ( (!defined $quoteFirst) or (!defined $quoteLast)) {
		die "ERROR: stripQuotesUsingFirstLastChars() must be called with 3 args (instr,quoteFirst,quoteLast). Exiting ...\n";
	}

	# we must be removing matching quote chars when stripping quotes:
	if ( (substr($instr, 0, 1) eq $quoteFirst) and (substr($instr, -1)) eq $quoteLast ) {
		return substr($instr,1,-1);
	}
	return $instr;
}

sub stripForwardSlashAsFirstChar {
	my $instr = shift;
	
	if (substr($instr, 0, 1) eq '/') {
		$instr = substr($instr,1);
	}
	return $instr;
}

sub forwardSlashToChar {
	my $instr = shift;
	my $replacement = shift;
	
	$instr =~ s/\//$replacement/g;
	return $instr;
}

sub validPopulatedParameter {
	my $instr = shift;
	
	return (defined $instr and $instr ne "" and $instr ne "''" and $instr ne '""');
}

sub loadLocations {
	my $file_content = shift;
	my $nmislocations = shift;
	
	my $res;
	
	print $t->markTime(). " Loading the Local Locations List\n";
	my $LT = loadLocationsTable();
	print "  done in ".$t->deltaTime() ."\n\n";

	print $t->markTime(). " Loading the Import Locations from zenbatchdumpfile. " . CONST_PATIENCE . "\n";
	my $expected_location_count = 0;
	my %newLocations;
	{
		# strictly no capturing within these compiled regexes: use (?:pattern) to group without capture
		# locations always start with '/Locations/'
		my $location_prepend_str_pattern = qr/\/Locations\//;
		# this pattern is expensive but it works, accurateley extracting the first quoted string on the relevant line
		my $quoted_location_pattern = qr/(?:'$location_prepend_str_pattern(?:(?:'')*[^']*)*')|(?:"$location_prepend_str_pattern(?:(?:"")*[^"]*)*")/;
		# options are:
		# setAddress: count=289
		# setTitle: count=98
		my $location_expected_prop_pattern ;
		if ($setlocation ne CONST_ALL_LOCATIONS) {
			$location_expected_prop_pattern = qr/$setlocation=$quoted_any_chars_pattern/;
		}
		else {
			$location_expected_prop_pattern = $any_chars_ungreedy_pattern;
		}
		my $draft_hash_val_pattern = qr/\s+
									  $any_chars_ungreedy_pattern
									  $location_expected_prop_pattern
									  $any_chars_ungreedy_pattern/x; # /x allows regex over multiple lines
		undef $location_expected_prop_pattern;
								  
		# capture locations key and value with (...)(...) in this regex:
		# get each block of text containing $location_expected_prop_pattern and split to quoted_key and value,
		my %newLocationsDraft = map { /$rec_delimiter
									   ($quoted_location_pattern)
									   ($draft_hash_val_pattern)
									   $rec_delimiter
									  /gsx } $file_content; # /x allows regex over multiple lines

		$expected_location_count = scalar (keys %newLocationsDraft);
		my $unique_location_count = scalar (Array::Utils::unique(keys %newLocationsDraft));
		if ($unique_location_count != $expected_location_count) {
			die "ERROR: unique location count \"$unique_location_count\" <> expected location count \"$expected_location_count\". Exiting ...\n";
		}

		# capture key and value with (...)=(...) in this regex:
		# regex to split each %newLocationsDraft value into its constituent key and value properties
		my $hash_val_pattern = qr/\s+(.*?)=($quoted_any_chars_pattern)/; # /x allows regex over multiple lines
		# split each %newLocationsDraft value into its constituent key and value properties
		# then populate %newLocations with key=hash of properties
		# %newLocationsDraft location keys are quoted.
		# we sort since we die on errors here and we want this to be a consistent procedure:
		
		# this pattern will be applied after stripQuotes()	
		my $drop_prepended_locations_pattern = qr/^$location_prepend_str_pattern/;
			
		for my $location_quoted_key (sort keys %newLocationsDraft) {
			my %newLocationProps = map { /$hash_val_pattern/gs; } $newLocationsDraft{$location_quoted_key};
			# %newLocationProps keys are not quoted; values are quoted:
			for my $props_key (keys %newLocationProps) {
				$newLocationProps{$props_key} = stripQuotes($newLocationProps{$props_key});
			}
			# make key unquoted
			my $location_key = stripQuotes($location_quoted_key);
			# drop the prepended '/Locations/'
			$location_key =~ s/$drop_prepended_locations_pattern//;
			# format $location_key correctly
			$location_key = forwardSlashToChar($location_key, '-');
			
			# validate mandatory fields early:
			# validate locationName
			my $locationName = $location_key; # $newLocationProps{setTitle} // $location_key;
			my $validPopulatedLocationName = validPopulatedParameter($locationName);
			if (!$validPopulatedLocationName) {
				die "ERROR: Invalid location name \"$locationName\". Exiting ...\n";
			}
			# done validating: set locationName as key and value as \%newLocationProps
			$newLocations{$locationName} = \%newLocationProps;
		}
	}
	print "  done in ".$t->deltaTime() ."\n\n";

	print $t->markTime(). " Importing Locations into NMIS\n";
	my $sum = initSummary();
	{
		foreach my $locationkey (sort keys %newLocations)
		{
			++$sum->{total};
			my $action;
			if ( $LT->{$locationkey}{Geocode} ne "" ) {
				++$sum->{update};
				$action = "UPDATE";
			}
			else {
				++$sum->{add};
				$action = "ADDING";
			}

			my %thisLocation = %{ $newLocations{$locationkey} };
			$LT->{$locationkey}{Geocode} = $thisLocation{setAddress};

			# print all data entered if verbose
			if ($verbose) {
				print "$action: Geocode='$LT->{$locationkey}{Geocode}'"
					  ."'\n";
			 }
		}
	}
	print "  done in ".$t->deltaTime() ."\n\n";

	$res .= "$sum->{total} locations processed\n"
		  . "$sum->{add} locations added\n"
		  . "$sum->{update} locations updated\n\n";

	if ($sum->{total} != $expected_location_count) {
		die "ERROR: locations processed \"$sum->{total}\" <> expected location count \"$expected_location_count\". Exiting ...\n";
	}

	if ( $nmislocations ne "" ) {
		if ( not -f $nmislocations ) {
			writeHashtoFile(file => $nmislocations, data => $LT);
			$res .= "New locations imported into \"$nmislocations\", check the file and copy over existing NMIS Locations file\n";
			$res .= "cp $nmislocations /usr/local/nmis8/conf/Locations.nmis\n";
		}
		elsif ( -r $nmislocations and $overwrite ) {
			mybackupFile(file => $nmislocations, backup => "$nmislocations.backup");
			writeHashtoFile(file => $nmislocations, data => $LT);
			$res .= "New locations imported into \"$nmislocations\", check the file and copy over existing NMIS Locations file\n";
			$res .= "cp $nmislocations /usr/local/nmis8/conf/Locations.nmis\n";
		}
		else {
			$res .= "ERROR: locations file \"$nmislocations\" already exists\n";
		}
	}
	else {
		$res .= "ERROR: no locations file to save to provided\n";
	}
	return $res."\n\n";
}

sub loadCustomers {
	my $file_content = shift;
	my $nmiscustomers = shift;
	
	my $res;

	print $t->markTime(). " Loading the Local Customers List\n";
	my $CT = loadGenericTable('Customers');
	print "  done in ".$t->deltaTime() ."\n\n";

	print $t->markTime(). " Loading the Import Customers from zenbatchdumpfile. " . CONST_PATIENCE . "\n";
	my $expected_customer_count = 0;
	my %newCustomers;
	{
		# strictly no capturing within these compiled regexes: use (?:pattern) to group without capture
		# customers always start with '/Groups/'
		my $customer_prepend_str_pattern = qr/\/Groups\//;
		# this pattern is expensive but it works, accurateley extracting the first quoted string on the relevant line
		my $quoted_customer_pattern = qr/(?:'$customer_prepend_str_pattern(?:(?:'')*[^']*)*')|(?:"$customer_prepend_str_pattern(?:(?:"")*[^"]*)*")/;
		# options are:
		# setAddress: count=289
		# setTitle: count=98
		my $customer_expected_prop_pattern = $any_chars_ungreedy_pattern;
		my $draft_hash_val_pattern = qr/\s+
									  $any_chars_ungreedy_pattern
									  $customer_expected_prop_pattern
									  $any_chars_ungreedy_pattern/x; # /x allows regex over multiple lines
		undef $customer_expected_prop_pattern;
								  
		# capture customers key and value with (...)(...) in this regex:
		# get each block of text containing $customer_expected_prop_pattern and split to quoted_key and value,
		my %newCustomersDraft = map { /$rec_delimiter
									   ($quoted_customer_pattern)
									   ($draft_hash_val_pattern)
									   $rec_delimiter
									  /gsx } $file_content; # /x allows regex over multiple lines

		$expected_customer_count = scalar (keys %newCustomersDraft);
		my $unique_customer_count = scalar (Array::Utils::unique(keys %newCustomersDraft));
		if ($unique_customer_count != $expected_customer_count) {
			die "ERROR: unique customer count \"$unique_customer_count\" <> expected customer count \"$expected_customer_count\". Exiting ...\n";
		}

		# capture key and value with (...)=(...) in this regex:
		# regex to split each %newCustomersDraft value into its constituent key and value properties
		my $hash_val_pattern = qr/\s+(.*?)=($quoted_any_chars_pattern)/; # /x allows regex over multiple lines
		# split each %newCustomersDraft value into its constituent key and value properties
		# then populate %newCustomers with key=hash of properties
		# %newCustomersDraft customer keys are quoted.
		# we sort since we die on errors here and we want this to be a consistent procedure:
		
		# this pattern will be applied after stripQuotes()	
		my $drop_prepended_customers_pattern = qr/^$customer_prepend_str_pattern/;
			
		for my $customer_quoted_key (sort keys %newCustomersDraft) {
			my %newCustomerProps = map { /$hash_val_pattern/gs; } $newCustomersDraft{$customer_quoted_key};
			# %newCustomerProps keys are not quoted; values are quoted:
			for my $props_key (keys %newCustomerProps) {
				$newCustomerProps{$props_key} = stripQuotes($newCustomerProps{$props_key});
			}
			# make key unquoted
			my $customer_key = stripQuotes($customer_quoted_key);
			# drop the prepended '/Groups/'
			$customer_key =~ s/$drop_prepended_customers_pattern//;
			# format $customer_key correctly
			$customer_key = forwardSlashToChar($customer_key, '-');
			
			# validate mandatory fields early:
			# validate customerName
			my $customerName = $customer_key; # $newNodeProps{setTitle} // $customer_key;
			my $validPopulatedCustomerName = validPopulatedParameter($customerName);
			if (!$validPopulatedCustomerName) {
				die "ERROR: Invalid customer name \"$customerName\". Exiting ...\n";
			}
			# done validating: set customerName as key and value as \%newCustomerProps
			$newCustomers{$customerName} = \%newCustomerProps;
		}
	}
	print "  done in ".$t->deltaTime() ."\n\n";

	print $t->markTime(). " Importing Customers into NMIS\n";
	my $sum = initSummary();
	{
		foreach my $customerkey (sort keys %newCustomers)
		{
			++$sum->{total};
			my $action;
			if ( $CT->{$customerkey}{Geocode} ne "" ) {
				++$sum->{update};
				$action = "UPDATE";
			}
			else {
				++$sum->{add};
				$action = "ADDING";
			}

			my %thisCustomer = %{ $newCustomers{$customerkey} };
			$CT->{$customerkey}{customer} = $customerkey;
			if ($thisCustomer{description})
			{
				$CT->{$customerkey}{description} = $thisCustomer{description};
			}

			# print all data entered if verbose
			if ($verbose) {
				print "$action: customer='$CT->{$customerkey}{customer}'"
				      .(($thisCustomer{description})? "; description='$CT->{$customerkey}{description}'": "")
					  ."'\n";
			 }
		}
	}
	print "  done in ".$t->deltaTime() ."\n\n";

	$res .= "$sum->{total} customers processed\n"
	        . "$sum->{add} customers added\n"
		    . "$sum->{update} customers updated\n\n";

	if ($sum->{total} != $expected_customer_count) {
		die "ERROR: customers processed \"$sum->{total}\" <> expected customer count \"$expected_customer_count\". Exiting ...\n";
	}

	if ( $nmiscustomers ne "" ) {
		if ( not -f $nmiscustomers ) {
			writeHashtoFile(file => $nmiscustomers, data => $CT);
			$res .= "New customers imported into \"$nmiscustomers\", check the file and copy over existing NMIS Customers file\n";
			$res .= "cp $nmiscustomers /usr/local/nmis8/conf/Nodes.nmis\n";
		}
		elsif ( -r $nmiscustomers and $overwrite ) {
			mybackupFile(file => $nmiscustomers, backup => "$nmiscustomers.backup");
			writeHashtoFile(file => $nmiscustomers, data => $CT);
			$res .= "New customers imported into \"$nmiscustomers\", check the file and copy over existing NMIS Nodes file\n";
			$res .= "cp $nmiscustomers /usr/local/nmis8/conf/Nodes.nmis\n";
		}
		else {
			$res .= "ERROR: customers file \"$nmiscustomers\" already exists\n";
		}
	}
	else {
		$res .= "ERROR: no customers file to save to provided\n";
	}
	return $res."\n\n";
}

sub loadNodes {
	my $file_content = shift;
	my $nmisnodes = shift;

	my $res;

	print $t->markTime(). " Loading the Local Node List\n";
	my $LNT = loadLocalNodeTable();
	print "  done in ".$t->deltaTime() ."\n\n";

	print $t->markTime(). " Loading the Import Nodes from zenbatchdumpfile. " . CONST_PATIENCE . "\n";
	my $expected_node_count = 0;
	my %newNodes;
	# strictly no capturing within these compiled regexes: use (?:pattern) to group without capture
	my $ipv4_pattern = qr/(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)/;
	{
		# strictly no capturing within these compiled regexes: use (?:pattern) to group without capture		
		my $quoted_ipv4_pattern = qr/(?:'$ipv4_pattern')|(?:"$ipv4_pattern")/;

		my $node_expected_prop = CONST_NODE_EXPECTED_PROP;
		my $node_expected_prop_pattern = qr/$node_expected_prop=$quoted_any_chars_pattern/;
		my $draft_hash_val_pattern = qr/\s+
									  $any_chars_ungreedy_pattern
									  $node_expected_prop_pattern
									  $any_chars_ungreedy_pattern/x; # /x allows regex over multiple lines
		undef $node_expected_prop_pattern;

		# count how many ipv4 keys start on lines to get an expected node count
		my @ipv4_keys = map { /$rec_delimiter
						       ($quoted_ipv4_pattern)
							  /gsx } $file_content;		

		$expected_node_count = scalar @ipv4_keys;
		my $expected_unique_node_count = scalar (Array::Utils::unique(@ipv4_keys));
		if ($expected_unique_node_count != $expected_node_count) {
			die "ERROR: expected unique node count \"$expected_unique_node_count\" <> expected node count \"$expected_node_count\". Exiting ...\n";
		}

		# capture key and value with (...)(...) in this regex:
		# get each block of text containing $node_expected_prop_pattern and split to quoted_key and value,
		# quoted key being quoted ipv4 address
		my %newNodesDraft = map { /$rec_delimiter
								   ($quoted_ipv4_pattern)
								   ($draft_hash_val_pattern)
								   $rec_delimiter
								  /gsx } $file_content; # /x allows regex over multiple lines

		my $node_count = scalar (keys %newNodesDraft);
		my $unique_node_count = scalar (Array::Utils::unique(keys %newNodesDraft));
		if ($unique_node_count != $node_count) {
			die "ERROR: unique node count \"$unique_node_count\" <> node count \"$node_count\". Exiting ...\n";
		}

		if ($node_count != $expected_node_count) {
			# symmetric difference
			my @array = (keys %newNodesDraft);
			my @diff = sort(Array::Utils::array_diff( @array, @ipv4_keys ));
			die "ERROR: node count \"$node_count\" <> expected node count \"$expected_node_count\":\n".Dumper(\@diff)."\n.Exiting ...\n";
		}
		undef @ipv4_keys;
		
		# handle floating point numbers including exponents
		my $numeric_val_pattern = qr/[-+]?[0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?/;
		# [a-zA-Z0-9_-] chars preceding, then including and between braces 
		my $braces_val_pattern = qr/\w*?{$any_chars_ungreedy_pattern}/;
		# [a-zA-Z0-9_-] chars preceding, then including and between parenthesis escaping '(' and ')'
		my $parenthesis_val_pattern = qr/\w*?\($any_chars_ungreedy_pattern\)/;
		# [a-zA-Z0-9_-] chars preceding, then including and between square brackets escaping '[' and ']'
		my $squarebracket_val_pattern = qr/\w*?\[$any_chars_ungreedy_pattern\]/;

		# capture key and value with (...)=(...) in this regex:
		# regex to split each %newNodesDraft value into its constituent key and value properties
		my $hash_val_pattern = qr/\s+(.*?)=($braces_val_pattern|
											$parenthesis_val_pattern|
											$squarebracket_val_pattern|
											$quoted_any_chars_pattern|
											$numeric_val_pattern)/x; # /x allows regex over multiple lines
		# split each %newNodesDraft value into its constituent key and value properties
		# then populate %newNodes with key=hash of properties
		# %newNodesDraft ipv4 keys are quoted.
		# we sort since we die on errors here and we want this to be a consistent procedure:
		
		my $default_nodename_chars = "a-zA-Z0-9_. -";
		my $nodenamerule = $C->{node_name_rule} // qr/^[$default_nodename_chars]+$/;
		my $nodename_replacechars_pattern = qr/[^$default_nodename_chars]/;

		# pattern to extract quoted elements from list which is a string as in ['...',"..."]: we remove the '[' and ']' before regex
		my $liststr_extract_pattern = qr/(?:,|^)((?:'(?:(?:'')*[^']*)*')|(?:"(?:(?:"")*[^"]*)*"))/;
		
		for my $ipv4_quoted_key (sort keys %newNodesDraft) {
			my %newNodeProps = map { /$hash_val_pattern/gs; } $newNodesDraft{$ipv4_quoted_key};
			# %newNodeProps keys are not quoted; values are sometimes quoted:
			for my $props_key (keys %newNodeProps) {
				$newNodeProps{$props_key} = stripQuotes($newNodeProps{$props_key});
			}
			# make key unquoted
			my $ipv4_key = stripQuotes($ipv4_quoted_key);
			# make absolutely sure we have an unquoted and valid ip address
			# here we need to compare against complete ipv4 string, hence ^...$
			if ($ipv4_key !~ /^$ipv4_pattern$/) {
				die "ERROR: \"$ipv4_key\" is not a valid ipv4 address: See entry $ipv4_quoted_key $newNodesDraft{$ipv4_quoted_key}. Exiting ...\n";
			}
			# validate mandatory fields early:
			# validate nodeName
			my $nodeName = $newNodeProps{setTitle};
			my $validPopulatedNodeName = validPopulatedParameter($nodeName);
			if (($nodeName !~ $nodenamerule) or !$validPopulatedNodeName) {
				# fix where possible and where 'fixNames' param set to true:
				if ($validPopulatedNodeName and $fixNames)
				{
					my $new_nodeName = $nodeName;
					$new_nodeName =~ s/$nodename_replacechars_pattern/-/g;
					if ($new_nodeName =~ $nodenamerule) {
						print "INFO: Invalid node name \"$nodeName\" corrected to \"$new_nodeName\"\n";
						$nodeName = $new_nodeName;
					}
					else {
						die "ERROR: Invalid node name \"$new_nodeName\" after attempting to repair node name \"$nodeName\". Exiting ...\n";
					}
				}
				else {
					die "ERROR: Invalid node name \"$nodeName\". There is an option \"fixNames=1\" which attempts to repair node name by replacing unwanted characters with '-' character. Exiting ...\n";
				}
			}
			# validate host
			my $host = $newNodeProps{setManageIp};
			if ($host !~ /^$ipv4_pattern$/) {
				die "ERROR: \"$host\" is not a valid ipv4 address: See entry $ipv4_quoted_key $newNodesDraft{$ipv4_quoted_key}. Exiting ...\n";
			}
			# format location:
			$newNodeProps{setLocation} = forwardSlashToChar(stripForwardSlashAsFirstChar($newNodeProps{setLocation}),'-');
			# extract groups from ListString into Array:
			if (validPopulatedParameter($newNodeProps{setGroups})) {
				my $groups = $newNodeProps{setGroups};
				# pattern to extract quoted elements from list which is a string as in ['...','...']: we remove the '[' and ']' before regex
				my @extracted_groups = map { /$liststr_extract_pattern/gs } stripQuotesUsingFirstLastChars($groups,'[',']');
				if (scalar @extracted_groups >= 1) {
					# clean the groups strings:
					for my $i (0 .. $#extracted_groups) {
						$extracted_groups[$i] = forwardSlashToChar(stripForwardSlashAsFirstChar(stripQuotes($extracted_groups[$i])),'-');
					}
					if (scalar @extracted_groups > 1) {
						print "INFO: setGroups \"$newNodeProps{setGroups}\" contains more than one element. Last element \"$extracted_groups[-1]\" will be used: See entry $ipv4_quoted_key\n";
					}
					$newNodeProps{setGroups} = \@extracted_groups;
				}
				else {
					die "ERROR: Groups could not be extracted from \"setGroups\" value \"$newNodeProps{setGroups}\": See entry $ipv4_quoted_key. Exiting ...\n";
				}
			}
			# general info:
			if ($host ne $ipv4_key) {
				print "INFO: setManageIp (NMIS8 'host' field) \"$host\" not same as node key $ipv4_quoted_key\n";
			}
			# done validating: set nodeName as key and value as \%newNodeProps
			$newNodes{$nodeName} = \%newNodeProps;
		}
	}
	print "  done in ".$t->deltaTime() ."\n\n";

	print $t->markTime(). " Importing Nodes into NMIS\n";
	my $sum = initSummary();
	{
		# nodeName is $nodekey: we have validated this early
		foreach my $nodekey (sort keys %newNodes)
		{
			++$sum->{total};
			my $action;
			if ( $LNT->{$nodekey}{name} ne "" ) {
				++$sum->{update};
				$action = "UPDATE";
			}
			else {
				++$sum->{add};
				$action = "ADDING";
			}

			my %thisNode = %{ $newNodes{$nodekey} };

			# host
			my $host = $thisNode{setManageIp};
			# snmpVersion and community
			# when zSnmpVer='v3', we 'should not' have a community string and we should have snmp v3 authentication porpoerties
			my $community = $thisNode{zSnmpCommunity};
			#my $setSnmpEngineId = $thisNode{setSnmpEngineId};
			#my $setSnmpV3EngineId = $thisNode{setSnmpV3EngineId};
			my $zSnmpAuthType = $thisNode{zSnmpAuthType};
			my $zSnmpAuthPassword = $thisNode{zSnmpAuthPassword};
			my $zSnmpPrivType = $thisNode{zSnmpPrivType};
			my $zSnmpPrivPassword = $thisNode{zSnmpPrivPassword};
			my $zSnmpSecurityName = $thisNode{zSnmpSecurityName};
	
			my $is_V3_snmp = ($thisNode{zSnmpVer} eq "v3");
			# nmis expects 'snmp' prepended to the values passed in $thisNode{zSnmpVer}
			my $snmpVer = $thisNode{zSnmpVer};
			if (substr($snmpVer, 0, 3) ne "snmp")
			{
				$snmpVer = $snmpVer? "snmp".$snmpVer: "";
			}
			my $snmp3_valid = $is_V3_snmp? (validPopulatedParameter($zSnmpAuthType)
											and validPopulatedParameter($zSnmpAuthPassword)
											and validPopulatedParameter($zSnmpPrivType)
											and validPopulatedParameter($zSnmpPrivPassword)
											and validPopulatedParameter($zSnmpSecurityName)) : 0;
			my $snmp_valid = !$is_V3_snmp? (validPopulatedParameter($community)) : 0;
			
			# invalid snmp authentication: set $collect = "false"
			my $collect;
			if (!$snmp3_valid and !$snmp_valid)
			{
				$collect = "false";
			}
			
			my $group;
			if (defined $defined_group) {
				$group = $defined_group;
			}
			else {
				# we have converted to array during parsing above:
				if (ref($group) eq "ARRAY") {
					$group = $thisNode{setGroups}[-1];
				}
			}

			my $roleType = $defined_role;
			###$roleType = $thisNode{roleType} if $thisNode{roleType};
	
			my $netType = $thisNode{net} // "lan";
			$netType = $thisNode{netType} if $thisNode{netType};
	
			# strategy here is to leave the unsupported hash keys in this dump
			# in place as placeholder and to then set a default value:
			$LNT->{$nodekey}{name} = $nodekey;
			$LNT->{$nodekey}{host} = $host // $thisNode{name};
			$LNT->{$nodekey}{group} = $group // "NMIS8";
			$LNT->{$nodekey}{roleType} = $roleType // CONST_NODE_ROLE_DEFAULT;
			
			# we populate whatever snmp auth details we are given, whether valid or not:
			# snmp prior to "snmpv3"
			$LNT->{$nodekey}{community} = $community // ""; # for this dumpfile we prefer "" over "public";
			# snmp from "snmpv3"
			$LNT->{$nodekey}{authprotocol} = $zSnmpAuthType // "";
			$LNT->{$nodekey}{authpassword} = $zSnmpAuthPassword // "";
			$LNT->{$nodekey}{privprotocol} = $zSnmpPrivType // "";
			$LNT->{$nodekey}{privpassword} = $zSnmpPrivPassword // "";
			$LNT->{$nodekey}{username} = $zSnmpSecurityName // "";
	
			$LNT->{$nodekey}{businessService} = $thisNode{businessService} // "";
			$LNT->{$nodekey}{serviceStatus} = $thisNode{serviceStatus} // "Production";
			$LNT->{$nodekey}{location} = $thisNode{setLocation} // "default";
	
			$LNT->{$nodekey}{active} = $thisNode{active} // "true";
			$LNT->{$nodekey}{collect} =  $thisNode{collect} || $collect // "true";
			$LNT->{$nodekey}{netType} = $thisNode{net} // "lan";
			$LNT->{$nodekey}{depend} = $thisNode{depend} // "N/A";
			$LNT->{$nodekey}{threshold} = $thisNode{threshold} // "true";
			$LNT->{$nodekey}{ping} = $thisNode{ping} // "true";
			$LNT->{$nodekey}{port} = $thisNode{port} // "161";
			$LNT->{$nodekey}{cbqos} = $thisNode{cbqos} // "none";
			$LNT->{$nodekey}{calls} = $thisNode{calls} // "false";
			$LNT->{$nodekey}{rancid} = $thisNode{rancid} // "false";
			$LNT->{$nodekey}{services} = $thisNode{services} // undef;
			$LNT->{$nodekey}{webserver} = $thisNode{webserver} // "false" ;
			$LNT->{$nodekey}{model} = $thisNode{model} // "automatic";
			$LNT->{$nodekey}{version} = $snmpVer // "snmpv2c";
			$LNT->{$nodekey}{timezone} = $thisNode{timezone} // 0 ;
			# custom fields - we don't want to be creating an unnecessary key=value
			# we have converted to array during parsing above:
			if ($customer_is_imported_group
				and validPopulatedParameter($thisNode{setGroups})
				and ref($thisNode{setGroups}) eq "ARRAY") {
					$LNT->{$nodekey}{customer} = $thisNode{setGroups}[-1];
			}
			if (validPopulatedParameter($thisNode{setHWTag})) {
				$LNT->{$nodekey}{hwtag} = $thisNode{setHWTag};
			}

			# print all data entered if verbose
			if ($verbose) {
				print "$action: node='$nodekey'"
					  ."; host='$LNT->{$nodekey}{host}'"
					  ."; group='$LNT->{$nodekey}{group}'"
					  ."; role='$LNT->{$nodekey}{roleType}'"
					  ."; community='$LNT->{$nodekey}{community}'"
					  ."; authprotocol='$LNT->{$nodekey}{authprotocol}'"
					  ."; authpassword='$LNT->{$nodekey}{authpassword}'"
					  ."; privprotocol='$LNT->{$nodekey}{privprotocol}'"
					  ."; privpassword='$LNT->{$nodekey}{privpassword}'"
					  ."; usernasme='$LNT->{$nodekey}{username}'"
					  ."; businessService='$LNT->{$nodekey}{businessService}'"
					  ."; serviceStatus='$LNT->{$nodekey}{serviceStatus}'"
					  ."; location='$LNT->{$nodekey}{location}'"
					  ."; active='$LNT->{$nodekey}{active}'"
					  ."; collext='$LNT->{$nodekey}{collect}'"
					  ."; netType='$LNT->{$nodekey}{netType}'"
					  ."; depend='$LNT->{$nodekey}{depend}'"
					  ."; threshold='$LNT->{$nodekey}{threshold}'"
					  ."; ping='$LNT->{$nodekey}{ping}'"
					  ."; port='$LNT->{$nodekey}{port}'"
					  ."; cbqos='$LNT->{$nodekey}{cbqos}'"
					  ."; calls='$LNT->{$nodekey}{calls}'"
					  ."; rancid='$LNT->{$nodekey}{rancid}'"
					  ."; services='$LNT->{$nodekey}{services}'"
					  ."; webserver='$LNT->{$nodekey}{webserver}'"
					  ."; model='$LNT->{$nodekey}{model}'"
					  ."; version='$LNT->{$nodekey}{version}'"
					  ."; timezone='$LNT->{$nodekey}{timezone}'"
					  .(($customer_is_imported_group
						 and validPopulatedParameter($thisNode{setGroups})
						 and ref($thisNode{setGroups}) eq "ARRAY")?
								"; customer='$LNT->{$nodekey}{customer}'": "")
					  .((validPopulatedParameter($thisNode{setHWTag}))?
								"; hwtag='$LNT->{$nodekey}{hwtag}'": "")
					  ."\n";
			}
		}
	}
	print "  done in ".$t->deltaTime() ."\n\n";

	$res .= "$sum->{total} nodes processed\n"
		    . "$sum->{add} nodes added\n"
		    . "$sum->{update} nodes updated\n\n";

	if ($sum->{total} != $expected_node_count) {
		die "ERROR: nodes processed \"$sum->{total}\" <> expected node count \"$expected_node_count\". Exiting ...\n";
	}

	if ( $nmisnodes ne "" ) {
		if ( not -f $nmisnodes ) {
			writeHashtoFile(file => $nmisnodes, data => $LNT);
			$res .= "New nodes imported into \"$nmisnodes\", check the file and copy over existing NMIS Nodes file\n";
			$res .= "cp $nmisnodes /usr/local/nmis8/conf/Nodes.nmis\n";
		}
		elsif ( -r $nmisnodes and $overwrite ) {
			mybackupFile(file => $nmisnodes, backup => "$nmisnodes.backup");
			writeHashtoFile(file => $nmisnodes, data => $LNT);
			$res .= "New nodes imported into \"$nmisnodes\", check the file and copy over existing NMIS Nodes file\n";
			$res .= "cp $nmisnodes /usr/local/nmis8/conf/Nodes.nmis\n";
		}
		else {
			$res .= "ERROR: nodes file \"$nmisnodes\" already exists\n";
		}
	}
	else {
		$res .= "ERROR: no nodes file to save to provided\n";
	}
	return $res."\n\n";
}

sub initSummary {
	my $sum;

	$sum->{add} = 0;
	$sum->{update} = 0;
	$sum->{total} = 0;

	return $sum;
}

sub getBackupFilename {
	my $file = shift;
	
	my $fname = $file;
	my $i = 0;
	for (;;) {
		last unless -f $fname;
		$i++;
		$fname = "${file}$i";
	}
	return $fname;
}

sub mybackupFile {
	my %arg = @_;
	my $buff;
	my $backupfile = getBackupFilename($arg{backup});
	if ( not -f $backupfile ) {
		if ( -r $arg{file} ) {
			open(IN,$arg{file}) or warn ("ERROR: problem with file $arg{file}; $!");
			open(OUT,">$backupfile") or warn ("ERROR: problem with file $backupfile; $!");
			binmode(IN);
			binmode(OUT);
			while (read(IN, $buff, 8 * 2**10)) {
			    print OUT $buff;
			}
			close(IN);
			close(OUT);
			return 1;
		} else {
			print STDERR "ERROR: mybackupFile file $arg{file} not readable.\n";
			close(OUT);
			return 0;
		}
	}
	else {
		print STDERR "ERROR: backup target $backupfile already exists.\n";
		return 0;
	}
}

sub myLoadFile {
	my $file = shift;
	my $file_content;
	if (sysopen(DATAFILE, "$file", O_RDONLY)) {
		flock(DATAFILE, LOCK_SH) or warn "can't lock filename: $!";
		read DATAFILE, $file_content, -s DATAFILE;
		close (DATAFILE) or warn "can't close filename: $!";
	} else {
		logMsg("cannot open file $file, $!");
	}
	return ($file_content);
}
