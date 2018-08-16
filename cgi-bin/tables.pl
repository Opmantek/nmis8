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
use strict;
our $VERSION="8.6.7G";

use FindBin;
use lib "$FindBin::Bin/../lib";

use CGI qw(:standard *table *Tr *td *form *Select *div);
use Data::Dumper;
use URI::Escape;
use Net::IP;

use NMIS;
use NMIS::UUID;
use Sys;
use func;
use csv;

use Auth;
use DBfunc;

my $q = new CGI; # This processes all parameters passed via GET and POST
my $Q = $q->Vars; # values in hash
my $C = loadConfTable(conf=>$Q->{conf},debug=>$Q->{debug});

die "failed to load configuration!\n" if (!$C or ref($C) ne "HASH" or !keys %$C);

# if arguments present, then called from command line
if ( @ARGV ) { $C->{auth_require} = 0; } # bypass auth


# variables used for the security mods
my $headeropts = {type=>'text/html',expires=>'now'};
my $AU = Auth->new(conf => $C);

if ($AU->Require) {
	exit 0 unless $AU->loginout(type=>$Q->{auth_type},username=>$Q->{auth_username},
					password=>$Q->{auth_password},headeropts=>$headeropts) ;
}
else
{
	# that's the command line/debugger scenario, where we assume a full admin
	$AU->SetUser("nmis");
}
# check for remote request
if ($Q->{server} ne "") { exit if requestServer(headeropts=>$headeropts); }

my $formid = $Q->{table} ? "nmis$Q->{table}" : "nmisTable";

# this cgi script defaults to widget mode ON
my $widget = getbool($Q->{widget},"invert")? "false" : "true";
my $wantwidget = $widget eq "true";

#======================================================================

# select function

if ($Q->{act} eq 'config_table_menu') { 			menuTable();
} elsif ($Q->{act} eq 'config_table_add') { 		editTable();
} elsif ($Q->{act} eq 'config_table_view') { 		viewTable();
} elsif ($Q->{act} eq 'config_table_show') { 		showTable();
} elsif ($Q->{act} eq 'config_table_edit') { 		editTable();
} elsif ($Q->{act} eq 'config_table_delete') { 		viewTable();
} elsif ($Q->{act} eq 'config_table_doadd') { 		if (doeditTable()) { menuTable(); }
} elsif ($Q->{act} eq 'config_table_doedit') { 		if (doeditTable()) { menuTable(); }
} elsif ($Q->{act} eq 'config_table_dodelete') { 	dodeleteTable(); menuTable();
} else { notfound(); }

sub notfound {
	print header($headeropts);
	print "Tables: ERROR, act=$Q->{act}, node=$Q->{node}, intf=$Q->{intf}\n";
	print "Request not found\n";
}

exit;

#==================================================================
#

# loads the file with the actual values
sub loadReqTable
{
	my %args = @_;
	my $table = $args{table};
	my $msg = $args{msg};

	my $T;

	my $db = "db_".lc($table)."_sql";
	if (getbool($C->{$db})) {
		$T = DBfunc::->select(table=>$table); # full table
	} else {
		$T = loadTable(dir=>'conf',name=>$table);
	}

	if (!$T and !getbool($msg,"invert")) {
		print Tr(td({class=>'error'},"Error on loading table $table"));
		return;
	}
	return $T;
}

sub menuTable{

	my $table = $Q->{table};
	#start of page
	print header($headeropts);
	pageStartJscript(title => "View Table $table") if (getbool($widget,"invert"));

	$AU->CheckAccess("Table_${table}_view");

	my $LNT;
	if ( $table eq "Nodes" ) {
		$LNT = loadLocalNodeTable(); # load from file or db
	}

	print <<EOF;
<script>
clearInterval(null);
</script>
EOF

	my $bt;
	my $T;
	$T = loadReqTable(table=>$table); # load requested table

	my $CT;
	# load configuration of table
	return if (!($CT = loadCfgTable(table=>$table, user => $AU->{user})));

	print start_table;

	my $url = url(-absolute=>1)."?conf=$Q->{conf}&table=$table";

	# print short info
	#print header
	print Tr( eval { my $line; my $colspan = 1;
			for my $ref ( @{$CT}) { # trick for order of header items
				for my $item (keys %{$ref}) {
					if ($ref->{$item}{display} =~ /header/ ) {
						$line .= td({class=>'header',align=>'center'},$ref->{$item}{header});
						$colspan++;
					}
				}
			}
			$line .= td({class=>'header',align=>'center'},'Action',
					eval {
						if ($AU->CheckAccess("Table_${table}_rw","check")) {
							return ' > '.a({href=>"$url&act=config_table_add&widget=$widget"},'add'),
						} else { return ''; }
					}
				);
			return Tr(th({class=>'title',colspan=>$colspan},"Table $table")).$line;
		});
	# print data
	for my $k (sort {lc($a) cmp lc($b)} keys %{$T}) {
		my $display = 1;
		if ( $table eq "Nodes" ) {
			$display = 0 unless $AU->InGroup($LNT->{$T->{$k}{name}}{group});
		}
		print start_Tr if $display;
		for my $ref ( @{$CT}) { # trick for order of header items
			for my $item (keys %{$ref}) {
				if ($ref->{$item}{display} =~ /header/ ) {
					print td({class=>'info Plain'}, escapeHTML($T->{$k}{$item})) if $display;
				}
			}
		}

		my $safekey = uri_escape($k);

		if ($AU->CheckAccess("Table_${table}_rw","check")) {
			$bt = '&nbsp;'
					# polling-policy: not editable, only add and delete
					. ($table eq "Polling-Policy"? '' :
						 (a({href=>"$url&act=config_table_edit&key=$safekey&widget=$widget"},
								'edit') . '&nbsp;'))
					. a({href=>"$url&act=config_table_delete&key=$safekey&widget=$widget"},
							'delete');
			# if looking at the users table AND lockout feature is enabled, offer a failure count reset
			if ($table eq "Users" && $C->{auth_lockout_after})
			{
				$bt .= '&nbsp;' . a({href => "$url&act=config_table_reset&key=$safekey&widget=$widget"},
														"reset login count");
			}
		} else {
			$bt = '';
		}

		if ($display)
		{
			print td({class=>'info Plain'},a({href=>"$url&act=config_table_view&key=$safekey&widget=$widget"},'view'),$bt);
			print end_Tr;
		}
	}

	print end_table;

	pageEnd() if (getbool($widget,"invert"));

}

# shows the table contents, optionally with a delete button
sub viewTable {

	my $table = $Q->{table};
	my $key = $Q->{key};

	#start of page
	print header($headeropts);
	pageStartJscript(title => "View Table $table") if (getbool($widget,"invert"));

	$AU->CheckAccess("Table_${table}_view");

	my $T;
	return if (!($T = loadReqTable(table=>$table))); # load requested table

	my $CT = loadCfgTable(table=>$table, user => $AU->{user}); # load table configuration
	# not delete -> we assume view
	my $action= $Q->{act} =~ /delete/? "config_table_dodelete": "config_table_menu";


  # the get() code doesn't work without a query param, nor does it work with all params present
	# conversely the non-widget mode needs post inputs as query params are ignored
	print start_form(-id=>"$formid", -href=>url(-absolute=>1)."?");
	print hidden(-override => 1, -name => "conf", -value => $Q->{conf})
			. hidden(-override => 1, -name => "act", -value => $action)
			. hidden(-override => 1, -name => "widget", -value => $widget)
			. hidden(-override => 1, -name => "table", -value => $table)
			. hidden(-override => 1, -name => "key", -value => $key)
			. hidden(-override => 1, -name => "cancel", -value => '', -id=> "cancelinput");

	print start_table;
	print Tr(td({class=>'header',colspan=>'2'},"Table $table"));

	# print items of table
	for my $ref ( @{$CT}) { # trick for order of header items
		for my $item (keys %{$ref}) {
			print Tr(td({class=>'header',align=>'center'},
									escapeHTML($ref->{$item}{header})),
							 td({class=>'info Plain'},
									escapeHTML($ref->{$item}->{display} =~ /password/?
														 "<hidden>" : $T->{$key}{$item})));
		}
	}

	if ($Q->{act} =~ /delete/)
	{
		# Polling Policy: should not be deletable if there are nodes with this policy
		my $forbidden;
		if ($table eq "Polling-Policy")
		{
			my $LNT = loadLocalNodeTable();
			my $problematic = scalar grep($_->{polling_policy} eq $key, values %$LNT);
			$forbidden = "Policy \"$key\" is used by $problematic nodes, cannot be deleted!" if ($problematic);
		}

		if ($forbidden)
		{
			print Tr(td({class=>"Error", colspan => 2 }, $forbidden,
									'&nbsp;', button(-name=>'button',
																	 onclick=> '$("#cancelinput").val("true");'
																	 . ($wantwidget? "get('$formid');" : 'submit();'),
																	 -value=>"Ok")));
		}
		else
		{
			print Tr(td('&nbsp;'),
							 td(button(-name=>"button",onclick => ($wantwidget? "get('$formid');" : 'submit()'),
												 -value=>"Delete"),
									"Are you sure",
									# need to set the cancel parameter
									button(-name=>'button',
												 onclick=> '$("#cancelinput").val("true");'
												 . ($wantwidget? "get('$formid');" : 'submit();'),
												 -value=>"Cancel")));
		}
	}
	else
	{
			# in mode view submitting the form straight is side-effect free and ok.
			print Tr(td('&nbsp;'),
							 td(
									 button(-name=>'button',
													onclick=> ($wantwidget? "get('$formid');" : 'submit()'),
													-value=>"Ok")));
	}

	print end_table;
	print end_form;
	pageEnd() if (getbool($widget,"invert"));
}

sub showTable {

	my $table = $Q->{table};
	my $key = $Q->{key};
	my $node = $Q->{node};
	my $found = 0;

	#start of page
	print header($headeropts);
	pageStartJscript(title => "Show Table $table") if (getbool($widget,"invert"));

	$AU->CheckAccess("Table_${table}_view");

	my $T;
	return if (!($T = loadReqTable(table=>$table))); # load requested table

	my $CT = loadCfgTable(table=>$table, user => $AU->{user}); # load table configuration

	my $S = Sys::->new;
	$S->init(name=>$node,snmp=>'false');

	print createHrButtons(node=>$node, system=>$S, refresh=>$Q->{refresh}, widget=>$widget, conf => $Q->{conf}, AU => $AU);

	print start_table;
	print Tr(th({class=>'title',colspan=>'2'},"Table $table"));

	# try to find a match
	my $pos = length($key)+1;
	my $k = lc $key;
	$k =~ tr/+,./ /; # remove

	while ($pos > 0 && $found == 0) {
		my $s = substr($k,0,$pos);
		for my $t (keys %{$T}) {
			if ($s eq lc($t)) {
				$found = 1;
				# print items of table
				for my $ref ( @{$CT}) { # trick for order of header items
					for my $item (keys %{$ref}) {
						print Tr(td({class=>'header',align=>'center'},escapeHTML($ref->{$item}{header})),
							td({class=>'info Plain'},escapeHTML($T->{$t}{$item})));
					}
				}
				last;
			}
		}
		$pos = rindex($k," ",($pos - 1));
	}
	if (!$found) {
		print Tr(td({class=>'error'},"\'$key\' does not exist in table $table"));
	}

	print end_table;
	print end_form;
	pageEnd() if (getbool($widget,"invert"));
}

sub editTable
{
	my $table = $Q->{table};
	my $key = $Q->{key};

	# polling policy: add and delete, no edit
	return menuTable() if ($table eq "Polling-Policy" and $Q->{act} eq 'config_table_edit');

	my @hash; # items of key

	#start of page
	print header($headeropts);
	pageStartJscript(title => "Edit Table $table") if (getbool($widget,"invert"));

	$AU->CheckAccess("Table_${table}_rw");

	my $T;
	return if (!($T = loadReqTable(table=>$table,msg=>'false')) and $Q->{act} =~ /edit/); # load requested table

	my $CT = loadCfgTable(table=>$table, user => $AU->{user});

	my $func = ($Q->{act} eq 'config_table_add') ? 'doadd' : 'doedit';
	my $button = ($Q->{act} eq 'config_table_add') ? 'Add' : 'Edit';
	my $url = url(-absolute=>1)."?";

  # the get() code doesn't work without a query param, nor does it work with all params present
	# conversely the non-widget mode needs post inputs as query params are ignored
	print start_form(-name=>"$formid",-id=>"$formid",-href=>"$url")
			. hidden(-override => 1, -name => "conf", -value => $Q->{conf} )
			. hidden(-override => 1, -name => "act", -value => "config_table_$func")
			. hidden(-override => 1, -name => "table" , -value => $table )
			. hidden(-override => 1, -name => "widget", -value => $widget)
			. hidden(-override => 1, -name => "cancel", -value => '', -id=> "cancelinput")
 			. hidden(-override => 1, -name => "update", -value => '', -id=> "updateinput");


	my $anyMandatory = 0;
	print start_table;
	print Tr(th({class=>'title',colspan=>'2'},"Table $table"));

	for my $ref ( @{$CT})
	{
		for my $item (keys %{$ref})
		{
			my $thisitem = $ref->{$item}; # table config record for this item
			my $thiscontent = $T->{$key}->{$item}; # table CONTENT for this item

			my $mandatory = "";
			my $headerclass = "header";
			my $headspan = 1;
			if ( getbool($thisitem->{mandatory}) )
			{
				$mandatory = " <span style='color:#FF0000'>*</span>";
				$anyMandatory = 1;
			}

			if ( exists $thisitem->{special} and $thisitem->{special} eq "separator" )
			{
				$headerclass = "heading4";
				$headspan = 2;
				print Tr(td({class=>$headerclass,align=>'center',colspan=>$headspan},
										escapeHTML($thisitem->{header}).$mandatory));
			}
			# things tagged editonly are ONLY editable, NOT settable initially on add
			elsif ($func eq "doadd" and $thisitem->{display} =~ /editonly/)
			{
				# do nothing, skip this thing's row completely
			}
			else
			{
				print Tr(td({class=>$headerclass,align=>'center',colspan=>$headspan},
										escapeHTML($thisitem->{header}).$mandatory),
								 eval {
									 my $line;
									 if ($thisitem->{display} =~ /key/)
									 {
										 push @hash,$item;
									 }

									 # things tagged key are NOT editable, only settable initially on add.
									 # on edit the text is static
									 if ($func eq 'doedit' and $thisitem->{display} =~ /key/)
									 {
										 $line .= td({class=>'header'}, escapeHTML($thiscontent));
										 $line .= hidden("-name"=>$item, "-default"=>$thiscontent, "-override"=>'1');
									 }
									 elsif ($thisitem->{display} =~ /textbox/)
									 {
										 my $value = ($thiscontent or $func eq 'doedit') ? $thiscontent : $thisitem->{value}[0];
										 $line .= td(textarea(-name=> $item, -value=>$value,
																					-style=> 'width: 95%;',
																					-rows => 3,
																					-columns => ($wantwidget? 35 : 70)));
									 }
									 elsif ($thisitem->{display} =~ /(text|password)/)
									 {
										 my $wantpassword = $1 eq "password";
										 my $value = ($thiscontent or $func eq 'doedit') ? $thiscontent : $thisitem->{value}[0];

										 $line .= td(
											 $wantpassword? password_field(-name=>$item, -value=>$value,
																										 -style=> 'width: 95%;',
																										 -size=>  ($wantwidget? 35 : 70))
											 : textfield(-name=>$item, -value=>$value,
																	 -style=> 'width: 95%;',
																	 -size=>  ($wantwidget? 35 : 70)));
									 }
									 elsif ($thisitem->{display} =~ /readonly/) {
										 my $value = ($thiscontent or $func eq 'doedit') ? $thiscontent : $thisitem->{value}[0];

										 $line .= td(escapeHTML($value));
										 $line .= hidden(-name=>$item, -default=>$value, -override=>'1');
									 }
									 elsif ($thisitem->{display} =~ /pop/) {
										 #print STDERR "DEBUG editTable: popup -- item=$item\n";
										 $line .= td(popup_menu(
																	 -name=> $item,

																	 -values=>$thisitem->{value},
																	 -style=>'width: 95%;',
																	 -default=>$thiscontent));
									 }
									 elsif ($thisitem->{display} =~ /scrol/) {
										 my @items = split(/,/,$T->{$key}{$item});
										 $line.= td(scrolling_list(-name=>"$item", -multiple=>'true',
																							 -style=>'width: 95%;',
																							 -size=>'6',
																							 -values=>$thisitem->{value},
																							 -default=>\@items));
									 }
									 return $line;
								 });
			}
		}
	}

	print hidden(-name=>'hash', -default=>join(',',@hash),-override=>'1');
	print Tr(td({class=>'',align=>'center',colspan=>'2'},"<span style='color:#FF0000'>*</span> mandatory fields."));
	print Tr(td('&nbsp;'),
					 td(
							 ($table eq 'Nodes' ?
								# set update to true, then submit
							 button(-name=>"button",
											onclick => '$("#updateinput").val("true");'
											. ($wantwidget? "javascript:get('$formid');" : 'submit();' ),
											-value=>"$button and Update Node") : "&nbsp;" ),
							 # the submit/add/edit button just submits the form as-is
							 button(-name=>"button", onclick => ( $wantwidget ? "get('$formid');" : 'submit();' ),
											-value=>$button),
							 # the cancel button needs to set the cancel input
							 button(-name=>'button', onclick=> '$("#cancelinput").val("true");'
											. ($wantwidget? "get('$formid');" : 'submit();'),
											-value=>"Cancel")));

	print end_table;
	print end_form;
	pageEnd() if (getbool($widget,"invert"));
}

# this function performs the actual modification of the files with values
# called for both adding and editing
sub doeditTable
{
	my $table = $Q->{table};
	my $hash = $Q->{hash};

	return 1 if (getbool($Q->{cancel}));

	# no editing for the Polling Policy, only add and delete
	return 1 if ($table eq "Polling-Policy"
							 and $Q->{act} eq "config_table_doedit");

	my $new_name;									# only needed for nodes table

	$AU->CheckAccess("Table_${table}_rw",'header');

	my $T = loadReqTable(table=>$table, msg=>'false');

	my $CT = loadCfgTable(table=>$table, user => $AU->{user});
	my $TAB = loadGenericTable('Tables');

	# combine key from values, values separated by underscrore
	my $key = join('_', map { $Q->{$_} } split /,/,$hash );
	$key = lc($key) if (getbool($TAB->{$table}{CaseSensitiveKey},"invert")); # let key of table Nodes equal to name

	# key and 'name' property values must match up, and be space-stripped, for both users and nodes
	if ($table eq "Nodes" or $table eq "Users")
	{
		$key = stripSpaces($key);
	}

	# test for invalid or existing key
	if ($Q->{act} =~ /doadd/)
	{
		if (exists $T->{$key}) {
			print header({-type=>"text/html",-expires=>'now'});
			print Tr(td({class=>'error'} , escapeHTML("Key $key already exists in table")));
			return 0;
		}
		if ($key eq '') {
			print header($headeropts);
			print Tr(td({class=>'error'} , escapeHTML("Field \'$hash\' must be filled in table $table")));
			return 0;
		}
	}

	# make room, make room! accessing a nonexistent $T->{$key} does NOT attach it to $T...
	my $thisentry  = $T->{$key} ||= {};

	my $V;												# fixme: deprecated, in sql db mode only

	# store new values in table structure
	for my $ref ( @{$CT})
	{
		for my $item (keys %{$ref})
		{
			my $thisitem = $ref->{$item}; # table config record for this item

			# do not save anything for separator entries, they're just for visual use
			if (defined($thisitem->{special}) && $thisitem->{special} eq "separator")
			{
				delete $thisentry->{$item};
				next;
			}
			# but handle multi-valued inputs correctly!
			# with Vars we get that as packed string of null-separated entries
			# if submission was under widget mode, then javascript:get() will have transformed
			# any such into comma-sep data - but for a standalone submission that does not happen.
			my $value = join(",", unpack("(Z*)*", stripSpaces($Q->{$item})));
			$thisentry->{$item} = $V->{$item} = $value;

			# and validate if told to
			next if (ref($thisitem->{validate}) ne "HASH");

			# supported validation mechanisms:
			# "int" => [ min, max ], undef can be used for no min/max - rejects X < min or > max.
			# "float" => [ min, max, above, below ] - rejects X < min or X <= above, X > max or X >= below
			#   that's required to express 'positive float' === strictly above zero: [0 or undef,dontcare,0,dontcare]
			# "resolvable" => [ 4 or 6 or 4, 6] - accepts ip of that type or hostname that resolves to that ip type
			# "int-or-empty", "float-or-empty", "resolvable-or-empty", "regex-or-empty" work like their namesakes,
			# but accept nothing/blank/undef as well.
			# "regex" => qr//,
			# "ip" => [ 4 or 6 or 4, 6],
			# "onefromlist" => [ list of accepted values ] or undef - if undef, 'value' list is used
			#   accepts exactly one value
			# "multifromlist" => [ list of accepted values ] or undef, like fromlist but more than one
			#   accepts any number of values from the list, including none whatsoever!
			# more than one rule possible but likely not very useful
			for my $valtype (sort keys %{$thisitem->{validate}})
			{
				my $valprops = $thisitem->{validate}->{$valtype};

				if ($valtype =~ /^(int|float)(-or-empty)?$/)
				{
					my ($actualtype, $emptyisok) = ($1,$2);

					# checks required if not both emptyisok and blank input
					if (!$emptyisok or (defined($value) and $value ne ""))
					{
						return validation_abort($item, "'$value' is not an integer!")
								if ($actualtype eq "int" and int($value) ne $value);
						return validation_abort($item, "'$value' is not a floating point number!")
								# integer or full ieee floating point with optional exponent notation
								if ($actualtype eq "float"
										and $value !~ /^([+-]?)(?=\d|\.\d)\d*(\.\d*)?([Ee]([+-]?\d+))?$/);

						my ($min,$max,$above,$below) = (ref($valprops) eq "ARRAY"? @{$valprops}
																						: (undef,undef,undef,undef));
						return validation_abort($item, "$value below minimum $min!")
								if (defined($min) and $value < $min);
						return validation_abort($item,"$value above maximum $max!")
								if (defined($max) and $value > $max);

						# integers don't subdivide infinitely precisely so above and below not needed
						if ($actualtype eq "float")
						{
							return validation_abort($item, "$value is not above $above!")
									if (defined($above) and $value <= $above);

							return validation_abort($item, "$value is not below $below!")
									if (defined($below) and $value >= $below);
						}
					}
				}
				elsif ($valtype =~ /^regex(-or-empty)?$/)
				{
					my $emptyisok = $1;

					if (!$emptyisok or (defined($value) and $value ne ""))
					{
						my $expected = ref($valprops) eq "Regexp"? $valprops : qr//; # fallback will match anything
						return validation_abort($item, "'$value' didn't match regular expression!")
								if ($value !~ $expected);
					}
				}
				elsif ($valtype eq "ip")
				{
					my @ipversions = ref($valprops) eq "ARRAY"? @$valprops : (4,6);

					my $ipobj = Net::IP->new($value);
					return validation_abort($item, "'$value' is not a valid IP address!")
							if (!$ipobj);

					return validation_abort($item, "'$value' is IP address of the wrong type!")
							if (($ipobj->version == 6 and !grep($_ == 6, @ipversions))
									or $ipobj->version == 4 and !grep($_ == 4, @ipversions));
				}
				elsif ($valtype =~ /^resolvable(-or-empty)?$/)
				{
					my $emptyisok = $1;

					if (!$emptyisok or (defined($value) and $value ne ""))
					{
						return validation_abort($item, "'$value' is not a resolvable name or IP address!")
								if (!$value);

						my @ipversions = ref($valprops) eq "ARRAY"? @$valprops : (4,6);

						my $alreadyip = Net::IP->new($value);
						if ($alreadyip)
						{
							return validation_abort($item, "'$value' is IP address of the wrong type!")
									if (!grep($_ == $alreadyip->version, @ipversions));
							# otherwise, we're happy...
						}
						else
						{
							my @addresses = NMIS::resolve_dns_name($value);
							return validation_abort($item, "DNS failed to resolve '$value'!")
									if (!@addresses);

							my @addr_objs = map { Net::IP->new($_) } (@addresses);
							my $goodones;
							for my $type (4,6)
							{
								$goodones += grep($_->version == $type, @addr_objs) if (grep($_ == $type, @ipversions));
							}
							return validation_abort($item,
																			"'$value' does not resolve to an IP address of the right type!")
									if (!$goodones);
						}
					}
				}
				elsif ($valtype eq "onefromlist" or $valtype eq "multifromlist")
				{
					# either explicit list of acceptables, or the 'value' config item
					my @acceptable = ref($valprops) eq "ARRAY"? @$valprops :
							ref($thisitem->{value}) eq "ARRAY"? @{$thisitem->{value}}: ();
					return validation_abort($item, "no validation choices configured!")
							if (!@acceptable);

					# for multifromlist assume that value is now comma-separated. *sigh*
					# for onefromlist values with colon are utterly unspecial *double sigh*
					my @mustcheckthese = ($valtype eq "multifromlist")? split(/,/, $value) : $value;
					for my $oneofmany (@mustcheckthese)
					{
						return validation_abort($item, "'$oneofmany' is not in list of acceptable values!")
								if (!List::Util::any { $oneofmany eq $_ } (@acceptable));
					}
				}
				else
				{
					return validation_abort($item, "unknown validation type \"$valtype\"");
				}
			}
		}
	}

	# nodes requires special handling, extra sanity checks, and dealing with rename
 	if ($table eq 'Nodes')
	{
		# ensure a uuid is present
		$thisentry->{uuid} ||= NMIS::UUID::getUUID($key);
		$V->{uuid} ||= $thisentry->{uuid};

		# keep the new_name from being written to the config file
		$new_name = $thisentry->{new_name};
		delete $thisentry->{new_name};

		# renaming?
		if ($new_name && $new_name ne $thisentry->{name})
		{

			# this rewrites nodes.nmis twice, by necessity; backs out nodes.nmis if unsuccessful
			my ($error,$message) = NMIS::rename_node(old => $thisentry->{name}, new => $new_name,
																							 originator => "tables.pl.editNodeTable");
			if ($error)
			{
				print header($headeropts),
				Tr(td({class=>'error'},
							escapeHTML("ERROR, renaming node \'$thisentry->{name}\' to \'$new_name\' failed: $message")));
				return 0;
			}
			$key = $new_name;
		}
		# nope, just a general modification so write out the data...
		else
		{
			writeTable(dir=>'conf',name=>$table, data=>$T);
		}
		cleanEvent($key, "tables.pl.editNodeTable");

		# ...before possibly running an update on that node
		if (getbool($Q->{update}))
		{
			doNodeUpdate(node=>$key);
			return 0;
		}

		# don't let the generic code (re|over)write the nodes table again...
		return 1;
	}

	# the non-nodes.nmis case
	my $db = "db_".lc($table)."_sql";
	if ( getbool($C->{$db}) )
	{
		my $stat;
		$V->{index} = $key; # add this column
		if ($Q->{act} =~ /doadd/) {
			$stat = DBfunc::->insert(table=>$table,data=>$V);
		} else {
			$stat = DBfunc::->update(table=>$table,data=>$V,index=>$key);
		}
		if (!$stat)
		{
			print header({-type=>"text/html",-expires=>'now'});
			print Tr(td({class=>'error'} , escapeHTML(DBfunc::->error())));
			return 0;
		}
	}
	else
	{
		writeTable(dir=>'conf',name=>$table, data=>$T);
	}
	return 1;
}

# print (negative) html response
sub validation_abort
{
	my ($item, $message) = @_;

	print header($headeropts),
	Tr(td({class=>'error'} , escapeHTML("'$item' failed to validate: $message")));
	return undef;
}

sub dodeleteTable {
	my $table = $Q->{table};
	my $key = $Q->{key};

	return 1 if (getbool($Q->{cancel}));

	$AU->CheckAccess("Table_${table}_rw",'header');

	my $T = loadReqTable(table=>$table);
	my $db = "db_".lc($table)."_sql";
	if (getbool($C->{$db}) ) {
		if (!(DBfunc::->delete(table=>$table,index=>$key))) {
			print header({-type=>"text/html",-expires=>'now'});
			print Tr(td({class=>'error'} ,escapeHTML(DBfunc::->error())));
			return 0;
		}
	} else {
		# remote key
		my $TT;
		foreach (keys %{$T}) {
			if ($_ ne $key) { $TT->{$_} = $T->{$_}; }
		}

		writeTable(dir=>'conf',name=>$table,data=>$TT);
	}

	# make sure to remove events for deleted nodes
	if ($table eq "Nodes")
	{
		cleanEvent($key,"tables.pl.editNodeTable");
	}
}

sub doNodeUpdate {
	my %args = @_;
	my $node = $args{node};

	# note that this will force nmis.pl to skip the pingtest as we are a non-root user !!
	# for now - just pipe the output of a debug run, so the user can see what is going on !

	# now run the update and display
	print header($headeropts);
	pageStartJscript(title => "Run update on $node") if (getbool($widget,"invert"));

	print start_form(-id => "$formid",
									 -href => url(-absolute=>1)."?")
			. hidden(-override => 1, -name => "conf", -value => $Q->{conf})
			. hidden(-override => 1, -name => "act", -value => "config_table_menu")
			. hidden(-override => 1, -name => "widget", -value => $widget)
			. hidden(-override => 1, -name => "table", -value => $Q->{table});


#									 conf=$Q->{conf}&act=config_table_menu&table=$Q->{table}&widget=$widget",
#									 -action => url(-absolute=>1)."?conf=$Q->{conf}&act=config_table_menu&table=$Q->{table}&widget=$widget" );

	print table(Tr(td({class=>'header'}, escapeHTML("Completed web user initiated update of $node")),
				td(button(-name=>'button', -onclick=> ($wantwidget? "get('$formid')" : "submit();" ),
									-value=>'Ok'))));
	print "<pre>\n";
	print escapeHTML("Running update on node $node\n\n\n");

	my $pid = open(PIPE, "-|");
	if (!defined $pid)
	{
		print "Error: cannot fork: $!\n";
	}
	elsif (!$pid)
	{
		# child
		open(STDERR, ">&STDOUT"); # stderr to go to stdout, too.
		exec("$C->{'<nmis_bin>'}/nmis.pl","type=update", "node=$node", "info=true", "force=true");
		die "Failed to exec: $!\n";
	}
	select((select(PIPE), $| = 1)[0]);			# unbuffer pipe
	select((select(STDOUT), $| = 1)[0]);		# unbuffer stdout

	while ( <PIPE> ) {
		print escapeHTML($_);
	}
	close(PIPE);
	print "\n</pre>\n<pre>\n";
	print escapeHTML("Running collect on node $node\n\n\n");

	$pid = open(PIPE, "-|");
	if (!defined $pid)
	{
		print "Error: cannot fork: $!\n";
	}
	elsif (!$pid)
	{
		# child
		open(STDERR, ">&STDOUT"); # stderr to go to stdout, too.
		exec("$C->{'<nmis_bin>'}/nmis.pl","type=collect", "node=$node", "info=true");
		die "Failed to exec: $!\n";
	}
	select((select(PIPE), $| = 1)[0]);			# unbuffer pipe

	while ( <PIPE> ) {
		print escapeHTML($_);
	}
	close(PIPE);
	print "\n</pre>\n";

	print table(Tr(td({class=>'header'},escapeHTML("Completed web user initiated update of $node")),
				td(button(-name=>'button', -onclick=> ($wantwidget? "get('$formid')" : "submit();" ),
									-value=>'Ok'))));
	print end_form;
	pageEnd() if (getbool($widget,"invert"));
}
