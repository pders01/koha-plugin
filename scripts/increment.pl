#!/usr/bin/env perl

use strict;
use warnings;
use lib './lib';
BEGIN { my $l = './local/lib/perl5'; unshift @INC, $l if -d $l }

use Carp         qw( croak );
use Getopt::Long qw( GetOptions );

use Local::Command::Increment qw( run_increment );

my %opts = (
    version => undef,
    type    => 'patch',
    times   => 1,
    name    => undef,
);

GetOptions(
    'version=s' => \$opts{version},
    'type=s'    => \$opts{type},
    'times=i'   => \$opts{times},
    'name=s'    => \$opts{name},
) or croak "Error in command line arguments\n";

run_increment(%opts);
