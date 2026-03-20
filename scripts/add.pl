#!/usr/bin/env perl

use strict;
use warnings;
use lib './lib';
BEGIN { my $l = './local/lib/perl5'; unshift @INC, $l if -d $l }

use Local::Command::Add qw( run_add );

run_add( $ARGV[0] );
