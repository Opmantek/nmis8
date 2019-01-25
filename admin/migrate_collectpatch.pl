#!/usr/bin/perl
our $VERSION = '1.0.0';

use strict;
use warnings;

use File::Basename;
use Term::ANSIColor ':constants';
use Getopt::Long;

use lib '/usr/local/nmis8/lib';
use NMIS;
use func;

my $name = basename($0);
my $usage = "Usage: $name [OPTIONS]

Options:
	-d|--dry      Dry run (don't save changes to Nodes.nmis)
	-q|--quiet    Don't print anything (except errors). Overrides -a.
	-h|--help     Show this usage message
	-v|--verbose  Verbose output (per node status)

Adds {collect_snmp} and {collect_wmi} properties to each node's entry in Nodes.nmis
where they are missing. WMI will be enabled if WMI credentials exist, and SNMP will
be enabled if community is set. If neither is found, both are set to off.";

# Options
my $opt_verbose;
my $opt_help;
my $opt_dry;
my $opt_quiet;
GetOptions(
	"help"		=> \$opt_help,
	"verbose"	=> \$opt_verbose,
	"dry"		=> \$opt_dry,
	"quiet"		=> \$opt_quiet,
) or die "Error processing command line arguents\n";

die "$usage\n" if $opt_help;

sub _log {
	print @_ unless $opt_quiet;
}

# Load NMIS tables
my $LNT = loadLocalNodeTable() or die "Error loading Nodes.nmis\n";
my $C = loadConfTable() or die "Error loading Config.nmis\n";

# Find nodes that are lacking a property 
my $num_nodes = keys $LNT;
my @nodesIgnored = grep {
	exists $LNT->{$_}{collect_snmp} and
	exists $LNT->{$_}{collect_wmi}
} keys $LNT;
my @nodesToMigrate = grep {
	!exists $LNT->{$_}{collect_snmp} or
	!exists $LNT->{$_}{collect_wmi}
} keys $LNT;
my @nodesError;
my @nodesOK;

# Start doing things
# Loop to check each node's config and set properties
foreach my $node (@nodesToMigrate) {
	my $cfg = $LNT->{$node};		
	my ($collect_wmi, $collect_snmp);

	# If WMI username and password are set, we can assume this node uses WMI
	$collect_wmi = (length $cfg->{wmipassword} and length $cfg->{wmipassword});

	# If SNMP community is set, we can assume this node uses SNMP
	$collect_snmp = length $cfg->{community} ? 1 : 0;

	# Add the properties to node table, print warning if both are missing (and -v given)
	_log UNDERLINE, "$node", RESET, "\n" if $opt_verbose;
	if ($collect_wmi or $collect_snmp) {
		if ($opt_verbose) {
			_log "collect_wmi:  " . ($collect_wmi ? 'true' : 'false') . "\n";
			_log "collect_snmp: " . ($collect_snmp ? 'true' : 'false') . "\n\n";
		}
		push @nodesOK, $node;
	} else {
		if ($opt_verbose) {
			_log RED, "WARNING: No SNMP community or WMI credentials found. Collection is turned OFF.\n\n", RESET;
		}
		push @nodesError, $node;
	}

	$LNT->{$node}{collect_snmp} = $collect_snmp ? 'true' : 'false';
	$LNT->{$node}{collect_wmi} = $collect_wmi ? 'true' : 'false';
}

# _log status report
_log GREEN BOLD "Finished. Migration status report:", RESET, "\n";
_log "Checked:  $num_nodes\n";
_log "Migrated: ", 0+@nodesOK, "\n";
_log "Ignored:  ", 0+@nodesIgnored, "\n";
_log "Off:      ", 0+@nodesError, "\n";

if (scalar @nodesError > 0) {
	_log "\n";
	_log BOLD CYAN "NOTE", RESET, "\n";
	_log 0+@nodesError . " node(s) are missing both SNMP community and WMI credentials.\n";
	_log "Not necessarily a problem, but be aware that no collection (besides from plugins) will be attempted on these nodes.\n";
	_log BOLD CYAN "\nNodes not collecting:\n", RESET;
	_log "$_\n" for @nodesError;
}

# Finally, write Nodes.nmis (unless it's a dry run)
unless ($opt_dry) {
	my $conf_dir = $C->{'<nmis_conf>'};
	#writeHashtoFile(file => "$conf_dir/Nodes.nmis", data => $LNT);
	_log "\nWrote changes to '$conf_dir/Nodes.nmis'.\n";
} else {
	_log "\n(", BOLD "DRY RUN", RESET, " - no changes are saved)\n" if $opt_dry;
}
