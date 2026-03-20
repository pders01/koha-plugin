#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

use FindBin qw( $RealBin );
use lib "$RealBin/../lib";
BEGIN { my $l = "$RealBin/../local/lib/perl5"; unshift @INC, $l if -d $l }

use Local::Util qw( l asset_dir resolve );

# --- asset_dir ---

subtest 'asset_dir without PAR_TEMP' => sub {
    local $ENV{PAR_TEMP} = undef;

    is( asset_dir(),            '.',         'base is CWD' );
    is( asset_dir('templates'), 'templates', 'subdir appended' );
    is( asset_dir('scripts'),   'scripts',   'scripts subdir' );
};

subtest 'asset_dir with PAR_TEMP' => sub {
    local $ENV{PAR_TEMP} = '/tmp/par-test';

    like( asset_dir(),            qr{/tmp/par-test.+inc$},           'base is PAR inc dir' );
    like( asset_dir('templates'), qr{/tmp/par-test.+inc.+templates}, 'templates under PAR' );
};

# --- l (logging) ---

subtest 'l returns true and routes to correct streams' => sub {
    my $stdout = q{};
    my $stderr = q{};
    {
        local *STDOUT;
        local *STDERR;
        open STDOUT, '>', \$stdout or die "Cannot redirect STDOUT: $!";
        open STDERR, '>', \$stderr or die "Cannot redirect STDERR: $!";
        ok( l( 'info',    'test info' ),    'info returns true' );
        ok( l( 'warning', 'test warning' ), 'warning returns true' );
        ok( l( 'error',   'test error' ),   'error returns true' );
    }
    like( $stdout, qr/test info/,    'info goes to STDOUT' );
    like( $stderr, qr/test warning/, 'warning goes to STDERR' );
    like( $stderr, qr/test error/,   'error goes to STDERR' );
    unlike( $stdout, qr/test warning/, 'warning not on STDOUT' );
    unlike( $stdout, qr/test error/,   'error not on STDOUT' );
};

# --- resolve ---

subtest 'resolve returns value when defined' => sub {
    is( resolve( 'hello', 'fallback' ),   'hello', 'scalar value used' );
    is( resolve( 'hello', sub {'nope'} ), 'hello', 'sub not called when value defined' );
    is( resolve( 0,       'fallback' ),   0,       'falsy but defined value used' );
    is( resolve( '',      'fallback' ),   '',      'empty string is defined' );
};

subtest 'resolve falls back when undef' => sub {
    is( resolve( undef, 'default' ),    'default', 'scalar fallback used' );
    is( resolve( undef, sub {'lazy'} ), 'lazy',    'sub fallback called' );

    my $called = 0;
    resolve( 'present', sub { $called = 1; 'nope' } );
    is( $called, 0, 'sub not called when value present' );

    resolve( undef, sub { $called = 1; 'yes' } );
    is( $called, 1, 'sub called when value undef' );
};

done_testing();
