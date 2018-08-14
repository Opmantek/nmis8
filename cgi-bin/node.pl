#!/usr/bin/perl
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
# Auto configure to the <nmis-base>/lib
use FindBin;
use lib "$FindBin::Bin/../lib";

use strict;
use List::Util 1.33;						# older versions don't have a usable any()
use Time::ParseDate;
use URI::Escape;
use Data::Dumper;
use CGI qw(:standard *table *Tr *td *form *Select *div);
use Text::CSV;

use func;
use NMIS;
use Auth;
use Sys;
use rrdfunc;										# for getrrdashash

my $q = new CGI; # This processes all parameters passed via GET and POST
my $Q = $q->Vars; # values in hash

my $C = loadConfTable(conf=>$Q->{conf},debug=>$Q->{debug});
die "Failed to load configuration!\n" if (ref($C) ne "HASH" or !keys %$C);

# Before going any further, check to see if we must handle
# an authentication login or logout request

# if arguments present, then called from command line, no auth.
if ( @ARGV ) { $C->{auth_require} = 0; }

my $user;
my $privlevel;

my $headeropts = {type=>'text/html',expires=>'now'};
my $AU = Auth->new(conf => $C);


if ($AU->Require) {
	exit 0 unless $AU->loginout(type=>$Q->{auth_type},username=>$Q->{auth_username},
					password=>$Q->{auth_password},headeropts=>$headeropts) ;
}

# check for remote request
if ($Q->{server} ne "") { exit if requestServer(headeropts=>$headeropts); }

my $NT = loadLocalNodeTable();
# this is just a hash of groupname=>groupname as observed from nodes' configurations - NOT filtered!
my $raw = loadGroupTable();
my $GT = {};
for my $configuredgroup (split(/\s*,\s*/, $C->{group_list}))
{
	$GT->{$configuredgroup} = $configuredgroup if (defined $raw->{$configuredgroup});
}

# cancel? go to graph view
if ($Q->{cancel} || $Q->{act} eq 'network_graph_view')
{
	typeGraph();
}
elsif ($Q->{act} eq 'network_export')
{
	typeExport();
}
elsif ($Q->{act} eq 'network_export_options')
{
	show_export_options();
}
elsif ($Q->{act} eq 'network_stats')
{
	typeStats();
}
else { bailout(message => "Unrecognised arguments! act=$Q->{act}, node=$Q->{node}, intf=$Q->{intf}<br>")};

exit 0;

# print minimal header, complaint message and exits
# args: code (optional, default: 400), message (required)
sub bailout
{
	my (%args) = @_;

	my $code = $args{code} // 400;
	my $message = $args{message} // "Failure";
	print header(-status => $code), start_html, $message, end_html;
	exit 0;
}

sub typeGraph
{
	my %args = @_;

	my $node = $Q->{node};
	my $index = $Q->{intf};
	my $item = $Q->{item};
	my $group = $Q->{group};
	my $start = $Q->{start}; # seconds
	my $end = $Q->{end};
	my $p_start = $Q->{p_start}; # seconds
	my $p_end = $Q->{p_end};
	my $p_time = $Q->{p_time};
	my $date_start = $Q->{date_start}; # string
	my $date_end = $Q->{date_end};
	my $p_date_start = $Q->{p_date_start}; # seconds
	my $p_date_end = $Q->{p_date_end};
	my $graphx = $Q->{'graphimg.x'}; # points
	my $graphy = $Q->{'graphimg.y'};
	my $graphtype = $Q->{graphtype};

	my $urlsafenode = uri_escape($node);
	my $urlsafegroup = uri_escape($group);
	my $urlsafeindex= uri_escape($index);
	my $urlsafeitem = uri_escape($item);

	my $length;

	my $S = Sys::->new; # get system object
	$S->init(name=>$node); # load node info and Model if name exists
	my $NI = $S->ndinfo;
	my $IF = $S->ifinfo;
	my $M = $S->mdl;
	my $V = $S->view;

	my %graph_button_table = (
		# graphtype		==	display #
		'health' 		=> 'Health' ,
		'response' 		=> 'Response' ,
		'cpu' 			=> 'CPU' ,
		'ccpu' 			=> 'CPU' ,
		'acpu' 			=> 'CPU' ,
		'ip' 			=> 'IP' ,
		'traffic'		=> 'Traffic' ,
		'mem-proc'		=> 'Memory' ,
		'pic-conn'		=> 'Connections' ,
		'a3bandwidth'	=> 'Bandwidth' ,
		'a3traffic'		=> 'Traffic' ,
		'a3errors'		=> 'Errors'	);

	# graphtypes for custom service graphs are fixed and not found in the model system
	# note: format known here, in services.pl and nmis.pl
	my $heading;
	if ($graphtype =~ /^service-custom-([a-z0-9\.-])+-([a-z0-9\._-]+)$/)
	{
		$heading = $2;
	}
	else
	{
		$heading = $S->graphHeading(graphtype=>$graphtype, index=>$index, item=>$group);
	}

	print header($headeropts);
	print start_html(
		-title => "Graph Drill In for $heading @ ".returnDateStamp." - $C->{server_name}",
		-meta => { 'CacheControl' => "no-cache",
			'Pragma' => "no-cache",
			'Expires' => -1
			},
		-head=>[
			 Link({-rel=>'shortcut icon',-type=>'image/x-icon',-href=>"$C->{'<url_base>'}/images/nmis_favicon.png"}),
			 Link({-rel=>'stylesheet',-type=>'text/css',-href=>"$C->{'styles'}"}),
		],
		-script => {-src => $C->{'jquery'}, -type=>"text/javascript"},
		);

	# verify that user is authorized to view the node within the user's group list
	if ( $node ) {
		if ( !$AU->InGroup($NT->{$node}{group}) or !exists $GT->{$NT->{$node}{group}} )
		{
			print "Not Authorized to view graphs on node '$node' in group $NT->{$node}{group}";
			return 0;
		}
	} elsif ( $group ) {
		if ( ! $AU->InGroup($group) or !exists $GT->{$group} )
		{
			print "Not Authorized to view graphs on nodes in group $group";
			return 0;
		}
	}


	my $time = time();

	my $width = $C->{graph_width};
	my $height = $C->{graph_height};

	### 2012-02-06 keiths, handling default graph length
	# default is hours!
	my $graphlength = $C->{graph_amount};
	if ( $C->{graph_unit} eq "days" ) {
		$graphlength = $C->{graph_amount} * 24;
	}

	# convert start time/date field to seconds
	###
	if ( $date_start eq "" ) {
		if ( $start eq "" ) { $start = $p_start = $time - ($graphlength*60*60); }
	} else {
		$start = parsedate($date_start);
	}

	# convert to seconds
	if ( $date_end eq "" ) {
		if ( $end eq "" ) { $end = $p_end = $time ; }
	} else {
		$end = parsedate($date_end);
	}

	$length = $end - $start;

	# width by default is 800, height is variable but always greater then 250
	#left
	if ( $graphx != 0 and $graphx < 150 ) {
		$end = $end - ($length/2);
		$start = $end - $length;
	}
	#right
	elsif ( $graphx != 0 and $graphx > $width + 94 - 150 ) {
		$end = $end + ($length/2);
		$start = $end - $length;
	}
	#zoom in
	elsif ( $graphx != 0 and ( $graphy != 0 and $graphy <= $height / 2 ) ) {
#		$start = $start + ($length/2);
		$end = $end - ($length/4);
		$length = $length/2;
		$start = $end - $length;
	}
	#zoom out
	elsif ( $graphx != 0 and ( $graphy != 0 and $graphy > $height / 2 ) ) {
#		$start = $start - ($length);
		$end = $end + ($length/2);
		$length = $length*2;
		$start = $end - $length;
	#
	} elsif ($p_time ne '' and $date_start eq $p_date_start and $date_end eq $p_date_end) {
		# pushed button, move with clock
		$end = $end + ($time - $p_time);
		$start = $end - $length;
	}

	# minimal length of 30 minutes
	if ( $start > ($time - (60*30)) ) {
		$start = $time - (60*30);
	}
	# minimal 30 min.
	if ($start > ($end - (60*30)) ) {
		$start = $end - (60*30);
	}

	# to integer
	$start = int($start);
	$end = int($end);

	$p_start = $start;
	$p_end = $end;

	$date_start = returnDateStamp($start);
	$date_end = returnDateStamp($end);

	#==== calculation done

	my $GTT = $S->loadGraphTypeTable(index=>$index);

	#print STDERR "DEBUG: ", %$GTT, "\n";

	my $itm;
	if ($Q->{graphtype} eq 'metrics') {
		$group = 'network' if $group eq "";
		$item = $group;
	} elsif ($Q->{graphtype} =~ /cbqos/) {
	} elsif ($GTT->{$graphtype} eq 'interface') {
		$item = '';
	}

	my @nodelist;
	for my $node ( sort keys %{$NT})
	{
		my $auth = 1;

		if ($AU->Require)
		{
			my $lnode = lc($NT->{$node}{name});
			if ( $NT->{$node}{group} ne "" ) {
				if ( not $AU->InGroup($NT->{$node}{group}) ) {
					$auth = 0;
				}
			}
			else {
				logMsg("WARNING ($node) not able to find correct group. Name=$NT->{$node}{name}.")
			}
		}

		# to be included node must be ok to see, active and belonging to a configured group
		push @nodelist, $NT->{$node}{name} if ($auth
																					 && getbool($NT->{$node}->{active})
																					 && $GT->{$NT->{$node}->{group}});
	}

	my %sshealth = get_graphtype_systemhealth(sys => $S, graphtype => $graphtype);

	print comment("typeGraph begin");

	# primary form part - if we want the url to have the params then we need to use GET
	# and tell cgi explicitely to use the appropriate encoding type...

	print start_form(-method => 'GET', -enctype => "application/x-www-form-urlencoded",
									 -name=>"dograph", -action=>url(-absolute=>1)),
	start_table();

	#print Tr(th({class=>'title',colspan=>'1'},"<div>$heading<span class='right'>User: $user, Auth: Level$privlevel</span></div>"));
	print Tr(th({class=>'title',colspan=>'1'},"$heading"));
	print Tr(td({colspan=>'1'},
							table({class=>'table',width=>'100%'},
										Tr(
											# Start date field
											td({class=>'header',align=>'center',colspan=>'1'},"Start",
												 textfield(-name=>"date_start",-override=>1,-value=>"$date_start",size=>'23',tabindex=>"1")),
											# Node select menu
											td({class=>'header',align=>'center',colspan=>'1'},

												 ($Q->{graphtype} eq 'metrics' or $Q->{graphtype}  eq 'nmis')?
												 hidden(-name=>'node', -default=>$Q->{node},-override=>'1')
												 : ( "Node ", popup_menu(-name=>'node', -override=>'1',
																								 tabindex=>"3",
																								 -values=>[@nodelist],
																								 -default=>"$Q->{node}",
																								 -onChange=>'JavaScript:this.form.submit()'))
											),
											# Graphtype select menu
											td({class=>'header',align=>'center',colspan=>'1'},"Type ",
												 popup_menu(-name=>'graphtype', -override=>'1', tabindex=>"4",
																		-values=>[sort keys %{$GTT}],
																		-default=>"$Q->{graphtype}",
																		-onChange=>'JavaScript:this.form.submit()')),
											# Submit button
											td({class=>'header',align=>'center',colspan=>'1'},
												 submit(-name=>"dograph",-value=>"Submit"))),

										# next row
										Tr(
											# End date field
											td({class=>'header',align=>'center',colspan=>'1'},"End&nbsp;",
												 textfield(-name=>"date_end",-override=>1,-value=>"$date_end",size=>'23',tabindex=>"2")),
											# Group or Interface select menu
											td({class=>'header',align=>'center',colspan=>'1'},
												 # fixme: using eval this way makes all errors vanish!
												 eval {
													 return hidden(-name=>'intf', -default=>$Q->{intf},-override=>'1') if $Q->{graphtype} eq 'nmis';
													 if ( $Q->{graphtype} eq "metrics") {
														 return 	"Group ",popup_menu(-name=>'group', -override=>'1',-size=>'1', tabindex=>"5",
																													-values=>[grep $AU->InGroup($_), 'network',sort keys %{$GT}],
																													-default=>"$group",
																													-onChange=>'JavaScript:this.form.submit()'),
														 hidden(-name=>'intf', -default=>$Q->{intf},-override=>'1');
													 }
													 elsif ($Q->{graphtype} eq "hrsmpcpu") {
														 return 	"CPU ",popup_menu(-name=>'intf', -override=>'1',-size=>'1', tabindex=>"5",
																												-values=>['',sort $S->getTypeInstances(graphtype => "hrsmpcpu")],
																												-default=>"$index",
																												-onChange=>'JavaScript:this.form.submit()');
													 } elsif ($Q->{graphtype} =~ /service|service-cpumem|service-response/) {
														 return 	"Service ",popup_menu(-name=>'intf', -override=>'1',-size=>'1', tabindex=>"5",
																														-values=>['',sort $S->getTypeInstances(section => "service")],
																														-default=>"$index",
																														-onChange=>'JavaScript:this.form.submit()');
													 } elsif ($Q->{graphtype} eq "hrdisk") {
														 my @disks = $S->getTypeInstances(graphtype =>  "hrdisk");
														 return 	"Disk ",popup_menu(-name=>'intf', -override=>'1',-size=>'1', tabindex=>"5",
																												 -values=>['',sort @disks],
																												 -default=>"$index",
																												 -labels=>{ map{($_ => $NI->{storage}{$_}{hrStorageDescr})} sort @disks },
																												 -onChange=>'JavaScript:this.form.submit()');
													 } elsif ($GTT->{$graphtype} eq "env_temp") {
														 my @sensors = $S->getTypeInstances(graphtype => "env_temp");
														 return 	"Sensor ",popup_menu(-name=>'intf', -override=>'1',-size=>'1', tabindex=>"5",
																													 -values=>['',sort @sensors],
																													 -default=>"$index",
																													 -labels=>{ map{($_ => $NI->{env_temp}{$_}{tempDescr})} sort @sensors },
																													 -onChange=>'JavaScript:this.form.submit()');
													 } elsif ($GTT->{$graphtype} eq "akcp_temp") {
														 my @sensors = $S->getTypeInstances(graphtype => "akcp_temp");
														 return 	"Sensor ",popup_menu(-name=>'intf', -override=>'1',-size=>'1', tabindex=>"5",
																													 -values=>['',sort @sensors],
																													 -default=>"$index",
																													 -labels=>{ map{($_ => $NI->{akcp_temp}{$_}{hhmsSensorTempDescr})} sort @sensors },
																													 -onChange=>'JavaScript:this.form.submit()');
													 } elsif ($GTT->{$graphtype} eq "akcp_hum") {
														 my @sensors = $S->getTypeInstances(graphtype => "akcp_hum");
														 return 	"Sensor ",popup_menu(-name=>'intf', -override=>'1',-size=>'1', tabindex=>"5",
																													 -values=>['',sort @sensors],
																													 -default=>"$index",
																													 -labels=>{ map{($_ => $NI->{akcp_hum}{$_}{hhmsSensorHumDescr})} sort @sensors },
																													 -onChange=>'JavaScript:this.form.submit()');
													 } elsif ($GTT->{$graphtype} eq "cssgroup") {
														 my @cssgroup = $S->getTypeInstances(graphtype => "cssgroup");
														 return 	"Group ",popup_menu(-name=>'intf', -override=>'1',-size=>'1', tabindex=>"5",
																													-values=>['',sort @cssgroup],
																													-default=>"$index",
																													-labels=>{ map{($_ => $NI->{cssgroup}{$_}{CSSGroupDesc})} sort @cssgroup },
																													-onChange=>'JavaScript:this.form.submit()');
													 } elsif ($GTT->{$graphtype} eq "csscontent") {
														 my @csscont = $S->getTypeInstances(graphtype => "csscontent");
														 return 	"Sensor ",popup_menu(-name=>'intf', -override=>'1',-size=>'1', tabindex=>"5",
																													 -values=>['',sort @csscont],
																													 -default=>"$index",
																													 -labels=>{ map{($_ => $NI->{csscontent}{$_}{CSSContentDesc})} sort @csscont },
																													 -onChange=>'JavaScript:this.form.submit()');
													 }
													 elsif ($sshealth{is_systemhealth})
													 {
														 return 	$sshealth{title}." ",
														 popup_menu(-name=>'intf', -override=>'1',-size=>'1', tabindex=>"5",
																				-values=>['',sort keys %{$NI->{ $sshealth{section} }}],
																				-default=>"$index",
																				-labels=> $sshealth{labels},
																				-onChange=>'JavaScript:this.form.submit()');
													 }
													 else {
														 # all interfaces have an ifindex, but for the menu we only want
														 # the ones that NMIS actually collects
														 my @wantedifs = sort { $IF->{$a}{ifDescr} cmp $IF->{$b}{ifDescr} }
														 grep( exists $IF->{$_}{ifIndex} && getbool($IF->{$_}->{collect}), keys %{$IF});

														 ### 2014-10-21 keiths, if the ifIndex is specifically requested, show it in the menu.
														 if (not grep { $_ eq $index } @wantedifs ) {
															 push(@wantedifs, $index);
														 }
														 return 	"Interface ",popup_menu(-name=>'intf', -override=>'1',-size=>'1', tabindex=>"5",
																															-values=>['',  @wantedifs],
																															-default=>"$index",
																															-labels=>{ map{($_ => $IF->{$_}{ifDescr})} @wantedifs },
																															-onChange=>'JavaScript:this.form.submit()');
													 }
												 }),

											# Fast select graphtype buttons
											td({class=>'header',align=>'center',colspan=>'2'},
												 div({class=>"header"},
														 eval {
															 my @out;
															 my $cg = "conf=$Q->{conf}&group=$urlsafegroup&start=$start&end=$end&intf=$index&item=$Q->{item}&node=$urlsafenode";

															 push @out, a({class=>'button', tabindex=>"-1",
																						 href=>url(-absolute=>1)."?$cg&act=network_graph_view&graphtype=nmis"},
																						"NMIS");

															 foreach my $gtp (keys %graph_button_table) {
																 foreach my $gt (keys %{$GTT}) {
																	 if ($gtp eq $gt) {
																		 push @out,a({class=>'button', tabindex=>"-1", href=>url(-absolute=>1)."?$cg&act=network_graph_view&graphtype=$gtp"},$graph_button_table{$gtp});
																	 }
																 }
															 }


															 if (not($graphtype =~ /cbqos|calls/ and $Q->{item} eq ''))
															 {
																 push @out,a({class=>'button', tabindex=>"-1",
																							href=>url(-absolute=>1)."?$cg&act=network_stats&graphtype=$Q->{graphtype}"},
																						 "Stats");

																 # export: one link, direct export with default resolution,
																 # one link to a separate page with option form
																 push @out, (
																	 a({class=>'button', tabindex=>"-1",
																			href=>url(-absolute=>1)."?$cg&act=network_export&graphtype=$Q->{graphtype}"},
																		 "Export"),
																	 a({class=>"button", tabindex => -1,
																			href => url(-absolute=>1)."?$cg&act=network_export_options&graphtype=$Q->{graphtype}"},
																		 "Adv. Export"), );
															 }


															 return @out;
														 })) ))));


	# interface info
	if ( $GTT->{$graphtype} =~ /interface|pkts|cbqos/i and $index ne "") {

		my $db;
		my $lastUpdate;
		if (($GTT->{$graphtype} =~ /cbqos/i and $item ne "") or $GTT->{$graphtype} =~ /interface|pkts/i ) {
			$db = $S->getDBName(graphtype=>$graphtype,index=>$index,item=>$item);
			$time = RRDs::last $db;
			$lastUpdate = returnDateStamp($time);
		}

		$S->readNodeView;
		my $V = $S->view;

		my $speed = &convertIfSpeed($IF->{$index}{ifSpeed});
		if ( $V->{interface}{"${index}_ifSpeedIn_value"} ne "" and $V->{interface}{"${index}_ifSpeedOut_value"} ne "" ) {
				$speed = qq|IN: $V->{interface}{"${index}_ifSpeedIn_value"} OUT: $V->{interface}{"${index}_ifSpeedOut_value"}|;
		}

		# info Type, Speed, Last Update, Description
		print Tr(td({colspan=>'1'},
			table({class=>'table',border=>'0',width=>'100%'},
				Tr(td({class=>'header',align=>'center',},'Type'),
					td({class=>'info Plain',},$IF->{$index}{ifType}),
					td({class=>'header',align=>'center',},'Speed'),
					td({class=>'info Plain'},$speed)),
				Tr(td({class=>'header',align=>'center',},'Last Updated'),
					td({class=>'info Plain'},$lastUpdate),
					td({class=>'header',align=>'center',},'Description'),
					td({class=>'info Plain'},$IF->{$index}{Description})) )));

	} elsif ( $GTT->{$graphtype} =~ /hrdisk/i and $index ne "") {
		print Tr(td({colspan=>'1'},
			table({class=>'table',border=>'0',width=>'100%'},
				Tr(td({class=>'header',align=>'center',},'Type'),
					td({class=>'info Plain'},$NI->{storage}{$index}{hrStorageType}),
					td({class=>'header',align=>'center',},'Description'),
					td({class=>'info Plain'},$NI->{storage}{$index}{hrStorageDescr})) )));
	}

	my @output;
	# check if database selectable with this info
	if ( ($S->getDBName(graphtype=>$graphtype,index=>$index,item=>$item,
											suppress_errors=>'true'))
			 or $Q->{graphtype} =~ /calls|cbqos/) {

		my %buttons;
		my $htitle;
		my $hvalue;
		my @buttons;
		my @intf;

		# figure out the available policy or classifier names and other cbqos details
		if ( $Q->{graphtype} =~ /cbqos/ )
		{
			my ($CBQosNames,undef) = NMIS::loadCBQoS(sys=>$S,graphtype=>$graphtype,index=>$index);
			$htitle = 'Policy name';
			$hvalue = $CBQosNames->[0] || "N/A";

			for my $i (1..$#$CBQosNames) {
				$buttons{$i}{name} = $CBQosNames->[$i];
				$buttons{$i}{intf} = $index;
				$buttons{$i}{item} = $CBQosNames->[$i];
			}
		}

		# display Call buttons if there is more then one call port for this node
		if ( $Q->{graphtype} eq "calls" ) {
			for my $i ($S->getTypeInstances(section => "calls")) {
				$buttons{$i}{name} = $IF->{$i}{ifDescr};
				$buttons{$i}{intf} = $i;
				$buttons{$i}{item} = '';
			}
		}

		if (%buttons) {
			my $cg = "conf=$Q->{conf}&act=network_graph_view&graphtype=$Q->{graphtype}&start=$start&end=$end&node=".uri_escape($Q->{node});
			push @output, start_Tr;
			if ($htitle ne "") {
				push @output, td({class=>'header',colspan=>'1'},$htitle),td({class=>'info Plain',colspan=>'1'},$hvalue);
			}
			push @output, td({class=>'header',colspan=>'1'},"Select ",
											 popup_menu(-name=>'item', -override=>'1',
																	-values=>['',map { $buttons{$_}{name} } keys %buttons],
																	-default=>"$item",
																	-onChange=>'JavaScript:this.form.submit()'));
			push @output, end_Tr;
		}

		my $graphLink = htmlGraph(only_link => 1, # we need the unwrapped link!
															node => $node,
															group => $group,
															graphtype => $graphtype,
															intf => $index,
															item => $item,
															start => $start,
															end => $end,
															width => $width,
															height => $height );
		# logMsg("asked for $graphtype, start $start end $end, got $graphLink");

		if ( $graphtype ne "service-cpumem" or $NI->{graphtype}{$index}{service} =~ /service-cpumem/ )
		{
			push @output, Tr(td({class=>'info Plain',align=>'center',colspan=>'4'},
													image_button(-name=>'graphimg',-src => $graphLink,
																			 -align=>'MIDDLE', -tabindex=>"-1")));
			push @output, Tr(td({class=>'info Plain',align=>'center',colspan=>'4'},
													"Clickable graphs: Left -> Back; Right -> Forward; Top Middle -> Zoom In; Bottom Middle-> Zoom Out, in time"));
		}
		else
		{
			push @output, Tr(td({class=>'info Plain',align=>'center',colspan=>'4'},
													"Graph type not applicable for this data set."));
		}
	} else {
		push @output, Tr(td({colspan=>'4',align=>'center'},
												"waiting for selection or no data available"));
		push @output, hidden(-name=>'item', -default=>"$item",-override=>'1');
	}
	# push on page
	print Tr(td({colspan=>'1'},
			table({class=>'plain',width=>'100%'},@output)));

	print "</table>";
	print hidden(-name=>'conf', -default=>$Q->{conf},-override=>'1');
	print hidden(-name=>'p_date_start', -default=>"$date_start",-override=>'1');
	print hidden(-name=>'p_date_end', -default=>"$date_end",-override=>'1');
	print hidden(-name=>'p_start', -default=>"$p_start",-override=>'1');
	print hidden(-name=>'p_end', -default=>"$p_end",-override=>'1');
	print hidden(-name=>'p_time', -default=>"$time",-override=>'1');
	print hidden(-name=>'act', -default=>"network_graph_view", -override=>'1');

	print "</form>", comment("typeGraph end");
	print end_html;

} # end typeGraph

# shows a form with options for exporting, submission target is typeExport()
sub show_export_options
{
	my ($node,$item,$intf,$group,$graphtype) = @{$Q}{qw(node item intf group graphtype)};

	bailout(message => "Invalid arguments, missing node!") if (!$node);

	my $S = Sys->new;
	my $isok = $S->init(name => $node, snmp => 'false');
	bailout(message => "Invalid arguments, could not load data for nonexistent node!") if (!$isok);

	# verify that user is authorized to view the node within the user's group list
	my $nodegroup = $S->ndinfo->{system}->{group};
	if ($node && (!$AU->InGroup($nodegroup || !exists $GT->{$nodegroup})))
	{
		bailout(code => 403,
						message => escapeHTML("Not Authorized to export rrd data for node '$node' in group '$nodegroup'."));
	}
	elsif ($group && (!$AU->InGroup($group) || !exists $GT->{$group}))
	{
		bailout(code => 403,
						message => escapeHTML("Not Authorized to export rrd data for nodes in group '$group'."));
	}

	# graphtypes for custom service graphs are fixed and not found in the model system
	# note: format known here, in services.pl and nmis.pl
	my $heading;
	if ($graphtype =~ /^service-custom-([a-z0-9\.-])+-([a-z0-9\._-]+)$/)
	{
		$heading = $2;
	}
	else
	{
		# fixme: really group in item???
		$heading = $S->graphHeading(graphtype=>$graphtype, index=>$intf, item=>$group);
	}
	$heading = escapeHTML($heading);

	# headers, html setup, form
	print header($headeropts),
	start_html(-title => "Export Options for Graph $heading - $C->{server_name}",
						 -head => [
								Link({-rel=>'shortcut icon',-type=>'image/x-icon',-href=>"$C->{'nmis_favicon'}"}),
								Link({-rel=>'stylesheet',-type=>'text/css',-href=>"$C->{'styles'}"}),
						 ],
						 -script => {-src => $C->{'jquery'}, -type=>"text/javascript"},),

								 # this form should post. we don't want anything in the url.
								start_form( -name => 'exportopts',
														-action => url(-absolute => 1)),
								 hidden(-name => 'act', -default => 'network_export', -override => 1),
								 # not selectable: node/group, graphtype, item/intf
								 hidden(-name => "node", -default => $node, -override => 1),
								 hidden(-name => "group", -default => $group, -override => 1),
								 hidden(-name => "graphtype", -default => $graphtype, -override => 1),
								 hidden(-name => "item", -default => $item, -override => 1),
								 hidden(-name => "intf", -default => $intf, -override => 1);


	# figure out how to label the selector/index/intf properties
	my %sshealth = get_graphtype_systemhealth(sys => $S, graphtype => $graphtype);
	my %graphtype2itemname = ( metrics => 'Group',
														 hrsmpcpu => 'Cpu',
														 ( map { ($_ => "Service") } (qw(service service-cpumem service-response))),
														 hrdisk => 'Disk',
														 ( map { ($_ => 'Sensor') } (qw(env_temp akcp_temp akcp_hum csscontent))),
														 cssgroup => 'Group',
														 nmis => undef); # no item label is shown

	print qq|<table><tr><th class='title' colspan='2'>Export Options for Graph "$heading"</th></tr>|;

	my $label = $graphtype2itemname{$graphtype};
	$label //= $sshealth{labels}->{$graphtype} if ($sshealth{is_systemhealth});
	$label //= "Interface";

	my $property = ( $graphtype eq "nmis"? undef
									 : $graphtype eq "metrics"? $group : $intf );

	print qq|<tr><td class="header">Node</td><td>|.escapeHTML($node).qq|</td></tr>|
			if ($graphtype ne "nmis" && $graphtype ne "metrics");
	if (defined $property)
	{
		print qq|<tr><td class="header">$label</td><td>|.escapeHTML($property).qq|</td></tr>|;
	}

	my $graphhours =$C->{graph_amount};
	$graphhours *= 24 if ($C->{graph_unit} eq "days");

	my $date_start = returnDateStamp( time - $graphhours*3600);
	my $date_end = returnDateStamp(time);

	print qq|<tr><td class='header'>Start</td><td>|
			. textfield(-name=>"date_start", -override=>1, -value=> $date_start, size=>'23', tabindex=>"1")
			. qq|</td></tr><tr><td class='header'>End</td><td>|
			. textfield(-name=>"date_end", -override=>1, -value=> $date_end, size=>'23', tabindex=>"2")
			. qq|</td></tr>|;


	# make a dropdown list for export summarisation options
	my @options = ref($C->{export_summarisation_periods}) eq "ARRAY"?
			@{$C->{export_summarisation_periods}}: ( 300, 900, 1800, 3600, 4*3600 );
	my %labels = ( '' => "best", map { ($_=> func::period_friendly($_)) } (@options));

	print qq|<tr><td class='header'>Resolution</td><td>Select one of |
			. popup_menu(-name => "resolution",
									 -id => "exportres",
									 -values => [ '', @options ],
									 -override => 1,
									 -labels => \%labels, )
			# also add an input field for a one-off text input
			. qq| or enter |
			.textfield(-name => "custom_resolution",
								 -id => "exportrescustom",
								 -override => 1,
								 -placeholder => "NNN",
								 -size => 6	)
			. qq| seconds </td></tr>|
			. qq|<tr><td class='header'>Compute Min/Max for each period?</td><td>|
			.checkbox(-name=>'add_minmax',
								-checked => 0,
								-override => 1,
								-value=>1,
								-label=>'')
			. qq| (only for Resolutions other than 'best')</td></tr>|;

	print  qq|<tr><td class='header' colspan='2' align='center'>|
			. hidden(-name => 'cancel', -id => 'cancelinput', -default => '', -override => 1)
			. submit( -value=>'Export')
			.qq| or <input name="cancel" type='button' value="Cancel" onclick="\$('#cancelinput').val(1); this.form.submit()"></td></tr></table>|;
}


# exports the underlying data for a particular graph as csv,
# optionally further bucketised into fewer readings
# params: node (or group?), graphtype, intf/item, start/end (or date_start/date_end),
# resolution (optional; default or blank, zero: use best resolution),
# also custom_resolution (optional, if present overrides resolution)
sub typeExport
{
	my $S = Sys->new; # get system object
	$S->init(name => $Q->{node}, snmp => 'false');
	my $NI = $S->ndinfo;
	my $IF = $S->ifinfo;

	my $NT = loadLocalNodeTable();

	my %interfaceTable;
	my $database;
	my $extName;

	# verify that user is authorized to view the node within the user's group list
	if ($Q->{node} && !$AU->InGroup($NT->{$Q->{node}}{group}))
	{
		bailout(code => 403, message => "Not Authorized to export rrd data for node '$Q->{node}' in group '$NT->{$Q->{node}}{group}'.");
	} elsif ( $Q->{group} && !$AU->InGroup($Q->{group}))
	{
		bailout(code => 403, message => "Not Authorized to export rrd data for nodes in group '$Q->{group}'.");
	}

	# figure out start and end
	my ($start, $end) = @{$Q}{"start","end"};
	$start //= func::parseDateTime($Q->{date_start}) || func::getUnixTime($Q->{date_start}) if ($Q->{date_start});
	$end //= func::parseDateTime($Q->{date_end}) || func::getUnixTime($Q->{date_end}) if ($Q->{date_end});

	my $mayberesolution = ( defined($Q->{custom_resolution}) && $Q->{custom_resolution} =~ /^\d+$/?
													$Q->{custom_resolution}
													: defined($Q->{resolution})
													&& $Q->{resolution} =~ /^\d+$/
													&& $Q->{resolution} != 0?
													$Q->{resolution}: undef );

	my ($statval,$head,$meta) = getRRDasHash(sys=>$S,
																					 graphtype=>$Q->{graphtype},
																					 index=>$Q->{intf},item=>$Q->{item},
																					 mode=>"AVERAGE",
																					 start => $start,
																					 end => $end,
																					 resolution => $mayberesolution,
																					 add_minmax => $Q->{add_minmax}?1:0);

	bailout(message => "Failed to retrieve RRD data: $meta->{error}\n") if ($meta->{error});

	# no data? complain, don't produce an empty csv
	bailout(message => "No exportable data found!") if (!keys %$statval or !$meta->{rows_with_data});

	# graphtypes for custom service graphs are fixed and not found in the model system
	# note: format known here, in services.pl and nmis.pl
	my $heading;
	if ($Q->{graphtype} =~ /^service-custom-([a-z0-9\.-])+-([a-z0-9\._-]+)$/)
	{
		$heading = $2;
	}
	else
	{
		# fixme: really group in item???
		$heading = $S->graphHeading(graphtype=>$Q->{graphtype}, index=>$Q->{intf}, item=>$Q->{group});
	}
	# some graphtypes have a heading that includes an identifier (eg. most interface graphs),
	# but most others don't (e.g. Services, disks...), so we must include the intf/item in the filename
	my $filename  = join("-", ($Q->{node} || $Q->{group}), $heading, $Q->{intf}//$Q->{item}).".csv";
	$filename =~ s![/: '"]+!_!g;	# no /, no colons or quotes or spaces please

	$headeropts->{type} = "text/csv";
	$headeropts->{"Content-Disposition"} = "attachment; filename=\"$filename\"";

	print header($headeropts);

	my $csv = Text::CSV->new;
	# header line, then the goodies
	if (ref($head) eq "ARRAY" && @$head)
	{
		$csv->combine(@$head);
		print $csv->string,"\n";
	}

	# print any row that has at least one reading with known ds/header name
	foreach my $rtime (sort keys %{$statval})
	{
		if ( List::Util::any { defined $statval->{$rtime}->{$_} } (@$head) )
		{
			$csv->combine(map { $statval->{$rtime}->{$_} } (@$head));
			print $csv->string,"\n";
		}
	}
	exit 0;
}

sub typeStats {

	my $S = Sys::->new; # get system object
	$S->init(name=>$Q->{node}); # load node info and Model if name exists
	my $NI = $S->ndinfo;
	my $IF = $S->ifinfo;

	my $NT = loadLocalNodeTable();
	my $C = loadConfTable();

	print header($headeropts);

	print start_html(
		-title => "Statistics",
		-meta => { 'CacheControl' => "no-cache",
			'Pragma' => "no-cache",
			'Expires' => -1
			},
		-head=>[
			 Link({-rel=>'stylesheet',-type=>'text/css',-href=>"$C->{'styles'}"}),
		],
		-script => {-src => $C->{'jquery'}, -type=>"text/javascript"},
		);

	# verify access to this command/tool bar/button
	#
	if ( $AU->Require ) {
		# CheckAccess will throw up a web page and stop if access is not allowed
		# $AU->CheckAccess( "") or die "Attempted unauthorized access";
		if ( ! $AU->User ) {
			do_force_login("Authentication is required to access this function. Please login.");
			exit 0;
		}
	}


	# verify that user is authorized to view the node within the user's group list
	#
	if ( $Q->{node} ) {
		if ( ! $AU->InGroup($NT->{$Q->{node}}{group}) ) {
			print "Not Authorized to export rrd data on node $Q->{node} in group $NT->{$Q->{node}}{group}";
			return 0;
		}
	} elsif ( $Q->{group} ) {
		if ( ! $AU->InGroup($Q->{group}) ) {
			print "Not Authorized to export rrd data on nodes in group $Q->{group}";
			return 0;
		}
	}


	$Q->{intf} = $Q->{group} if $Q->{group} ne '';

	my $statval = getRRDStats(sys=>$S,graphtype=>$Q->{graphtype},mode=>"AVERAGE",start=>$Q->{start},end=>$Q->{end},index=>$Q->{intf},item=>$Q->{item});
	my $f = 1;
	my $starttime = returnDateStamp($Q->{start});
	my $endtime = returnDateStamp($Q->{end});

	print start_table;

	print Tr(td({class=>'header',colspan=>'11'},"NMIS RRD Graph Stats $NI->{system}{name} $IF->{$Q->{intf}}{ifDescr} $Q->{item} $starttime to $endtime"));

	foreach my $m (sort keys %{$statval}) {
		if ($f) {
			$f = 0;
			print Tr(td({class=>'header',align=>'center'},'metric'),
				eval { my $line;
					foreach my $s (sort keys %{$statval->{$m}}) {
						if ( $s ne "values" ) {
							$line .= td({class=>'header',align=>'center'},$s);
						}
					}
				return $line;
				}
			);
		}
		print Tr(td({class=>'info',align=>'right'},$m),
			eval { my $line;
				foreach my $s (sort keys %{$statval->{$m}}) {
					if ( $s ne "values" ) {
						$line .= td({class=>'info',align=>'right'},$statval->{$m}{$s});
					}
				}
				return $line;
			}
		);
	}

	print end_table,end_html;

}

# determine if the given graphtype belongs to systemhealth-modelled section,
# and if so, look up the labels
# args: sys object, graphtype
# returns: hash of is_systemhealth, section, header, title, labels (hashref)
sub get_graphtype_systemhealth
{
	my (%args) = @_;

	my ($S,$graphtype) = @args{"sys","graphtype"};
	my $NI = $S->ndinfo;
	my $M = $S->mdl;

	my %result = ( is_systemhealth => 0 );

	for my $index (keys %{$NI->{graphtype}})
	{
		my $thisgt = $NI->{graphtype}->{$index};
		next if (ref($thisgt) ne "HASH");

		for my $gtype (keys %{$thisgt})
		{
			if ( $thisgt->{$gtype} =~ /$graphtype/ # fixme: not equality?
					 and exists $M->{systemHealth}->{rrd}->{$gtype} )
			{
				$result{is_systemhealth} = 1;
				$result{section} = $gtype;
				my $mdlsection = $M->{systemHealth}->{sys}->{$gtype};

				$result{header} = $mdlsection->{headers};
				$result{header} =~ s/,.*$//;
				$result{title} = $result{header};

				if (exists $mdlsection->{snmp}->{ $result{header} }->{title}
						and $mdlsection->{snmp}->{ $result{header} }->{title} ne "")
				{
					$result{title} =  $mdlsection->{snmp}->{ $result{header} }->{title};
				}

				$result{labels} = { map { ($_ => $NI->{$gtype}->{$_}->{ $result{header} }) } (keys %{$NI->{$gtype}}) };
				return %result;
			}
		}
	}
	return %result;
}
