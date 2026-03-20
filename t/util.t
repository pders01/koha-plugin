#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

use FindBin qw( $RealBin );
use lib "$RealBin/../lib";
BEGIN { my $l = "$RealBin/../local/lib/perl5"; unshift @INC, $l if -d $l }

use Local::Util qw( l asset_dir );

# --- asset_dir ---

subtest 'asset_dir without PAR_TEMP' => sub {
    local $ENV{PAR_TEMP} = undef;

    is( asset_dir(),            '.',          'base is CWD' );
    is( asset_dir('templates'), 'templates',  'subdir appended' );
    is( asset_dir('scripts'),   'scripts',    'scripts subdir' );
};

subtest 'asset_dir with PAR_TEMP' => sub {
    local $ENV{PAR_TEMP} = '/tmp/par-test';

    like( asset_dir(),            qr{/tmp/par-test.+inc$},           'base is PAR inc dir' );
    like( asset_dir('templates'), qr{/tmp/par-test.+inc.+templates}, 'templates under PAR' );
};

# --- l (logging) ---

subtest 'l returns true' => sub {
    # Capture STDOUT to avoid noise
    my $output = q{};
    {
        local *STDOUT;
        open STDOUT, '>', \$output or die "Cannot redirect STDOUT: $!";
        ok( l( 'info',    'test info' ),    'info returns true' );
        ok( l( 'warning', 'test warning' ), 'warning returns true' );
        ok( l( 'error',   'test error' ),   'error returns true' );
    }
    like( $output, qr/test info/,    'info message printed' );
    like( $output, qr/test warning/, 'warning message printed' );
    like( $output, qr/test error/,   'error message printed' );
};

done_testing();
