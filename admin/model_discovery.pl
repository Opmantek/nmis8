#!/usr/bin/perl
#
## $Id: modelcheck.pl,v 1.1 2011/11/16 01:59:35 keiths Exp $
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

# Auto configure to the <nmis-base>/lib
use FindBin;
use lib "$FindBin::Bin/../lib";
 
use strict;
use func;
use NMIS;
use Sys;
use snmp 1.1.0;									# for snmp-related access
use Data::Dumper;
use NMIS::Timing;

my $modelTemplate = "$FindBin::Bin/../models/Model-Default-HC.nmis";

if ( $ARGV[0] eq "" ) {
	usage();
	exit 1;
}

my $t = NMIS::Timing->new();

print $t->elapTime(). " Begin\n";

# Variables for command line munging
my %arg = getArguements(@ARGV);

if ( not defined $arg{node} ) {
	print "ERROR: need a node to check\n";
	usage();
	exit 1;
}

my $node = $arg{node};
my $file = $arg{file};
my $newModelName = $arg{model};
my $common_exclude = $arg{common_exclude};

# Set debugging level.
my $debug = setDebug($arg{debug});
my $verbose = getbool($arg{verbose});

# load configuration table
my $C = loadConfTable(conf=>$arg{conf},debug=>$debug);

print $t->elapTime(). " What Existing Modelling Applies to $node\n" if $verbose;

# load configuration table
my $C = loadConfTable(conf=>undef,debug=>$debug);

my $pass = 0;
my $dirpass = 1;
my $dirlevel = 0;
my $maxrecurse = 200;
my $maxlevel = 10;

my $bad_file;
my $bad_dir;
my $file_count;
my $mib_count;
my $extension = "nmis";

my $indent = 0;
my @path;
my $rrdlen = 19;

my $curModel;
my $models;
my $vendors;
my $modLevel;
my @topSections;
my @oidList;

# needs feature to match enterprise, e.g. only do standard mibs and my vendor mibs.


my @discoverList;
my $discoveryResults;
my %graphTypes;
my %nodeSummary;
my $mibs = loadMibs($C);

print $t->elapTime(). " Load all the NMIS models.\n" if $verbose;
processDir(dir => $C->{'<nmis_models>'});
print $t->elapTime(). " Done with Models.  Processed $file_count NMIS Model files.\n" if $verbose;

print $t->elapTime(). " Processing MIBS on node $node.\n" if $verbose;
processNode($node);
print $t->elapTime(). " Done with node.  Tried $mib_count SNMP MIBS.\n" if $verbose;

print Dumper $discoveryResults if $debug;

printDiscoverySummary();

printDiscoveryResults($file) if defined $file;

#print Dumper(\@discoverList);

sub processNode {
	my $node = shift;

	my $LNT = loadLocalNodeTable();

	if ( not getbool($LNT->{$node}{active})) {
		die "Node $node is not active, will die now.\n";
	}
	else {
		print $t->elapTime(). " Working on SNMP Discovery for $node\n" if $verbose;
	}

	my %doneIt;
	# initialise the node.
	my $S = Sys::->new; # get system object
	$S->init(name=>$node,snmp=>'true'); # load node info and Model if name exists
	my $NI = $S->ndinfo;
	my $IF = $S->ifinfo;
	my $NC = $S->ndcfg;
	my $max_repetitions = $NC->{node}->{max_repetitions} || $C->{snmp_max_repetitions};

	$nodeSummary{node} = $node;
	$nodeSummary{sysDescr} = $NI->{system}{sysDescr};
	$nodeSummary{nodeModel} = $NI->{system}{nodeModel};

	my %nodeconfig = %{$NC->{node}}; # copy required because we modify it...
	$nodeconfig{host_addr} = $NI->{system}{host};

	my $snmp = snmp->new(name => $node);
	print Dumper $snmp if $debug;

	if (!$snmp->open(config => \%nodeconfig ))
	{
		print "ERROR: Could not open SNMP session to node $node: ".$snmp->error;
	}
	else
	{
		if (!$snmp->testsession)
		{
			logMsg"ERROR: Could not retrieve SNMP vars from node $node: ".$snmp->error;
		}
		else
		{
			my $count = 0;
			foreach my $thing (@discoverList) {
				my $works = undef;
				
				if ( $thing->{type} eq "systemHealth" and not defined $doneIt{$thing->{index_oid}}) {
					++$count;
					print $t->elapTime(). " $count System Health Discovery on $node of MIB in $thing->{file}::$thing->{path}\n" if $verbose;
					++$mib_count;
					my $result = $snmp->gettable($thing->{index_oid},$max_repetitions);
					$doneIt{$thing->{index_oid}} = 1;
					if ( defined $result ) {
						$works = "YES";
						print $t->elapTime(). " MIB SUPPORTED: $thing->{indexed} $thing->{index_oid}\n" if $verbose;
						print Dumper $thing if $debug;
						print Dumper $result if $debug;
					}
					else {
						$works = "NO";
						print $t->elapTime(). " MIB NOT SUPPORTED: $thing->{indexed} $thing->{index_oid}\n" if $verbose;
					}
					print "\n" if $verbose;
					
					$discoveryResults->{$thing->{index_oid}}{node} = $node;
					#$discoveryResults->{$thing->{index_oid}}{sysDescr} = $NI->{system}{sysDescr};
					$discoveryResults->{$thing->{index_oid}}{nodeModel} = $NI->{system}{nodeModel};
					$discoveryResults->{$thing->{index_oid}}{Type} = $thing->{type};
					$discoveryResults->{$thing->{index_oid}}{File} = $thing->{file};
					$discoveryResults->{$thing->{index_oid}}{Path} = $thing->{path};
					$discoveryResults->{$thing->{index_oid}}{Section} = $thing->{section};
					$discoveryResults->{$thing->{index_oid}}{Supported} = $works;
					$discoveryResults->{$thing->{index_oid}}{SNMP_Object} = $thing->{indexed};
					$discoveryResults->{$thing->{index_oid}}{SNMP_OID} = $thing->{index_oid};
					$discoveryResults->{$thing->{index_oid}}{OID_Used} = $thing->{index_oid};
					$discoveryResults->{$thing->{index_oid}}{result} = Dumper $result;
					$discoveryResults->{$thing->{index_oid}}{result}
				}
				elsif ( $thing->{type} eq "system" and not defined $doneIt{$thing->{snmpoid}} ) {
					++$count;
					print "  $count System Discovery on $node of MIB in $thing->{file}::$thing->{path}\n" if $verbose;
					my $getoid = $thing->{snmpoid};
					# does the oid in the model finish in a number?
					if ( $thing->{oid} !~ /\.\d+/ ) {
						$getoid .= ".0";
					}
					# does the actual snmpoid finish in a number?
					elsif ( $getoid !~ /\.0/ ) {
						$getoid .= ".0";
					}
					++$mib_count;
					my $result = $snmp->get($getoid);
					$doneIt{$thing->{snmpoid}} = 1;

					if ( defined $result and $result->{$getoid} !~ /(noSuchObject|noSuchInstance)/ ) {
						$works = "YES";
						print $t->elapTime(). " MIB SUPPORTED: $thing->{oid} $thing->{snmpoid}\n" if $verbose;
						print Dumper $thing if $debug;
						print Dumper $result if $debug;
					}
					else {
						$works = "NO";
						print $t->elapTime(). " MIB NOT SUPPORTED: $thing->{oid} $thing->{snmpoid}\n" if $verbose;
					}
					print "\n" if $verbose;
					$discoveryResults->{$thing->{snmpoid}}{node} = $node;
					#$discoveryResults->{$thing->{snmpoid}}{sysDescr} = $NI->{system}{sysDescr};
					$discoveryResults->{$thing->{snmpoid}}{nodeModel} = $NI->{system}{nodeModel};
					$discoveryResults->{$thing->{snmpoid}}{Type} = $thing->{type};
					$discoveryResults->{$thing->{snmpoid}}{File} = $thing->{file};
					$discoveryResults->{$thing->{snmpoid}}{Path} = $thing->{path};
					$discoveryResults->{$thing->{snmpoid}}{Section} = $thing->{section};
					$discoveryResults->{$thing->{snmpoid}}{Supported} = $works;
					$discoveryResults->{$thing->{snmpoid}}{SNMP_Object} = $thing->{oid};
					$discoveryResults->{$thing->{snmpoid}}{SNMP_OID} = $thing->{snmpoid};
					$discoveryResults->{$thing->{snmpoid}}{OID_Used} = $thing->{snmpoid};
					$discoveryResults->{$thing->{snmpoid}}{result} = $result->{$getoid};
				}
				last if $count >= 10000;
			}


		}
	}
}

sub printDiscoverySummary {

	my $newModel = readFiletoHash(file => $modelTemplate) if defined $newModelName;

	# do some basic model changes
	if ( defined $newModelName ) {
		$newModel->{'system'}{'nodeModel'} = $newModelName;
		$newModel->{'system'}{'nodeModelComment'} = "Auto Generated Model by model_discovery.pl";
	}

	my %graphTypeSupported;

	$nodeSummary{sysDescr} =~ s/\r\n/\\n/g;
	print "node:\t$nodeSummary{node}\n";
	print "sysDescr:\t$nodeSummary{sysDescr}\n";
	print "nodeModel:\t$nodeSummary{nodeModel}\n";

	print "\n";

	my @sections = ();
	my @common_things = ();
	# loop through the data
	foreach my $key ( sort { $discoveryResults->{$a}{Type} cmp $discoveryResults->{$b}{Type} } (keys %$discoveryResults) ) {
		if ( $discoveryResults->{$key}{Supported} eq "YES" ) {
			if ( $discoveryResults->{$key}{Type} eq "systemHealth" ) {
				my $section_name = $discoveryResults->{$key}{Path};
				$section_name =~ s|\w+/systemHealth/sys/(\w+)|$1|;
				if ( not grep ($_ eq $section_name, @sections) ) {
					push(@sections,$section_name);
				}
			}

			if ( $discoveryResults->{$key}{Path} =~ /Common/ ) {
				my $common_name = $discoveryResults->{$key}{File};
				$common_name =~ s|^Common-([\w\-]+)\.nmis$|$1|;
				if ( not grep ($_ eq $common_name, @common_things) ) {
					push(@common_things,$common_name);	
				}
			}

			# what graphtypes does this section have?
			my $section = $discoveryResults->{$key}{Section};
			$graphTypeSupported{$section}{graphtype} = $graphTypes{$section}{graphtype} if defined $graphTypes{$section}{graphtype};
			$graphTypeSupported{$section}{path} = $discoveryResults->{$key}{Path} if defined $graphTypes{$section}{graphtype};

			# make this a little more pretty.
			$discoveryResults->{$key}{result} =~ s/\r\n/\\n/g;
			$discoveryResults->{$key}{result} =~ s/\n/  /g;
			print "DISCOVERED: $discoveryResults->{$key}{Type} $discoveryResults->{$key}{File} $discoveryResults->{$key}{Path} $discoveryResults->{$key}{SNMP_OID} $discoveryResults->{$key}{result}\n" if $debug;
		}
	}

	print "Common Things to Include: \n\n" if $debug;
	foreach my $common_name (@common_things) {
		# save the new common sections if common_exclude is null or if it is defined and does not match.
		if (( defined $newModelName and not defined $common_exclude )
		 	or ( defined $newModelName and defined $common_exclude and $common_name !~ /$common_exclude/ )
		) {
			print "Adding common model $common_name to model\n";
			$newModel->{'-common-'}{'class'}{$common_name}{'common-model'} = $common_name;
		}
		elsif ( defined $common_exclude and $common_name =~ /$common_exclude/ ) {
			print "Excluding from common models: $common_name\n";
		}

		print <<EO_TEXT if $debug;
      '$common_name' => {
        'common-model' => '$common_name'
      },
EO_TEXT
	}
	print "\n";

	print "System Health Sections:\n";
	@sections = sort { $a cmp $b } (@sections);
	my $sections_list = join(",",@sections);
	print "'sections' => '$sections_list',\n";

    $newModel->{'systemHealth'}{'sections'} = $sections_list if defined $newModelName;

	if ( defined $newModelName ) {
		my $model_file_name = "$C->{'<nmis_models>'}/Model-$newModelName.nmis";
		writeHashtoFile( file => $model_file_name, data=>$newModel);
		print "New Auto Model $newModelName saved to $model_file_name\n";
	}

	# fixme, not currently right, needs more time.
	#print "List of Graph Types found and their path:\n";
	#foreach my $section ( sort { $a cmp $b } (keys %graphTypeSupported) ) {
	#	print "$section ($graphTypeSupported{$section}{path}) has graph type: $graphTypeSupported{$section}{graphtype}\n";
	#}
	#print Dumper \%graphTypes;

}

sub printDiscoveryResults {
	my $file = shift;

	open(OUT,">$file") or die "ERROR with file $file: $!\n";

	# make a header and print it out
	my @header = qw(
		node
		nodeModel
		Type
		File
		Path
		Supported
		SNMP_Object
		SNMP_OID
		OID_Used
		result
	);

	$nodeSummary{sysDescr} =~ s/\r\n/\\n/g;
	print OUT "node:\t$nodeSummary{node}\n";
	print OUT "sysDescr:\t$nodeSummary{sysDescr}\n";
	print OUT "nodeModel:\t$nodeSummary{nodeModel}\n";

	print OUT "\n";
	my $printit = join("\t",@header);
	print OUT "$printit\n";

	# loop through the data
	foreach my $key ( keys %$discoveryResults ) {
		my @data;
		$discoveryResults->{$key}{result} =~ s/\r\n/\\n/g;
		$discoveryResults->{$key}{result} =~ s/\n/  /g;
		# now use the previously defined header to print out the data.
		foreach my $head (@header) {
			push(@data,$discoveryResults->{$key}{$head});
		}
		my $printit = join("\t",@data);
		print OUT "$printit\n";
	}
	close(OUT);
}
#print Dumper($models);

#@oidList = sort @oidList;
#my $out = join(",",@oidList);
#print "OIDS:$out\n";
#
#my %summary;
#foreach my $model (keys %$models) {
#	foreach my $section (@{$models->{$model}{sections}}) {
#		$summary{$model}{$section} = "YES";
#		if ( not grep {$section eq $_} @topSections ) {
#			print "ADDING $section to TopSections\n";
#			push(@topSections,$section);
#		}
#	}
#}
#
#@topSections = sort @topSections;
#my $out = join(",",@topSections);
#print "Model,$out\n";
#
#foreach my $model (sort keys %summary) {
#	my @line;
#	push(@line,$model);
#	foreach my $section (@topSections) {
#		if ( $summary{$model}{$section} eq "YES" ) {
#			push(@line,$summary{$model}{$section});
#		}
#		else {
#			push(@line,"NO");
#		}
#	}
#	my $out = join(",",@line);
#	print "$out\n";
#}


sub indent {
	for (1..$indent) {
		print " ";
	}
}

sub processDir {
	my %args = @_;
	# Starting point
	my $dir = $args{dir};
	my @dirlist;
	my $index;
	++$dirlevel;
	my @filename;
	my $key;

	if ( -d $dir ) {
		print "\nProcessing Directory $dir pass=$dirpass level=$dirlevel\n" if $debug;
	}
	else {
		print "\n$dir is not a directory\n" if $debug;
		exit -1;
	}

	#sleep 1;
	if ( $dirpass >= 1 and $dirpass < $maxrecurse and $dirlevel <= $maxlevel ) {
		++$dirpass;
		opendir (DIR, "$dir");
		@dirlist = readdir DIR;
		closedir DIR;

		if ($debug > 1) { print "\tFound $#dirlist entries\n"; }

		foreach my $file (sort {$a cmp $b} (@dirlist)) {
		#for ( $index = 0; $index <= $#dirlist; ++$index ) {
			@filename = split(/\./,"$dir/$file");
			if ( -f "$dir/$file"
				and $extension =~ /$filename[$#filename]/i
				and $bad_file !~ /$file/i
			) {
				if ($debug>1) { print "\t\t$index file $dir/$file\n"; }
				&processModelFile(dir => $dir, file => $file)
			}
			elsif ( -d "$dir/$file"
				and $file !~ /^\.|CVS/
				and $bad_dir !~ /$file/i
			) {
				#if (!$debug) { print "."; }
				&processDir(dir => "$dir/$file");
				--$dirlevel;
			}
		}
	}
} # processDir

sub processModelFile {
	my %args = @_;
	my $dir = $args{dir};
	my $file = $args{file};
	$indent = 2;
	++$file_count;
	
	if ( $file !~ /^Graph|^Model.nmis$/ ) {
		$curModel = $file;
		$curModel =~ s/Model\-|\.nmis//g;

		my $comment = "Model";
		$comment = "Common" if ( $file =~ /Common/ );
	
		print &indent . "Processing $curModel: $file\n" if $verbose;
		my $model = readFiletoHash(file=>"$dir/$file");		
		#Recurse into structure, handing off anything which is a HASH to be handled?
		push(@path,$comment);
		$modLevel = 0;
		processData($model,$comment,$file);
		pop(@path);
	}	
}

sub processData {
	my $data = shift;
	my $comment = shift;
	my $file = shift;
	$indent += 2;
	++$modLevel;
	
	if ( ref($data) eq "HASH" ) {
		my $indexed = undef;
		my $index_oid = undef;
		my $graphtype = undef;
		foreach my $section (sort keys %{$data}) {
			my $curpath = join("/",@path);
			if ( ref($data->{$section}) =~ /HASH|ARRAY/ ) {
				print &indent . "$curpath -> $section\n" if $debug;
				#recurse baby!
				if ( $curpath =~ /rrd\/\w+\/snmp$/ ) {
					#print indent."Found RRD Variable $section \@ $curpath\n" if $debug;
					#checkRrdLength($section);
				}
									
				push(@path,$section);
				if ( $modLevel <= 1 and $section !~ /-common-|class/ ) {
					push(@{$models->{$curModel}{sections}},$section);
					if ( not grep {$section eq $_} @path ) {
						push(@topSections,$section);
					}
				}
				elsif ( grep {"-common-" eq $_} @path and $section !~ /-common-|class/ ) {
					push(@{$models->{$curModel}{sections}},"Common-$section");
					if ( not grep {$section eq $_} @path ) {
						push(@topSections,$section);
					}				
				}

				processData($data->{$section},"$section",$file);
				
				pop(@path);
			}
			else {
				# what are the index variables.
				# looking at these variabled globally in the model
				if ( $section eq "indexed" and $curpath =~ /\/sys\// and $data->{$section} ne "true" ) {
					#print "    $curpath/$section: $data->{$section}\n";
					$indexed = $data->{$section};
				}	
				elsif ( $section eq "index_oid" and $curpath =~ /\/sys\// and $data->{$section} =~ /\.\d+\.\d+\.\d+\.\d+/ ) {
					#print "    $curpath/$section: $data->{$section}\n";
					$index_oid = $data->{$section};
				}
				elsif ( $section eq "graphtype" and $curpath =~ /\/rrd\// ) {
					#print "    $curpath/$section: $data->{$section}\n";
					if ( $curpath =~ /^(Common|Model)\/(\w+)\/rrd\/(\w+)/ ) {
						my $type = $2; 
						my $stat_section = $3; 
						$graphTypes{$stat_section}{type} = $type;
						$graphTypes{$stat_section}{section} = $stat_section;
						$graphTypes{$stat_section}{graphtype} = $data->{graphtype};
					}
				}

				# only diving deeper into the variables for the system.
				if ( $curpath =~ /^(Common|Model)\/system\/(sys|rrd)\/(\w+)\/snmp\/(\w+)/ and $section eq "oid" ) {
					my $snmpoid = $mibs->{$data->{oid}};
					if ( not defined $snmpoid and $data->{oid} =~ /1\.3\.6\.1/ ) {
						$snmpoid = $data->{oid};
					}
					# this is a bad one like ciscoMemoryPoolUsed.2?
					elsif ( $data->{oid} =~ /[a-zA-Z]+\.[\d\.]+/ ) {
						print "FIXING bad Model OID $file :: $curpath $data->{oid}\n" if $debug;
						my ($mib,$index) = split(/\./,$data->{oid});
						
						if ( defined $mibs->{$mib} ) {
							$snmpoid = $mibs->{$mib};
							$snmpoid .= ".$index";							
						}
					}

					if ( not defined $snmpoid ) {
						print "ERROR with Model OID $file :: $curpath $data->{oid}\n";
					}

					push(@discoverList,{
						type => "system",
						stat_type => $2,
						section => $3,
						metric => $4,
						file => $file,
						path => $curpath,
						oid => $data->{$section},
						snmpoid => $snmpoid
					});					
					#print "Processing $file: $curpath/$section\n";
				}


				#elsif ( $section eq "oid" ) {
				#	print "    $curpath/$section: $data->{$section}\n";
				#	
				#	if ( not grep {$data->{$section} eq $_} @oidList ) {
				#		print "ADDING $data->{$section} to oidList\n" if $debug;
				#		push(@oidList,$data->{$section});
				#	}
				#}
				print &indent . "$curpath -> $section = $data->{$section}\n" if $debug;
			}
		}
		if ( defined $indexed ) {
			my $curpath = join("/",@path);
			my $section = $path[-1];
			print "$curpath :: section=$section indexed=$indexed index_oid=$index_oid\n" if $debug;
			# convert indexed into an oid if index_oid is blank
			if ( not defined $index_oid ) {
				$index_oid = $mibs->{$indexed};
			}
			push(@discoverList,{
				type => "systemHealth",
				file => $file,
				path => $curpath,
				section => $section,
				indexed => $indexed,
				index_oid => $index_oid
			});
		}
	}
	elsif ( ref($data) eq "ARRAY" ) {
		foreach my $element (@{$data}) {
			my $curpath = join("/",@path);
			print indent."$curpath: $element\n" if $debug;
			#Is this an RRD DEF?
			if ( $element =~ /DEF:/ ) {
				my @DEF = split(":",$element);
				#DEF:avgBusy1=$database:avgBusy1:AVERAGE
				checkRrdLength($DEF[2]);
			}
		}
	}
	$indent -= 2;
	--$modLevel;
}

sub checkRrdLength {
	my $string = shift;
	my $len = length($string);
	print indent."FOUND: $string is length $len\n" if $debug;
	if ($len > $rrdlen ) {
		print "    ERROR: RRD variable $string found longer than $rrdlen\n";
			
	}
}

sub loadMibs {
	my $C = shift;

	my $oids = "$C->{mib_root}/nmis_mibs.oid";
	my $mibs;

	info("Loading Vendor OIDs from $oids");

	open(OIDS,$oids) or warn "ERROR could not load $oids: $!\n";

	my $match = qr/\"([\w\-\.]+)\"\s+\"([\d+\.]+)\"/;

	while (<OIDS>) {
		if ( $_ =~ /$match/ ) {
			$mibs->{$1} = $2;
		}
		elsif ( $_ =~ /^#|^\s+#/ ) {
			#all good comment
		}
		else {
			info("ERROR: no match $_");
		}
	}
	close(OIDS);

	return ($mibs);
}

sub usage {
	print <<EO_TEXT;
$0 will check existing NMIS models and determine which models apply to a node in NMIS.
usage: $0 node=<nodename> [model=name for new model] [file=/path/to/file_for_details.txt] [debug=true|false]
eg: $0 node=nodename [debug=true|false] [verbose=true|false]

node: NMIS nodename
model: Name of new model and the result file to be generated.
common_exclude: A regular expression for the Common models to exclude in the auto geneated model.
file: Where to save the results to, TAB delimited CSV.

EO_TEXT
}
