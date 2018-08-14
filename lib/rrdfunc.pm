#
#  Copyright (C) Opmantek Limited (www.opmantek.com)
#
#  ALL CODE MODIFICATIONS MUST BE SENT TO CODE@OPMANTEK.COM
#
#  This file is part of Network Management Information System (“NMIS”).
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
package rrdfunc;
our $VERSION = "3.0.0";

use NMIS::uselib;
use lib "$NMIS::uselib::rrdtool_lib";

use strict;

use vars qw(@ISA @EXPORT);

use Exporter;

use RRDs 1.000.490;
use Statistics::Lite;
use POSIX qw();									# for strftime
use List::Util 1.33;

use func;
use Sys;

@ISA = qw(Exporter);

@EXPORT = qw(
		getUpdateStats
    getRRDerror
		getRRDasHash
		getRRDStats
		addDStoRRD
		updateRRD
		createRRD
	);


# rough stats of what the module has done,
# including last error - fixme: this is module-level, not instance-level!
my %stats;
sub getRRDerror
{
	return $stats{error};
}

sub getUpdateStats
{
	my %pruned;
	# don't include the nodes, just their number
	map { $pruned{$_} = $stats{$_}; } (grep($_ ne "nodes", keys %stats));
	$pruned{nodecount} = keys %{$stats{nodes}};
	return \%pruned;
}

# returns the rrd data for a given rrd type as a hash
# this uses the Sys object to translate between graphtype and rrd section (Sys::getTypeName)
#
# args: sys, graphtype, mode (all required),
# index or item (synthesised from one another),
# mode (required, AVERAGE,MIN,MAX or LAST)
# optional: hours_from and hours_to (default: no restriction),
# optional: resolution (default: highest resolution that rrd can provide),
# optional: add_minmax (default: unset, if set AND if resolution is set,
#  then <ds>_min and <ds>_max are added for each bucket)
#
# returns: hash of time->dsname=value, list(ref) of dsnames (plus 'time', 'date'), and meta data hash
# metadata hash: actual begin, end, step as per rrd, error if necessary, rows (=count), rows_with_data
sub getRRDasHash
{
	my %args = @_;
	my $S = $args{sys};
	my $graphtype = $args{graphtype};
	my $index = $args{index};
	my $item = $args{item};

	my $minhr = (defined $args{hour_from}? $args{hour_from} : 0);
	my $maxhr = (defined $args{hour_to}? $args{hour_to} :  24) ;
	my $mustcheckhours = ($minhr != 0  and $maxhr != 24);
	my $invertperiod = $minhr > $maxhr;
	my $wantedresolution = $args{resolution};

	if (!$S) {
		$S = Sys::->new(); # get base Model containing database info
		$S->init;
	}
	# let sys reason through graphtype/sections, and index vs item
	my $db = $S->getDBName(graphtype=>$graphtype, index=>$index, item=>$item);

	my @rrdargs = ($db, $args{mode});
	my ($bucketsize, $resolution);
	if (defined($wantedresolution) && $wantedresolution > 0)
	{
		# rrdfetch selects resolutions only from existing RRAs (no multiples),
		# so we need to determine what native resolutions are available,
		# look for equality or fall back to the smallest/best/step,
		# post-process into buckets of the desired size...
		my ($error, @available) = getRRDResolutions($db, $args{mode});
		return ({},[], { error => $error }) if ($error);

		# this can work if the desired resolution is directly equal to an RRA period,
		# or if the step divides the desired resolution cleanly
		# HOWEVER, if add_minmax is requested the we must do our own bucketising as rrd likely won't have MIN and MAX rras!
		if (grep($_ == $wantedresolution, @available) && !$args{add_minmax})
		{
			$resolution = $wantedresolution;
		}
		elsif ( $wantedresolution % $available[0] == 0)
		{
			# we must bucketise ourselves
			$bucketsize = $wantedresolution / $available[0];
			$resolution = $available[0];
		}
		else
		{
			return ({},[], { error => "Summarisation with resolution $wantedresolution not possible, available RRD resolutions: "
													 .join(", ",@available) });
		}

		push @rrdargs, ("--resolution",$resolution);
		$args{start} = $args{start} - $args{start} % $resolution;
		$args{end} = $args{end} - $args{end} % $resolution;
	}
	push @rrdargs, ("--start",$args{start},"--end",$args{end});

	my ($begin,$step,$name,$data) = RRDs::fetch(@rrdargs);

	# bail out if we ask for resolution X but get back (bigger) step Y
	# and cannot recompute the bucket size
	if (defined($bucketsize) && $resolution != $step)
	{
		if ($wantedresolution % $step == 0) # step we got back is divisible into buckets of desired size
		{
			$bucketsize = $wantedresolution / $step;
		}
		else
		{
			return ({}, [], {
				error => "Summarisation with resolution $wantedresolution not possible, RRD only provides resolution $step for requested time interval! " });
		}
	}

	my @dsnames = @$name if (defined $name);
	my %s;
	my $time = $begin;
	my $rowswithdata;

	# loop over the readings over time
	for(my $row = 0; $row <= $#{$data}; ++$row, $time += $step)
	{
		my $thisrow = $data->[$row];
		my $datapresent;
		# loop over the datasets per individual reading
		for(my $dsidx = 0; $dsidx <= $#{$thisrow}; ++$dsidx)
		{
			$s{$time}->{ $dsnames[$dsidx] } = $thisrow->[$dsidx];
			$datapresent ||= 1 if (defined $thisrow->[$dsidx]);
		}

		# compute date only if at least on ds col has defined data
		if ($datapresent)
		{
			++$rowswithdata;
			my @timecomponents = localtime($time);
			my $hour = $timecomponents[2];
			if (!$mustcheckhours or
					(
					 # between from (incl) and to (excl) hour if not inverted
					 ( !$invertperiod and $hour >= $minhr and $hour < $maxhr )
					 or
					 # before to (excl) or after from (incl) hour if inverted,
					 ( $invertperiod and ($hour < $maxhr or $hour >= $minhr )) ))
			{
				$s{$time}->{time} = $time;
				# we DON'T want to rerun localtime() again, so no func::returnDateStamp()
				# want 24-Mar-2014 11:22:33, regardless of LC_*, so %b isn't good.
				my $mon=('Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec')[$timecomponents[4]];
				$s{$time}->{date} = POSIX::strftime("%d-$mon-%Y %H:%M:%S", @timecomponents);
			}
			else
			{
				delete $s{$time};				# out of specified hours
			}
		}
	}

	my %meta = ( step => $step, start => $begin, end => $time,
							 rows => scalar @$data, rows_with_data => $rowswithdata );
	# bucket post-processing needed?
	if ($bucketsize)
	{
		my $bucketstart = $meta{start} = $args{start}; # $begin can be one step interval later
		$meta{step} = $bucketsize * $step;

		my $nrdatapoints = @$data;
		my $nrbuckets = int($nrdatapoints/$bucketsize + 0.5); # last bucket may end up partially filled
		$meta{rows} = $meta{rows_with_data} = $nrbuckets;

		for my $bucket (1..$nrbuckets)
		{
			my $targettime = $bucketstart + $bucket * $wantedresolution;
			$meta{end} = $targettime;	# so that last bucket is included in meta

			my %acc;
			for my $slot (0..$bucketsize-1) # backwards
			{
				my $contribtime = $targettime - $slot*$step;
				next if (!exists $s{$contribtime}); # holes in the data are possible

				for my $ds (@dsnames)
				{
					$acc{$ds} ||= [];
					push @{$acc{$ds}}, $s{$contribtime}->{$ds};
				}
				delete $s{$contribtime} if ($slot); # last timeslot receives all the readings for the whole bucket
			}

			if (!keys %acc)	# all gone?
			{
				delete $s{$targettime};
				--$meta{rows_with_data};
			}
			else
			{
				for my $ds (@dsnames)
				{
					$s{$targettime}->{$ds} = Statistics::Lite::mean(@{$acc{$ds}});
					if ($args{add_minmax})
					{
						$s{$targettime}->{"${ds}_min"} = Statistics::Lite::min(@{$acc{$ds}});
						$s{$targettime}->{"${ds}_max"} = Statistics::Lite::max(@{$acc{$ds}});
					}
				}

				# last bucket may be partial and lack time or date
				if (!exists $s{$targettime}->{time})
				{
					$s{$targettime}->{time} = $targettime;
					my @timecomponents = localtime($targettime);
					# we DON'T want to rerun localtime() again, so no func::returnDateStamp()
					# want 24-Mar-2014 11:22:33, regardless of LC_*, so %b isn't good.
					my $mon=('Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec')[$timecomponents[4]];
					$s{$targettime}->{date} = POSIX::strftime("%d-$mon-%Y %H:%M:%S", @timecomponents);
				}
			}
		}

		# ditch trailing stuff
		map { delete $s{$_}; } (grep($_ > $meta{end}, keys %s));
		# reorganise the ds names to list ds, min, max,... in that order
		if ($args{add_minmax})
		{
			@dsnames = map { ($_, "${_}_min","${_}_max") } (@dsnames);
		}
	}

	# two artificial ds header cols - let's put them first
	unshift(@dsnames,"time","date");

	# actual data, the dsname list, and the meta data
	return (\%s, \@dsnames, \%meta);
}

# args: rrdfile (full path), mode (one of AVERAGE, MIN or MAX - LAST makes no sense here)
# returns: (undef, array of resolutions, seconds, ascending) or (error)
sub getRRDResolutions
{
	my ($rrdfile,$mode) = @_;
	my $info = RRDs::info($rrdfile);

	return "failed to retrieve RRD info: ".RRDs::error()
			if (ref($info) ne "HASH");

	my $basicstep = $info->{step};
	my (@others, $rrasection);
	for my $k (sort keys %$info)
	{
		if ($k =~ /^rra\[(\d+)\]\.cf$/)
		{
			next if ($info->{$k} ne $mode);
			$rrasection = $1;
		}
		elsif (defined($rrasection) && $k =~ /^rra\[$rrasection\]\.pdp_per_row$/)
		{
			push @others, $info->{$k};
			undef $rrasection;
		}
	}

	# return ascending
	return (undef, map { $basicstep * $_ } (sort { $a <=> $b } @others));
}

# retrieves rrd data and computes a number of descriptive stats
# this uses the sys object to translate from graphtype to section (Sys::getTypeName)
#
# args: sys, graphtype (required),
# index or item (synthesisted from each other),
# hour_from hour_to define the daily period [from,to].
#
# if from > to then the meaning is inverted and data OUTSIDE the [to,from] interval is returned
# for midnight use either 0 or 24, depending on whether you want the inside or outside interval
#
# optional argument: truncate (defaults to 3), if >0 then results are reformatted as %.NNNf
# if -1 then untruncated values are returned.
#
# stats also include the ds's values, as an ordered list under the 'values' key,
# but NOT the original timestamps (relevant if filtered with hour_from/to)!
#
# returns: hashref of the stats
sub getRRDStats
{
	my %args = @_;
	my $S = $args{sys};
	my $graphtype = $args{graphtype};
	my $index = $args{index};
	my $item = $args{item};
	my $wanttruncate = (defined $args{truncate})? $args{truncate}: 3;

	my $minhr = (defined $args{hour_from}? $args{hour_from} : 0);
	my $maxhr = (defined $args{hour_to}? $args{hour_to} :  24) ;

	my $invertperiod = $minhr > $maxhr;

	if (!$S) {
		$S = Sys::->new(); # get base Model containing database info
		$S->init;
	}

	# let sys reason through graphtype/sections, and index vs item
	my $db = $S->getDBName(graphtype=>$graphtype, index=>$index, item=>$item);

	if ( ! defined $args{mode} ) { $args{mode} = "AVERAGE"; }
	if ( -r $db ) {
		my ($begin,$step,$name,$data) = RRDs::fetch($db,$args{mode},"--start",$args{start},"--end",$args{end});
		my %s;
		my $time = $begin;
		for(my $a = 0; $a <= $#{$data}; ++$a) {
			my @timecomponents = localtime($time);
			my $hour = $timecomponents[2];
			for(my $b = 0; $b <= $#{$data->[$a]}; ++$b)
			{
					if ( defined $data->[$a][$b]
							 and
							 (
								 # between from (incl) and to (excl) hour if not inverted
								 ( !$invertperiod and $hour >= $minhr and $hour < $maxhr )
								 or
								 # before to (excl) or after from (incl) hour if inverted,
								 ( $invertperiod and ($hour < $maxhr or $hour >= $minhr )) ))
					{
							push(@{$s{$name->[$b]}{values}},$data->[$a][$b]);
					}
			}
			$time = $time + $step;
		}

		foreach my $m (sort keys %s)
		{
			my %statsinfo = Statistics::Lite::statshash(@{$s{$m}{values}});
			$s{$m}{count} = $statsinfo{count}; # count of records, NOT all data - see hours from/to filtering
			$s{$m}{step} = $step;
			for my $key (qw(mean min max median range sum variance stddev))
			{
				$s{$m}{$key} = $wanttruncate>=0 ? sprintf("%.${wanttruncate}f", $statsinfo{$key}) : $statsinfo{$key};
			}
		}
		return \%s;
	}
	else
	{
		$stats{error} = "RRD is not readable rrd=$db";
		logMsg("ERROR RRD is not readable rrd=$db");
		return undef;
	}
}

#
# add a DataSource to an existing RRD
# Cologne, dec 2004
# $rrd = filename of RRD, @ds = list of DS:name:type:hearthbeat:min:max
#
sub addDStoRRD
{
	my ($rrd, @ds) = @_ ;

	dbg("update $rrd with @ds");

	my $rrdtool = "rrdtool";
	if ($NMIS::kernel =~ /win32/i) {
		$rrdtool = "rrdtool.exe";
	}
	my $info = `$rrdtool`;
	if ($info eq "")
	{
		# $rrdtool = "/opt/local/bin/rrdtool"; # maybe this
		$rrdtool = "/usr/local/rrdtool/bin/rrdtool"; # maybe this
		$info = `$rrdtool`;
		if ($info eq "")
		{
			logMsg("ERROR, rrdtool not found");
			$stats{error} = "rrdtool not found";
			return;
		}
	}

	# version of rrdtool
	my $version = "10";
	if ($info =~ /.*RRDtool\s+(\d+)\.(\d+)\.(\d+).*/) {
		dbg("RRDtool version is $1.$2.$3");
		$version = "$1$2";
	}

	my $DSname;
	my $DSvalue;
	my $DSprep;

	# Get XML Output
	### Adding Mark Nagel's fix for quoting strings.
	my $qrrd = quotemeta($rrd);
	my $xml = `$rrdtool dump $qrrd`;

	#prepare inserts
	foreach my $ds (@ds) {
		if ( $ds =~ /^DS:([a-zA-Z0-9_]{1,19}):(\w+):(\d+):([\dU]+):([\dU]+)/) {
				# Variables
				my $dsName      = $1;
				my $dsType      = $2;
				my $dsHeartBeat = $3;
				my $dsMin       = $4 eq 'U' ? 'NaN' : $4;
				my $dsMax       = $5 eq 'U' ? 'NaN' : $5;

				if ( $dsType !~ /^(GAUGE|COUNTER|DERIVE|ABSOLUTE)$/ )
				{
					logMsg("ERROR, unknown DS type in $ds");
					$stats{error} = "unknown DS type in $ds";
					return undef;
				}
				if ($xml =~ /<name> $dsName </)
				{
					logMsg("DS $ds already in database $ds");
				}
				else
				{
				$DSname .= "	<ds>
			<name> $dsName </name>
			<type> $dsType </type>
			<minimal_heartbeat> $dsHeartBeat </minimal_heartbeat>
			<min> $dsMin </min>
			<max> $dsMax </max>

			<!-- PDP Status -->
			<last_ds> UNKN </last_ds>
			<value> 0.0000000000e+00 </value>
			<unknown_sec> 0 </unknown_sec>
		</ds>\n";

				$DSvalue = $DSvalue eq "" ? "<v> NaN " : "$DSvalue </v><v> NaN ";

				if ($version > 11) {
					$DSprep .= "
				 <ds>
				<primary_value> 0.0000000000e+00 </primary_value>
				<secondary_value> 0.0000000000e+00 </secondary_value>
				<value> NaN </value>  <unknown_datapoints> 0 </unknown_datapoints></ds>\n";
				} else {
					$DSprep .= "<ds><value> NaN </value>  <unknown_datapoints> 0 </unknown_datapoints></ds>\n";
				}
			}
		}
	}

	if ($DSname ne "" )
	{
		if ( $xml =~ /Round Robin Archives/ )
		{
			# check priv.
			if ( -w $rrd )
			{
		 		# Move the old source
	   			if (rename($rrd,$rrd.".bak"))
					{
						dbg("$rrd moved to $rrd.bak");
						if ( -e "$rrd.xml" ) {
							# from previous action
							unlink $rrd.".xml";
							dbg("$rrd.xml deleted (previous action)");
						}
						# update xml and rite output
						if (open(OUTF, ">$rrd.xml")) {
							foreach my $line (split(/\n/,$xml)) {
								if ( $line=~ /Round Robin Archives/ ) {
									print OUTF $DSname.$line;
								} elsif ($line =~ /^(.+?<row>)(.+?)(<\/row>.*)$/) {
									my @datasources_in_entry = split(/<\/v>/, $2);
									splice(@datasources_in_entry, 999, 0, "$DSvalue");
									my $new_line = join("</v>", @datasources_in_entry);
									print OUTF "$1$new_line</v>$3\n";
								} elsif ($line =~ /<\/cdp_prep>/) {
									print OUTF $DSprep.$line ;
								} else {
									print OUTF $line;
								}
							}
							close (OUTF);
							dbg("xml written to $rrd.xml");
							# Re-import
							RRDs::restore($rrd.".xml",$rrd);
							if (my $ERROR = RRDs::error())
							{
								logMsg("update ERROR database=$rrd: $ERROR");
								$stats{error} = "update database=$rrd: $ERROR";
							}
							else
							{
								dbg("$rrd created");
								setFileProt($rrd); # set file owner/permission, default: nmis, 0775
								unlink $rrd.".xml";
								dbg("$rrd.xml deleted");
								unlink $rrd.".bak";
								dbg("$rrd.bak deleted");
								logMsg("INFO DataSource @ds added to $rrd");
								return 1;
							}
						}
						else
						{
							logMsg("ERROR, could not open $rrd.xml for writing: $!");
							$stats{error} = "could not open $rrd.xml for writing: $!";
							rename($rrd.".bak",$rrd); # backup
						}
					}
					else
					{
						logMsg("ERROR, cannot rename $rrd: $!");
						$stats{error} = "cannot rename $rrd: $!";
					}
			}
			else
			{
				logMsg("ERROR, no write permission for $rrd: $!") ;
				$stats{error} = "no write permission for $rrd: $!";
			}
		}
		else
		{
			logMsg("ERROR, could not dump $rrd (maybe rrdtool missing)");
			$stats{error} = "could not dump $rrd (maybe rrdtool missing)";
		}
	}
}

# determine the rrd file name from the node's model, the common-database
# and the input parameters like name/type/item/index; also extras (optional),
# and nmis4 (optional, for backwards compat expansion)
#
# attention: this low-level function does NOT translate from graphtype instances to
# sections (e.g. graphtype cpu and many others is covered by nodehealth section),
# the caller must have made that translation (using Sys::getTypeName) already!
# therefore the argument name is type (meaning rrd section) and NOT graphtype.
#
# attention: this function name clashes with the function from func.pm, and is therefore
# not exported!
sub getFileName
{
	my %args = @_;

	my ($S,$type,$index,$item,$extras,$nmis4) =
			@args{"sys","type","index","item","extras","nmis4"};

	my $C = loadConfTable();

	if (!$S) {
		$S = Sys::->new(); # get base Model containing database info
		$S->init;
	}

	my $dir;

	# get the rule in Model to find the database file
	if ($S->{mdl}{database}{type}{$type})
	{
		my $string = $S->{mdl}{database}{type}{$type};
		$string =~ s/\$node\b/\$host/g if getbool($nmis4);

		# note: no CVARs as no section given
		# also, all optional inputs must be safeguarded, as indices (for example) can easily contain '/'
		# and at least these /s must be removed
		my $safetype = $type; $safetype =~ s!/!_!g;
		my $safeindex = $index; $safeindex =~ s!/!_!g;
		my $safeitem = $item; $safeitem =~ s!/!_!g;
		my %safeextras = ref($extras) eq "HASH"? %{$extras} :  ();
		map { $safeextras{$_} =~ s!/!_!g; } (keys %safeextras);

		if ($dir = $S->parseString(string=>$string, type=>$safetype,
															 index=>$safeindex, item=>$safeitem,
															 extras => \%safeextras ))
		{
			$dir = $C->{database_root}.$dir; # full specification
			dbg("filename of type=$type is $dir");
		}
	}
	else
	{
		logMsg("ERROR, ($S->{name}) no type=$type found in class=database of model=$S->{mdl}{system}{nodeModel}");
		$stats{error} = "($S->{name}) no type=$type found in class=database of model=$S->{mdl}{system}{nodeModel}";
	}
	return $dir;
}

# this function takes in a set of data items and updates the relevant rrd file
# arsg: sys, data (absolutely required), type/index/item (more or less required), extras (optional),
# database (optional, if set overrides the internal file naming logic)
#
# if node has marker node_was_reset or outage_nostats, then inbound
# data is IGNORED and 'U' is written instead
# (except for type "health", DS "outage", "polltime" and "updatetime", which are always let through)
#
# returns: the database file name; sets the internal error indicator
sub updateRRD
{
	my %args = @_;

	my ($S,$data,$type,$index,$item,$database,$extras) =
			@args{"sys","data","type","index","item","database","extras"};

	my $NI = $S->ndinfo;

	++ $stats{nodes}->{$S->{name}};

	dbg("Starting RRD Update Process, type=$type, index=$index, item=$item");

	# use heuristic or given database?
	$database = getFileName(sys=>$S, type=>$type, index=>$index, item=>$item, extras => $extras)
			if (!defined $database);

	if (!$database)
	{
		$stats{error} = "No RRD file found!";
		logMsg("ERROR, $stats{error}");
		return;
	}

	# Does the database exist ?
	if ( -f $database and -r $database and -w $database )
	{
		dbg("database $database exists and is R/W");
	}
	# Check if the RRD Database Exists but is ReadOnly
	# Maybe this should check for valid directory or not.
	elsif ( -f $database and not -w $database )
	{
		$stats{error} = "($S->{name}) database $database exists but is readonly!";
		logMsg("ERROR, $stats{error}");
		return;
	}
	else 												# no db file exists
	{
		# fall back to nmis4 format if requested to
		my $C = loadConfTable();
		if (getbool($C->{nmis4_compatibility}))
		{
			dbg("file=$database not found, try nmis4 format");
			my $database4 = getFileName(sys=>$S, type=>$type, index=>$index,
																	item=>$item, nmis4=>'true');
			if ($database4 and -f $database4
					and -r $database4 and -w $database4 )
			{
				$database = $database4;
				dbg("database $database exists and is R/W");
			}
		}

		# nope, create new file
		if (! createRRD(data=>$data, sys=>$S, type=>$type, database=>$database,
										index=>$index))
		{
			$stats{error} = "Failed to create RRD file $database!";
			return; # error
		}
	}

	my (@updateargs, @ds, %blankme);
	my @values = ("N");							# that's 'reading is for Now'

	# if the node has gone through a reset, then insert a U to avoid spikes for all COUNTER-ish DS
	if ($NI->{admin}->{node_was_reset})
	{
		dbg("node was reset, inserting U values");

		# get the DS definitions, extract the DS types and mark the counter-ish ones as blankable
		for (grep(/^DS:/, optionsRRD(data=>$data, sys=>$S, type=>$type, index=>$index)))
		{
			my (undef, $dsid, $dstype) = split(/:/, $_);
			if ($dstype ne "GAUGE")		# basically anything non-gauge is counter-ish
			{
				dbg("marking DS $dsid in $type as blankable, DS type $dstype");
				$blankme{$dsid} = 1;
			}
		}
	}
	# similar to the node reset case, but this also blanks GAUGE DS
	dbg("node has current outage with nostats option, inserting U values") if ($NI->{admin}->{outage_nostats});
	foreach my $var (keys %{$data})
	{
		# handle the nosave option
		if (exists($data->{$var}->{option}) && $data->{$var}->{option} eq "nosave")
		{
			dbg("DS $var is marked as nosave, not saving to RRD", 3);
			next;
		}

		push @ds, $var;

		# in outage with nostats option active?
		# then all rrds INCL health but EXCEPT health's outage/polltime/updatetime DS are overwritten
		# or was the node reset? then all known-blankable DS are overwritten
		# (as health holds only gauges and no counters the U isn't needed to avoid spikes)
		if (($NI->{admin}->{node_was_reset} and $blankme{$var})
				or ($NI->{admin}->{outage_nostats}
						and ($type ne "health" or $var !~ /^(outage|polltime|updatetime)$/)))
		{
			push @values, 'U';
		}
		else
		{
			# cleanup invalid values:
			# nonexistent or blank object we treat as 0
			$data->{$var}{value} = 0 if ($data->{$var}{value} eq "noSuchObject"
																	 or $data->{$var}{value} eq "noSuchInstance"
																	 or $data->{$var}{value} eq "");

			# then get rid of unwanted leading or trailing white space
			$data->{$var}{value} =~ s/^\s*//;
			$data->{$var}{value} =~ s/\s*$//;

			# other non-numeric input becomes rrdtool's 'undefined' value
			# all standard integer/float notations (incl 1.345E+7) should be accepted
			$data->{$var}{value} = "U" if ($data->{$var}{value} !~
																		 /^([+-]?)(?=\d|\.\d)\d*(\.\d*)?([Ee]([+-]?\d+))?$/);

			push @values,  $data->{$var}{value};
		}
	}
	my $thevalue =  join(":",@values);
	my $theds = join(":",@ds);
	push @updateargs,("-t", $theds, $thevalue);

	my $points = scalar @ds;
	# for bytes consider a 64 bit word, 8 bytes for each thing.
	#64-bits (8 bytes),
	my $bytes = $points * 8;

	$stats{datapoints} += $points;
	$stats{databytes} += $bytes;

	dbg("DS $theds, $points");
	dbg("value $thevalue, $bytes bytes");

	logPolling("$type,$NI->{system}{name},$index,$item,$theds,$thevalue");

	if (@updateargs)
	{
		# update RRD
		RRDs::update($database,@updateargs);
		++$stats{rrdcount};

		if (my $ERROR = RRDs::error())
		{
			if ($ERROR !~ /contains more DS|unknown DS name/)
			{
				$stats{error} = "($S->{name}) database=$database: $ERROR: arguments = @updateargs";
				logMsg("ERROR $stats{error}");
			}
			else
			{
				dbg("missing DataSource in $database, try to update");
				# find the DS names in the existing database (format ds[name].* )
				my $info = RRDs::info($database);
				my $names = ":";
				foreach my $key (keys %$info) {
					if ( $key =~ /^ds\[([a-zA-Z0-9_]{1,19})\].+/) { $names .= "$1:";}
				}
				# find the missing DS name (format DS:name:type:hearthbeat:min:max)
				my @options_db = optionsRRD(data=>$data,sys=>$S,type=>$type,index=>$index);
				foreach my $ds (@options_db)
				{
					my @opt = split /:/, $ds;
					if ( $opt[0] eq "DS" and $names !~ /:$opt[1]:/ )
					{
						&addDStoRRD($database,$ds); # sub in rrdfunc
					}
				}
			}
		}
	}
	else
	{
		$stats{error} = "($S->{name}) type=$type, no data to create/update database";
		logMsg("ERROR $stats{error}");
	}
	return $database;
	dbg("Finished");
} # end updateRRD

# the optionsRRD function creates the configuration options
# for creating an rrd file.
# args: sys, data, type (all pretty much required),
# index (optional, for string expansion)
# returns: array of rrdcreate parameters; updates global %stats
sub optionsRRD
{
	my %args = @_;

	my $S = $args{sys};
	my $data = $args{data};
	my $type = $args{type};
	my $index = $args{index}; # optional

	dbg("type $type, index $index");
	undef $stats{error};

	if (ref($S) ne "Sys")
	{
		$S = Sys->new;							# create generic object with base model info
		$S->init;
	}
	my $mdlinfo = $S->mdl;

	# find out rrd step and heartbeat values, possibly use type-specific values (which the polling policy would supply)
	my $timinginfo = (ref($mdlinfo->{database}) eq "HASH"
										&& ref($mdlinfo->{database}->{db}) eq "HASH"
										&& ref($mdlinfo->{database}->{db}->{timing}) eq "HASH")?
										$mdlinfo->{database}->{db}->{timing}->{$type} // $mdlinfo->{database}->{db}->{timing}->{"default"} :  undef;
	$timinginfo //= { heartbeat => 900, poll => 300 };
	# note: heartbeat is overridable per DS by passing in 'heartbeat' in data!
	dbg("timing options for this file of type $type: step $timinginfo->{poll}, heartbeat $timinginfo->{heartbeat}");

	# align the start time with the step interval, but reduce by one interval so that we can send data immediately
	my $starttime = time - (time % $timinginfo->{poll}) - $timinginfo->{poll};
	my @options = ("-b", $starttime, "-s", $timinginfo->{poll});

	# $data{ds_name}{value} contains the values
	# $data{ds_name}{option} contains the info for creating the dds, format is "source,low:high,heartbeat"
	# where source can be GAUGE,COUNTER etc. low:high are the limits of values to store, heartbeat
	# is for overriding the rrdfile-level heartbeat. range and heartbeat are optional, the ',' are clearly needed
	# even if you skip range but provide heartbeat.
	#
	# default is GAUGE,"U:U", and the standard heartbeat
	foreach my $id (sort keys %{$data})
	{
		if (length($id) > 19)
		{
			$stats{error} = "DS name=$id greater then 19 characters";
			logMsg("ERROR, DS name=$id greater then 19 characters") ;
			next;
		}

		my ($source,$range,$heartbeat);
		if ($data->{$id}{option})
		{
			if ($data->{$id}->{option} eq "nosave")
			{
				dbg("DS $id marked as nosave, ignoring.", 3);
				next;
			}

			($source,$range,$heartbeat) = split (/\,/,$data->{$id}{option});

			# no CVARs possible as no section given
			$range = $S->parseString(string=>$range, type=>$type, index=>$index) if $S ne "";
			$source = uc $source;
		}
		$source ||= "GAUGE";
		$range ||= "U:U";
		$heartbeat ||= $timinginfo->{heartbeat};

		dbg("ID of data is $id, source $source, range $range, heartbeat $heartbeat",2);
		push @options,"DS:$id:$source:$heartbeat:$range";
	}

	# now figure out the consolidation parameters, again possibly type-specific plus fallback
	my $sizeinfo = (ref($mdlinfo->{database}) eq "HASH"
									&& ref($mdlinfo->{database}->{db}) eq "HASH"
									&& ref($mdlinfo->{database}->{db}->{size}) eq "HASH")?
									$mdlinfo->{database}->{db}->{size}->{$type} // $mdlinfo->{database}->{db}->{size}->{"default"} :  undef;
	$sizeinfo //= { step_day => 1, step_week => 6, step_month => 24, step_year => 288,
									rows_day => 2304, rows_week => 1536, rows_month => 2268, rows_year => 1890 };

	for my $period (qw(day week month year))
	{
		for my $rra (qw(AVERAGE MIN MAX))
		{
			push @options,  join(":", "RRA", $rra, 0.5, $sizeinfo->{"step_$period"}, $sizeinfo->{"rows_$period"});
		}
	}
	return @options;
}

### createRRRDB now checks if RRD exists and only creates if doesn't exist.
### also add node directory create for node directories, if rrd is not found
### note that the function does NOT create an rrd file if
### $main::selftest_dbdir_status is 0 (not undef)
sub createRRD
{
	my %args = @_;
	my $S = $args{sys}; # optional
	my $data = $args{data};
	my $type = $args{type};
	my $index = $args{index};
	my $database = $args{database};

	my $C = loadConfTable();

	my $exit = 1;

	dbg("Starting");
	dbg("check and/or create RRD database $database");

	# Does the database exist already?
	if ( -f $database and -r $database and -w $database ) {
		# nothing to do!
		dbg("Database $database exists and is R/W");
	}
	# Check if the RRD Database Exists but is ReadOnly
	# Maybe this should check for valid directory or not.
	elsif ( -f $database and not -w $database )
	{
		$stats{error} = "($S->{name}) database $database Exists but is readonly";
		dbg("ERROR ($S->{name}) database $database Exists but is readonly");
		$exit = 0;
	}
	# are we allowed to create new files, or is the filesystem with the database dir (almost) full already?
	elsif (defined $main::selftest_dbdir_status && !$main::selftest_dbdir_status)
	{
		$stats{error} = "Not creating $database, as database filesystem is (almost) full!";
		logMsg("ERROR: Not creating $database, as database filesystem is (almost) full!");
		return 0;
	}
	# It doesn't so create it
	else
	{
		my @x = $database =~ /\//g; # until last slash
		my $dir = $`; # before last slash

		if ( not -d "$dir" and not -r "$dir" )
		{
			my $permission = "0770"; # default
			if ( $C->{'os_execperm'} ne "" ) {
				$permission = $C->{'os_execperm'} ;
			}

			my @comps = split(m!/!,$dir);
			for my $idx (1..$#comps)
			{
				my $parentdir = join("/",@comps[0..$idx]);
				if (!-d $parentdir)
				{
					dbg("creating database directory $parentdir, $permission");

					my $umask = umask(0);
					mkdir($parentdir, oct($permission)) or warn "Cannot mkdir $parentdir: $!\n";
					umask($umask);
					setFileProt($parentdir);
				}
			}
		}

		my @options = optionsRRD(data=>$data,sys=>$S,type=>$type,index=>$index);

		if ( @options ) {
			logMsg("Creating new RRD database $database");

			dbg("options to create database $database");
			foreach my $t (@options) {
				dbg($t);
			}
			RRDs::create("$database",@options);
			my $ERROR = RRDs::error();
			if ($ERROR)
			{
				$stats{error} = "($S->{name}) unable to create $database: $ERROR";
				logMsg("ERROR ($S->{name}) unable to create $database: $ERROR");
				$exit = 0;
			}
			# set file owner and permission, default: nmis, 0775.
			setFileProt($database); # Cologne, Jan 2005
			# Double check created OK for this user
			if ( -f $database and -r $database and -w $database )
			{
				logMsg("INFO ($S->{name}) created RRD $database");
			}
			else
			{
				$stats{error} = "($S->{name}) could not create RRD $database - check directory permissions";
				logMsg("ERROR ($S->{name}) could not create RRD $database - check directory permissions");
				$exit = 0;
			}
		}
		else
		{
			$stats{error} = "($S->{name}) unknown type=$type";
			logMsg("ERROR ($S->{name}) unknown type=$type");
			$exit = 0;
		}
	}
	dbg("Finished");
	return $exit;
} # end createRRD

1;
