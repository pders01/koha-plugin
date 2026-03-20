#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

use FindBin qw( $RealBin );
use lib "$RealBin/../lib";
BEGIN { my $l = "$RealBin/../local/lib/perl5"; unshift @INC, $l if -d $l }

use Local::Metadata qw( metadata_from_env validate_metadata stringify_metadata );

# --- metadata_from_env ---

subtest 'metadata_from_env reads PLUGIN_ vars' => sub {
    local %ENV = %ENV;
    $ENV{PLUGIN_NAME}    = 'Koha::Plugin::Com::Example::Test';
    $ENV{PLUGIN_VERSION} = '1.2.3';
    $ENV{PLUGIN_AUTHOR}  = 'Tester';
    delete $ENV{PLUGIN_DESCRIPTION};

    my $m = metadata_from_env();
    is( ref $m,        'HASH',                             'returns hashref' );
    is( $m->{name},    'Koha::Plugin::Com::Example::Test', 'name from env' );
    is( $m->{version}, '1.2.3',                            'version from env' );
    is( $m->{author},  'Tester',                           'author from env' );
    ok( !defined $m->{description}, 'missing env var yields undef' );
};

subtest 'metadata_from_env with empty env' => sub {
    local %ENV = ();
    my $m = metadata_from_env();
    is( ref $m, 'HASH', 'returns hashref even with no env' );
    ok( !defined $m->{name}, 'all fields undef' );
};

# --- validate_metadata ---

subtest 'validate_metadata succeeds with valid data' => sub {
    my $m = {
        name             => 'Koha::Plugin::Com::Example::Test',
        author           => 'Tester',
        version          => '1.0.0',
        description      => 'A test plugin',
        date_authored    => '2025-01-01',
        date_updated     => '2025-06-01',
        minimum_version  => '22.11',
        maximum_version  => '25.05',
        release_filename => 'example-test',
        static_dir_name  => 'static',
    };

    # Suppress log output
    my $output = q{};
    local *STDOUT;
    local *STDERR;
    open STDOUT, '>', \$output or die;
    open STDERR, '>', \$output or die;

    ok( validate_metadata($m), 'valid metadata passes' );
};

subtest 'validate_metadata fails without name' => sub {
    my $m = { name => undef };

    my $output = q{};
    local *STDOUT;
    local *STDERR;
    open STDOUT, '>', \$output or die;
    open STDERR, '>', \$output or die;

    ok( !validate_metadata($m), 'missing name fails' );
};

subtest 'validate_metadata fails with wrong name format' => sub {
    my $m = { name => 'Koha::Plugin::Bad' };

    my $output = q{};
    local *STDOUT;
    local *STDERR;
    open STDOUT, '>', \$output or die;
    open STDERR, '>', \$output or die;

    ok( !validate_metadata($m), 'wrong name format fails' );
};

subtest 'validate_metadata rewrites "today" dates' => sub {
    my $m = {
        name          => 'Koha::Plugin::Com::Example::Test',
        date_authored => 'today',
        date_updated  => 'today',
    };

    my $output = q{};
    local *STDOUT;
    local *STDERR;
    open STDOUT, '>', \$output or die;
    open STDERR, '>', \$output or die;

    validate_metadata($m);
    like( $m->{date_authored}, qr/^\d{4}-\d{2}-\d{2}$/, 'date_authored rewritten to ISO' );
    like( $m->{date_updated},  qr/^\d{4}-\d{2}-\d{2}$/, 'date_updated rewritten to ISO' );
};

# --- stringify_metadata ---

subtest 'stringify_metadata produces Data::Dumper output without braces' => sub {
    my $m = { name => 'Test', version => '1.0.0' };
    my $s = stringify_metadata($m);

    unlike( $s, qr/^[{]/, 'no leading brace' );
    unlike( $s, qr/[}]$/, 'no trailing brace' );
    like( $s, qr/'name'/,    'contains name key' );
    like( $s, qr/'version'/, 'contains version key' );
};

done_testing();
