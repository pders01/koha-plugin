#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use File::Temp qw( tempdir );
use File::Spec ();

use FindBin qw( $RealBin );
use lib "$RealBin/../lib";
BEGIN { my $l = "$RealBin/../local/lib/perl5"; unshift @INC, $l if -d $l }

use Local::Config qw( load_config save_config find_config migrate_from_dotenv config_to_env );

my $tmpdir = tempdir( CLEANUP => 1 );

# --- YAML round-trip ---

subtest 'YAML save and load' => sub {
    my $path = File::Spec->catfile( $tmpdir, 'test.yml' );
    my $data = {
        name    => 'Koha::Plugin::Com::Example::Test',
        version => '1.0.0',
        author  => 'Tester',
    };

    ok( save_config( $data, $path ), 'save_config YAML succeeds' );
    ok( -e $path,                    'file created' );

    my $loaded = load_config($path);
    is( ref $loaded,        'HASH',           'load_config returns hashref' );
    is( $loaded->{name},    $data->{name},    'name round-trips' );
    is( $loaded->{version}, $data->{version}, 'version round-trips' );
    is( $loaded->{author},  $data->{author},  'author round-trips' );
};

# --- JSON round-trip ---

subtest 'JSON save and load' => sub {
    my $path = File::Spec->catfile( $tmpdir, 'test.json' );
    my $data = {
        name        => 'Koha::Plugin::Com::Example::Json',
        version     => '2.0.0',
        description => 'JSON test',
    };

    ok( save_config( $data, $path ), 'save_config JSON succeeds' );
    ok( -e $path,                    'file created' );

    my $loaded = load_config($path);
    is( ref $loaded,            'HASH',               'load_config returns hashref' );
    is( $loaded->{name},        $data->{name},        'name round-trips' );
    is( $loaded->{version},     $data->{version},     'version round-trips' );
    is( $loaded->{description}, $data->{description}, 'description round-trips' );
};

# --- config_to_env ---

subtest 'config_to_env populates %ENV' => sub {
    local %ENV = %ENV;
    my $config = {
        name    => 'Koha::Plugin::Com::Example::Env',
        version => '3.0.0',
        author  => 'EnvTester',
    };

    ok( config_to_env($config), 'config_to_env returns true' );
    is( $ENV{PLUGIN_NAME},    'Koha::Plugin::Com::Example::Env', 'PLUGIN_NAME set' );
    is( $ENV{PLUGIN_VERSION}, '3.0.0',                           'PLUGIN_VERSION set' );
    is( $ENV{PLUGIN_AUTHOR},  'EnvTester',                       'PLUGIN_AUTHOR set' );
};

subtest 'config_to_env handles missing fields' => sub {
    local %ENV = %ENV;
    my $config = { name => 'Test' };

    config_to_env($config);
    is( $ENV{PLUGIN_NAME},    'Test', 'present field set' );
    is( $ENV{PLUGIN_VERSION}, '',     'missing field set to empty string' );
};

# --- find_config ---

subtest 'find_config detects config files' => sub {

    # Should not find anything in our temp dir
    my $orig = Cwd::getcwd();
    chdir $tmpdir or die "Cannot chdir: $!";

    is( find_config(), undef, 'no config file in empty dir' );

    # Create a koha-plugin.yml
    open my $fh, '>', 'koha-plugin.yml' or die;
    print {$fh} "---\nname: test\n";
    close $fh;

    is( find_config(), 'koha-plugin.yml', 'finds koha-plugin.yml' );
    unlink 'koha-plugin.yml';

    # Create a koha-plugin.json
    open $fh, '>', 'koha-plugin.json' or die;
    print {$fh} '{"name":"test"}';
    close $fh;

    is( find_config(), 'koha-plugin.json', 'finds koha-plugin.json' );
    unlink 'koha-plugin.json';

    chdir $orig or die;
};

# --- migrate_from_dotenv ---

subtest 'migrate_from_dotenv' => sub {
    my $orig = Cwd::getcwd();
    chdir $tmpdir or die "Cannot chdir: $!";

    # Create a .env
    open my $fh, '>', '.env' or die;
    print {$fh} <<'DOTENV';
# comment
PLUGIN_NAME=Koha::Plugin::Com::Migrate::Test
PLUGIN_VERSION=1.5.0
PLUGIN_AUTHOR=Migrator
PLUGIN_DESCRIPTION="A migrated plugin"
DOTENV
    close $fh;

    my $output = q{};
    local *STDOUT;
    local *STDERR;
    open STDOUT, '>', \$output or die;
    open STDERR, '>', \$output or die;

    my $result = migrate_from_dotenv('yml');
    is( $result, 'koha-plugin.yml', 'returns target filename' );
    ok( -e 'koha-plugin.yml', 'YAML config created' );

    my $config = load_config('koha-plugin.yml');
    is( $config->{name},        'Koha::Plugin::Com::Migrate::Test', 'name migrated' );
    is( $config->{version},     '1.5.0',                            'version migrated' );
    is( $config->{author},      'Migrator',                         'author migrated' );
    is( $config->{description}, 'A migrated plugin',                'description migrated (quotes stripped)' );

    # Should refuse to overwrite
    my $result2 = migrate_from_dotenv('yml');
    ok( !$result2, 'refuses to overwrite existing config' );

    unlink '.env', 'koha-plugin.yml';
    chdir $orig or die;
};

done_testing();
