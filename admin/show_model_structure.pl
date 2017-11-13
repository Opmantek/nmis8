#!/usr/bin/perl
# small helper for analysing/exporting model structures: 
# shows flattened structure and values. 
# works off expanded model_cache json files,
# or off UNEXPANDED models/models-install files (i.e. common sections are 
# not filled in!)
use strict;

use FindBin;
use lib "$FindBin::RealBin/../lib";
use Data::Dumper;
use func;

my $mf = $ARGV[0];
die "usage: $0 <somefile.json or .nmis>\n"
		if (!$mf or !-f $mf);

my $deepdata = readFiletoHash(file => $mf, json => ($mf =~ /\.json$/i));

my %flatearth = flatten($deepdata);
for my $k (sort keys %flatearth)
{
	print "$k  =  $flatearth{$k}\n";
}
exit 0;

# translates EXISTING deep structure into key1/key2/key3 constructs,
# also supports key1/N/key2/M but toplevel thing must be hash.
# args: deep hash ref
# returns: flat hash
sub flatten
{
	my ($deep, $prefix) = @_;
	my %flattened;

	if ($prefix)
	{
		$prefix .= "/";
	}
	else
	{
		$prefix='/';
	}

	if (ref($deep) eq "HASH")
	{
		for my $k (keys %$deep)
		{
			my $visk = $k;
			$visk =~ s!/!\\/!g;				# escape any '/' that key might contain
			if (ref($deep->{$k}))
			{
				%flattened = (%flattened, flatten($deep->{$k}, "$prefix$visk"));
			}
			else
			{
				$flattened{"$prefix$visk"} = $deep->{$k};
			}
		}
	}
	elsif (ref($deep) eq "ARRAY")
	{
		for my $idx (0..$#$deep)
		{
			if (ref($deep->[$idx]))
			{
				%flattened = (%flattened, flatten($deep->[$idx], "$prefix$idx"));
			}
			else
			{
				$flattened{"$prefix$idx"} = $deep->[$idx];
			}
		}
	}
	else
	{
		die "invalid inputs to flatten: ".Dumper($deep)."\n";
	}
	return %flattened;
}
