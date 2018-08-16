#!/usr/bin/perl
#
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
our $VERSION = "8.6.7G";

use FindBin;
use lib "$FindBin::Bin/../lib";

use NMIS::uselib;
use lib "$NMIS::uselib::rrdtool_lib";

use RRDs 1.4004;
use Data::Dumper;
use CGI qw(:standard *table *Tr *td *form *Select *div);

use func;
use Sys;
use NMIS;
use NMIS::RRDdraw;
use Auth;

my $q = new CGI; # This processes all parameters passed via GET and POST
my $Q = $q->Vars;

my $C;
if (!($C = loadConfTable(conf=>$Q->{conf},debug=>$Q->{debug}))) { exit 1; };

# bypass auth iff called from command line
$C->{auth_require} = 0 if (@ARGV);

# variables used for the security mods
my $headeropts = {type=>'text/html',expires=>'now'};
my $AU = Auth->new(conf => $C);  # Auth::new will reap init values from NMIS::config

if ($AU->Require) {
	exit 0 unless $AU->loginout(type=>$Q->{auth_type},username=>$Q->{auth_username},
					password=>$Q->{auth_password},headeropts=>$headeropts) ;
}

# check for remote request
if ($Q->{server} ne "")
{
	exit if requestServer(headeropts=>$headeropts);
}

# select function
if ($Q->{act} eq 'draw_graph_view')
{
	rrdDraw();
}
else
{
	error("Command unknown act=$Q->{act}");
}
exit 0;

sub error
{
	my ($msg) = @_;
	print header($headeropts), start_html(),
	($msg || "Request not found\n"), end_html;
}


# produce one graph
# args: pretty much all coming from a global $Q object
# returns: rrds::graph result array or empty
sub rrdDraw
{
	my %args = @_;

	# Break the query up for the names
	my $nodename = $Q->{node};
	my $debug = $Q->{debug};
	my $grp = $Q->{group};
	my $graphtype = $Q->{graphtype};
	my $graphstart = $Q->{graphstart}; # fixme not  used anywhere?

	my $width = $Q->{width};
	my $height = $Q->{height};
	my $start = $Q->{start};
	my $end = $Q->{end};
	my $intf = $Q->{intf};
	my $item = $Q->{item};
	my $filename = $Q->{filename};
	my $when = $Q->{time};

	my ($error, $graphret) = NMIS::RRDdraw::draw(node => $nodename,
																							 group => $grp,
																							 graphtype => $graphtype,
																							 intf => $intf,
																							 item => $item,
																							 width => $width,
																							 height => $height,
																							 filename => $filename,
																							 start => $start,
																							 end => $end,
																							 debug => $debug,
																							 time => $when);
	if ($error)
	{
		error("rrddraw failed: $error");
		return;
	}
	return $graphret;
}
