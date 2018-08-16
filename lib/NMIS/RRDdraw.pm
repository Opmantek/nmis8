#
#  Copyright 1999-2018 Opmantek Limited (www.opmantek.com)
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
package NMIS::RRDdraw;
our $VERSION = "8.6.7G";

use strict;
use FindBin;
use lib "$FindBin::Bin/../lib";

# note: caller is expected to 'use NMIS' already
use func;
use Sys;
use RRDs 1.4004;

# produce one graph
# args: node/group, graphtype, intf/item, width, height (all required),
#  start, end, filename (optional)
#
# if filename is given then the graph is saved there.
# if no filename is given, then the graph is printed to stdout with minimal content-type header.
#
# returns: error message or (undef, rrds::graph result array)
sub draw
{
	my %args = @_;

	my ($nodename,$mygroup,$graphtype,$intf,$item,
			$width,$height,$filename,$start,$end,$time,$debug)
			= @args{qw(node group graphtype intf item width height filename start end time debug)};

	my $C = loadConfTable;

	my $S = Sys->new;
	$S->init(name=>$nodename, snmp=>'false');
	my $NI = $S->ndinfo;
	my $IF = $S->ifinfo;

	# default unit is hours!
	my $graphlength = ( $C->{graph_unit} eq "days" )?
			86400 * $C->{graph_amount} : 3600 * $C->{graph_amount}; # want seconds

	my $when = $time // time;
	$start = $when-$graphlength if (!$start);
	$end = $when if (!$end);

	# prep human-friendly (imprecise!) length of graph period
	my $mylength;									# cannot be called length
	if (($end - $start) < 3600)
	{
		$mylength = int(($end - $start) / 60) . " minutes";
	}
	elsif (($end - $start) < (3600*48))
	{
		$mylength = int(($end - $start) / (3600)) . " hours";
	}
	else
	{
		$mylength = int(($end - $start) / (3600*24)) . " days";
	}

	my (@rrdargs, 								# final rrd graph args
			$mydatabase);								# path to the rrd file

	# special graphtypes: global metrics
	if ($graphtype eq 'metrics')
	{
		$item = $mygroup;
		undef $intf;
	}

	# special graphtypes: cbqos is dynamic (multiple inputs create one graph), ditto calls
	if ($graphtype =~ /cbqos/)
	{
		@rrdargs = graphCBQoS(sys=>$S,
														 graphtype=>$graphtype,
														 intf=>$intf,
														 item=>$item,
														 start=>$start, end=>$end,
														 width=>$width, height=>$height);
	}
	elsif ($graphtype eq "calls")
	{
		@rrdargs = graphCalls(sys=>$S,
														 graphtype=>$graphtype,
														 intf=>$intf,
														 item=>$item,
														 start=>$start, end=>$end,
														 width=>$width, height=>$height);
	}
	else
	{
		$mydatabase = $S->getDBName(graphtype=>$graphtype, index=>$intf, item=>$item);
		return "failed to find database for graphtype $graphtype!" if (!$mydatabase);

		my $graph =  loadTable(dir=>'models', name=>"Graph-$graphtype");
		return "failed to read Graph-$graphtype!" if (ref($graph) ne "HASH" or !keys %$graph);

		my $titlekey =  ($width <= 400 and $graph->{title}{short})? 'short' : 'standard';
		my $vlabelkey = (getbool($C->{graph_split}) and $graph->{vlabel}{split})? 'split'
				: ($width <= 400 and $graph->{vlabel}{short})? 'short' : 'standard';
		my $size =  ($width <= 400 and $graph->{option}{small})? 'small' : 'standard';

		my $title = $graph->{title}{$titlekey};
		my $label = $graph->{vlabel}{$vlabelkey};

		logMsg("no title->$titlekey found in Graph-$graphtype") if (!$title);
		logMsg("no vlabel->$vlabelkey found in Graph-$graphtype") if (!$label);

		@rrdargs = (
			"--title", $title,
			"--vertical-label", $label,
			"--start", $start,
			"--end", $end,
			"--width", $width,
			"--height", $height,
			"--imgformat", "PNG",
			"--interlaced",
			"--disable-rrdtool-tag",
			"--color", 'BACK#ffffff',      # Background Color
			"--color", 'SHADEA#ffffff',    # Left and Top Border Color
			"--color", 'SHADEB#ffffff',    # was CFCFCF
			"--color", 'CANVAS#FFFFFF',    # Canvas (Grid Background)
			"--color", 'GRID#E2E2E2',      # Grid Line ColorGRID#808020'
			"--color", 'MGRID#EBBBBB',     # Major Grid Line ColorMGRID#80c080
			"--color", 'FONT#222222',      # Font Color
			"--color", 'ARROW#924040',     # Arrow Color for X/Y Axis
			"--color", 'FRAME#808080'      # Canvas Frame Color
				);

		if ($width > 400) {
			push(@rrdargs, "--font", $C->{graph_default_font_standard}) if $C->{graph_default_font_standard};
		}
		else
		{
			push(@rrdargs, "--font", $C->{graph_default_font_small}) if $C->{graph_default_font_small};
		}
		push @rrdargs, @{$graph->{option}{$size}};
	}

	{
		no strict;									# *shudder* this is so utterly wrong and broken
		# any scalars used in here must be global,
		# having an outside my $whatever does NOT WORK!
		if ($intf ne "")
		{
			$indx = $intf;
			$ifDescr = $IF->{$intf}{ifDescr};
			$ifSpeed = $IF->{$intf}{ifSpeed};
			$ifSpeedIn = $IF->{$intf}{ifSpeed};
			$ifSpeedOut = $IF->{$intf}{ifSpeed};
			$ifSpeedIn = $IF->{$intf}{ifSpeedIn} if $IF->{$intf}{ifSpeedIn};
			$ifSpeedOut = $IF->{$intf}{ifSpeedOut} if $IF->{$intf}{ifSpeedOut};
			if ($ifSpeed eq "auto" ) {
				$ifSpeed = 10000000;
			}

			if ( $IF->{$intf}{ifSpeedIn} and $IF->{$intf}{ifSpeedOut} ) {
				$speed = "IN\\: ". convertIfSpeed($ifSpeedIn) ." OUT\\: ". convertIfSpeed($ifSpeedOut);
			}
			else {
				$speed = convertIfSpeed($ifSpeed);
			}
		}
		# global scalars, cannot inherit from outer my $xyz
		$node = $NI->{system}{name}; # should be the same as args{node}...
		$length = $mylength;
		$group = $mygroup;

		$datestamp_start = returnDateStamp($start);
		$datestamp_end = returnDateStamp($end);
		$datestamp = returnDateStamp(time);
		$database = $mydatabase;

		$itm = $item;
		$split = getbool($C->{graph_split}) ? -1 : 1 ;
		$GLINE = getbool($C->{graph_split}) ? "AREA" : "LINE1" ;
		$weight = 0.983;

		for my $idx (0..$#rrdargs)
		{
			my $str = $rrdargs[$idx];

			# escape any ':' chars which might be in the database name (e.g C:\\) or the other
			# inputs (e.g. indx == service name). this must be done for ALL substitutables,
			# but no thanks to no strict we don't exactly know who they are, nor can we safely change
			# their values without side-effects...so we do it on the go, and only where not already pre-escaped.

			# EXCEPT in --title, where we can't have colon escaping. grrrrrr!
			if  ($idx > 0 && $rrdargs[$idx-1] eq "--title")
			{
				$str =~ s{\$(\w+)}{if(defined${$1}){${$1};}else{"ERROR, no variable \'\$$1\' ";}}egx;
			}
			else
			{
				$str =~ s{\$(\w+)}{if(defined${$1}){NMIS::postcolonial(${$1});}else{"ERROR, no variable \'\$$1\' ";}}egx;
			}

		 	if ($str =~ /ERROR/)
			{
				logMsg("ERROR in expanding variables, $str");
				return "ERROR in expanding variables, $str";
			}
			$rrdargs[$idx] = $str;
		}
	}

	my $graphret;
	# finally, generate the graph - as an indep http response to stdout
	# (bit uggly, no etag, expiration, content-length...)...
	if (!$filename)
	{
		# if this isn't done, then the graph output overtakes the header output,
		# and apache considers the cgi script broken and returns 500
		STDOUT->autoflush(1);
		print "Content-type: image/png\n\n";
		($graphret,undef,undef) = RRDs::graph('-', @rrdargs);
	}
	# ...or as a file.
	else
	{
		($graphret,undef,undef) = RRDs::graph($filename, @rrdargs);
	}
	if (my $error = RRDs::error)
	{
		logMsg("Graphing Error for graphtype $graphtype, database $mydatabase: $error");
		return "Graphing Error for graphtype $graphtype, database $mydatabase: $error";
	}
	return (undef, $graphret);
}

# special graph helper for CBQoS
# this handles both cisco and huawei flavour cbqos
# args: sys, graphtype, intf/item, start, end, width, height (all required)
# returns: array of rrd args
sub graphCBQoS
{
	my %args = @_;

	my $C = loadConfTable;
	my ($S,$graphtype,$intf,$item,$start,$end,$width,$height,$debug)
			= @args{qw(sys graphtype intf item start end width height debug)};

	my $NI = $S->ndinfo;
	my $IF = $S->ifinfo;

	# OMK-5182, customer wants / as delimiter for the cbqos names, not our default --
	my $delimiter = $C->{cbqos_classmap_name_delimiter} // "--";

	# order the names, find colors and bandwidth limits, index and section names
	my ($CBQosNames, $CBQosValues) = NMIS::loadCBQoS(sys=>$S, graphtype=>$graphtype, index=>$intf);

	# display all class-maps in one graph...
	if ($item eq "")
	{
		my $direction = ($graphtype eq "cbqos-in") ? "input" : "output" ;
		my $ifDescr = shortInterface($IF->{$intf}{ifDescr});
		my $vlabel = "Avg Bits per Second";
		my $title;

		if ( $width <= 400 ) {
			$title = "$NI->{name} $ifDescr $direction";
			$title .= " - $CBQosNames->[0]" if ($CBQosNames->[0] && $CBQosNames->[0] !~ /^(in|out)bound$/i);
			$title .= ' - $length';
			$vlabel = "Avg bps";
		}
		else
		{
			$title = "$NI->{name} $ifDescr $direction - CBQoS from ".'$datestamp_start to $datestamp_end'; # fixme: why replace later??
		}

		my @opt = (
			"--title", $title,
			"--vertical-label", $vlabel,
			"--start", $start,
			"--end", $end,
			"--width", $width,
			"--height", $height,
			"--imgformat", "PNG",
			"--interlaced",
			"--disable-rrdtool-tag",
			"--color", 'BACK#ffffff',      # Background Color
			"--color", 'SHADEA#ffffff',    # Left and Top Border Color
			"--color", 'SHADEB#ffffff',    #
			"--color", 'CANVAS#FFFFFF',    # Canvas (Grid Background)
			"--color", 'GRID#E2E2E2',      # Grid Line ColorGRID#808020'
			"--color", 'MGRID#EBBBBB',     # Major Grid Line ColorMGRID#80c080
			"--color", 'FONT#222222',      # Font Color
			"--color", 'ARROW#924040',     # Arrow Color for X/Y Axis
			"--color", 'FRAME#808080'      # Canvas Frame Color
				);

		if ($width > 400) {
			push(@opt,"--font", $C->{graph_default_font_standard}) if $C->{graph_default_font_standard};
		}
		else {
			push(@opt,"--font", $C->{graph_default_font_small}) if $C->{graph_default_font_small};
		}

		# calculate the sum (avg and max) of all Classmaps for PrePolicy and Drop
		# note that these CANNOT be graphed by themselves, as 0 isn't a valid RPN expression in rrdtool
		my $avgppr = "CDEF:avgPrePolicyBitrate=0";
		my $maxppr = "CDEF:maxPrePolicyBitrate=0";
		my $avgdbr = "CDEF:avgDropBitrate=0";
		my $maxdbr = "CDEF:maxDropBitrate=0";

		# is this hierarchical or flat?
		my $HQOS = 0;
		foreach my $i (1..$#$CBQosNames)
		{
			# \w is [a-zA-Z0-9_]
			if ( $CBQosNames->[$i] =~ /^[\w-]+$delimiter\w+$delimiter/ )
			{
				$HQOS = 1;
				last;
			}
		}

		my $gtype = "AREA";
		my $gcount = 0;
		my $parent_name = "";
		foreach my $i (1..$#$CBQosNames)
		{
			my $thisinfo = $CBQosValues->{$intf.$CBQosNames->[$i]};

			my $database = $S->getDBName(graphtype => $thisinfo->{CfgSection},
																	 index => $thisinfo->{CfgIndex},
																	 item => $CBQosNames->[$i] );
			my $parent = 0;
			if ( $CBQosNames->[$i] !~ /\w+$delimiter\w+/ and $HQOS )
			{
				$parent = 1;
				$gtype = "LINE1";
			}

			if ( $CBQosNames->[$i] =~ /^([\w-]+)$delimiter\w+$delimiter/ )
			{
				$parent_name = $1;
				dbg("parent_name=$parent_name\n") if ($debug);
			}

			if ( not $parent and not $gcount)
			{
				$gtype = "AREA";
				++$gcount;
			}
			elsif ( not $parent and $gcount)
			{
				$gtype = "STACK";
				++$gcount;
			}
			my $alias = $CBQosNames->[$i];
			$alias =~ s/${parent_name}$delimiter//g;
			$alias =~ s!$delimiter!/!g;

			# rough alignment for the columns, necessarily imperfect
			# as X-char strings aren't equally wide...
			my $tab = "\\t";
			if ( length($alias) <= 5 )
			{
				$tab = $tab x 4;
			}
			elsif ( length($alias) <= 14 )
			{
				$tab = $tab x 3;
			}
			elsif ( length($alias) <= 19 )
			{
				$tab = $tab x 2;
			}

			my $color = $CBQosValues->{$intf.$CBQosNames->[$i]}{'Color'};

			push @opt, ("DEF:avgPPB$i=$database:".$thisinfo->{CfgDSNames}->[0].":AVERAGE",
									"DEF:maxPPB$i=$database:".$thisinfo->{CfgDSNames}->[0].":MAX",
									"DEF:avgDB$i=$database:".$thisinfo->{CfgDSNames}->[2].":AVERAGE",
									"DEF:maxDB$i=$database:".$thisinfo->{CfgDSNames}->[2].":MAX",
									"CDEF:avgPPR$i=avgPPB$i,8,*",
									"CDEF:maxPPR$i=maxPPB$i,8,*",
									"CDEF:avgDBR$i=avgDB$i,8,*",
									"CDEF:maxDBR$i=maxDB$i,8,*",);

			if ($width > 400)
			{
				push @opt, ("$gtype:avgPPR$i#$color:$alias$tab",
										"GPRINT:avgPPR$i:AVERAGE:Avg %8.2lf%s\\t",
										"GPRINT:maxPPR$i:MAX:Max %8.2lf%s\\t",
										"GPRINT:avgDBR$i:AVERAGE:Avg Drops %6.2lf%s\\t",
										"GPRINT:maxDBR$i:MAX:Max Drops %6.2lf%s\\l");
			}
			else
			{
				push(@opt,"$gtype:avgPPR$i#$color:$alias");
			}

			#push(@opt,"LINE1:avgPPR$i#$color:$CBQosNames->[$i]");
			$avgppr .= ",avgPPR$i,+";
			$maxppr .= ",maxPPR$i,+";
			$avgdbr .= ",avgDBR$i,+";
			$maxdbr .= ",maxDBR$i,+";
		}

		push @opt,$avgppr,$maxppr,$avgdbr, $maxdbr;

		if ($width > 400)
		{
			push(@opt,"COMMENT:\\l",
					 "GPRINT:avgPrePolicyBitrate:AVERAGE:PrePolicyBitrate\\t\\t\\tAvg %8.2lf%s\\t",
					 "GPRINT:maxPrePolicyBitrate:MAX:Max\\t%8.2lf%s\\l",
					 "GPRINT:avgDropBitrate:AVERAGE:DropBitrate\\t\\t\\tAvg %8.2lf%s\\t",
					 "GPRINT:maxDropBitrate:MAX:Max\\t%8.2lf%s\\l");
		}
		return @opt;
	}

	# ...or display ONLY the selected class-map

	my $thisinfo = $CBQosValues->{$intf.$item};
	my $speed = defined $thisinfo->{CfgRate}? &convertIfSpeed($thisinfo->{'CfgRate'}) : undef;
	my $direction = ($graphtype eq "cbqos-in") ? "input" : "output" ;

	my $database = $S->getDBName(graphtype => $thisinfo->{CfgSection},
															 index => $thisinfo->{CfgIndex},
															 item => $item	);

	# in this case we always use the FIRST color, not the one for this item
	my $color = $CBQosValues->{$intf.$CBQosNames->[1]}->{'Color'};

	my $ifDescr = shortInterface($IF->{$intf}{ifDescr});
	my $title = "$ifDescr $direction - $item from ".'$datestamp_start to $datestamp_end'; # fixme: why replace later??

	my @opt = (
		"--title", $title,
		"--vertical-label", 'Avg Bits per Second',
		"--start", $start,
		"--end", $end,
		"--width", $width,
		"--height", $height,
		"--imgformat", "PNG",
		"--interlaced",
		"--disable-rrdtool-tag",
		"--color", 'BACK#ffffff',      # Background Color
		"--color", 'SHADEA#ffffff',    # Left and Top Border Color
		"--color", 'SHADEB#ffffff',    #
		"--color", 'CANVAS#FFFFFF',    # Canvas (Grid Background)
		"--color", 'GRID#E2E2E2',      # Grid Line ColorGRID#808020'
		"--color", 'MGRID#EBBBBB',     # Major Grid Line ColorMGRID#80c080
		"--color", 'FONT#222222',      # Font Color
		"--color", 'ARROW#924040',     # Arrow Color for X/Y Axis
		"--color", 'FRAME#808080',      # Canvas Frame Color
			);

		if ($width > 400)
		{
			push(@opt,"--font", $C->{graph_default_font_standard}) if $C->{graph_default_font_standard};
		}
		else
		{
			push(@opt,"--font", $C->{graph_default_font_small}) if $C->{graph_default_font_small};
		}

		# needs to work for both types of qos, hence uses the CfgDSNames
		push @opt, (
			"DEF:PrePolicyByte=$database:".$thisinfo->{CfgDSNames}->[0].":AVERAGE",
			"DEF:maxPrePolicyByte=$database:".$thisinfo->{CfgDSNames}->[0].":MAX",
			"DEF:DropByte=$database:".$thisinfo->{CfgDSNames}->[2].":AVERAGE",
			"DEF:maxDropByte=$database:".$thisinfo->{CfgDSNames}->[2].":MAX",
			"DEF:PrePolicyPkt=$database:".$thisinfo->{CfgDSNames}->[3].":AVERAGE",
			"DEF:DropPkt=$database:".$thisinfo->{CfgDSNames}->[5].":AVERAGE");

		# huawei doesn't have NoBufDropPkt
		push @opt, "DEF:NoBufDropPkt=$database:".$thisinfo->{CfgDSNames}->[6].":AVERAGE"
				if (defined $thisinfo->{CfgDSNames}->[6]);

		push @opt, (
			"CDEF:PrePolicyBitrate=PrePolicyByte,8,*",
			"CDEF:maxPrePolicyBitrate=maxPrePolicyByte,8,*",
			"CDEF:DropBitrate=DropByte,8,*",
			"TEXTALIGN:left",
			"AREA:PrePolicyBitrate#$color:PrePolicyBitrate",
		);

		# detailed legends are only shown on the 'big' graphs
		if ($width > 400) {
			push(@opt,"GPRINT:PrePolicyBitrate:AVERAGE:\\tAvg %8.2lf %sbps\\t");
			push(@opt,"GPRINT:maxPrePolicyBitrate:MAX:Max %8.2lf %sbps");
		}
		# move back to previous line, then right-align
		push @opt, "COMMENT:\\u", "AREA:DropBitrate#ff0000:DropBitrate\\r:STACK";

		if ($width > 400)
		{
			push @opt, ( "GPRINT:PrePolicyByte:AVERAGE:Bytes transferred\\t\\tAvg %8.2lf %sB/s\\n",
									 "GPRINT:DropByte:AVERAGE:Bytes dropped\\t\\t\\tAvg %8.2lf %sB/s\\t",
									 "GPRINT:maxDropByte:MAX:Max %8.2lf %sB/s\\n",
									 "GPRINT:PrePolicyPkt:AVERAGE:Packets transferred\\t\\tAvg %8.2lf\\l",
									 "GPRINT:DropPkt:AVERAGE:Packets dropped\\t\\t\\tAvg %8.2lf");

			# huawei doesn't have that
			push(@opt,"COMMENT:\\l","GPRINT:NoBufDropPkt:AVERAGE:Packets No buffer dropped\\tAvg %8.2lf\\l")
					if (defined $thisinfo->{CfgDSNames}->[6]);

			# not all qos setups have a graphable bandwidth limit
			push @opt, "COMMENT:\\u", "COMMENT:".$thisinfo->{CfgType}." $speed\\r" if (defined $speed);
		}
	return @opt;
}

sub graphCalls
{
	my %args = @_;

	my $S = $args{sys};
	my $NI = $S->ndinfo;
	my $IF = $S->ifinfo;
	my $graphtype = $args{graphtype};
	my $intf = $args{intf};
	my $start = $args{start};
	my $end = $args{end};
	my $width = $args{width};
	my $height = $args{height};

	my $database;
	my @opt;
	my $title;

	my $device = ($intf eq "") ? "total" : $IF->{$intf}{ifDescr};
	if ( $width <= 400 ) { $title = "$NI->{name} Calls ".'$length'; }
	else { $title = "$NI->{name} - $device - ".'$length from $datestamp_start to $datestamp_end'; }

	# display Calls summarized or only one port
	@opt = (
		"--title", $title,
		"--vertical-label","Call Stats",
		"--start", "$start",
		"--end", "$end",
		"--width", "$width",
		"--height", "$height",
		"--imgformat", "PNG",
		"--interlaced",
		"--disable-rrdtool-tag"
			);

	my $CallCount = "CDEF:CallCount=0";
	my $AvailableCallCount = "CDEF:AvailableCallCount=0";
	my $totalIdle = "CDEF:totalIdle=0";
	my $totalUnknown = "CDEF:totalUnknown=0";
	my $totalAnalog = "CDEF:totalAnalog=0";
	my $totalDigital = "CDEF:totalDigital=0";
	my $totalV110 = "CDEF:totalV110=0";
	my $totalV120 = "CDEF:totalV120=0";
	my $totalVoice = "CDEF:totalVoice=0";


	foreach my $i ($S->getTypeInstances(section => 'calls')) {
		next unless $intf eq "" or $intf eq $i;
		$database = $S->getDBName(graphtype => 'calls',
															index => $i);
		next if (!$database);

		push(@opt,"DEF:CallCount$i=$database:CallCount:MAX");
		push(@opt,"DEF:AvailableCallCount$i=$database:AvailableCallCount:MAX");
		push(@opt,"DEF:totalIdle$i=$database:totalIdle:MAX");
		push(@opt,"DEF:totalUnknown$i=$database:totalUnknown:MAX");
		push(@opt,"DEF:totalAnalog$i=$database:totalAnalog:MAX");
		push(@opt,"DEF:totalDigital$i=$database:totalDigital:MAX");
		push(@opt,"DEF:totalV110$i=$database:totalV110:MAX");
		push(@opt,"DEF:totalV120$i=$database:totalV120:MAX");
		push(@opt,"DEF:totalVoice$i=$database:totalVoice:MAX");

		$CallCount .= ",CallCount$i,+";
		$AvailableCallCount .= ",AvailableCallCount$i,+";
		$totalIdle .= ",totalIdle$i,+";
		$totalUnknown .= ",totalUnknown$i,+";
		$totalAnalog .= ",totalAnalog$i,+";
		$totalDigital .= ",totalDigital$i,+";
		$totalV110 .= ",totalV110$i,+";
		$totalV120 .= ",totalV120$i,+";
		$totalVoice .= ",totalVoice$i,+";
		if ($intf ne "") { last; }
	}

	push(@opt,$CallCount);
	push(@opt,$AvailableCallCount);
	push(@opt,$totalIdle);
	push(@opt,$totalUnknown);
	push(@opt,$totalAnalog);
	push(@opt,$totalDigital);
	push(@opt,$totalV110);
	push(@opt,$totalV120);
	push(@opt,$totalVoice);

	push(@opt,"LINE1:AvailableCallCount#FFFF00:AvailableCallCount");
	push(@opt,"LINE2:totalIdle#000000:totalIdle");
	push(@opt,"LINE2:totalUnknown#FF0000:totalUnknown");
	push(@opt,"LINE2:totalAnalog#00FFFF:totalAnalog");
	push(@opt,"LINE2:totalDigital#0000FF:totalDigital");
	push(@opt,"LINE2:totalV110#FF0080:totalV110");
	push(@opt,"LINE2:totalV120#800080:totalV120");
	push(@opt,"LINE2:totalVoice#00FF00:totalVoice");
	push(@opt,"COMMENT:\\l");
	push(@opt,"GPRINT:AvailableCallCount:MAX:Available Call Count %1.2lf");
	push(@opt,"GPRINT:CallCount:MAX:Total Call Count %1.0lf");

	return @opt;
}

1;
