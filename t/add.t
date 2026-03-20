#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use File::Temp qw( tempdir );
use File::Spec ();
use Cwd        ();

use FindBin qw( $RealBin );
use lib "$RealBin/../lib";
BEGIN { my $l = "$RealBin/../local/lib/perl5"; unshift @INC, $l if -d $l }

use Local::Command::Add qw( run_add );
use Local::Config       qw( save_config config_to_env );

my $PROJECT_ROOT = "$RealBin/..";

sub _quiet (&) {
    my ($code) = @_;
    my $output = q{};
    local *STDOUT;
    local *STDERR;
    open STDOUT, '>', \$output or die;
    open STDERR, '>', \$output or die;
    return $code->();
}

# --- Setup: create a plugin dir with config ---

my $tmpdir = tempdir( CLEANUP => 1 );

sub _setup_plugin {
    my $orig = Cwd::getcwd();
    chdir $tmpdir or die;

    my $config = {
        name             => 'Koha::Plugin::Com::Test::Add',
        author           => 'Tester',
        version          => '1.0.0',
        description      => 'Test plugin for add commands',
        minimum_version  => '',
        maximum_version  => '',
        release_filename => 'test-add',
        static_dir_name  => 'static',
        date_authored    => '2026-03-20',
        date_updated     => '2026-03-20',
    };

    save_config( $config, 'koha-plugin.yml' );
    config_to_env($config);

    my $plugin_dir = 'Koha/Plugin/Com/Test/Add';
    require File::Path;
    File::Path::make_path($plugin_dir);

    return $orig;
}

# --- add action (non-interactive) ---

subtest 'add action non-interactive' => sub {
    my $orig = _setup_plugin();

    # Set KOHA_PLUGIN_ROOT so templates are found
    local $ENV{KOHA_PLUGIN_ROOT} = $PROJECT_ROOT;

    my $result = _quiet { run_add( 'action', type => 'tool' ) };
    ok( $result,                               'add action returns true' );
    ok( -e 'Koha/Plugin/Com/Test/Add/tool.tt', 'tool.tt created' );

    # Verify content
    require Path::Tiny;
    my $content = Path::Tiny::path('Koha/Plugin/Com/Test/Add/tool.tt')->slurp_utf8;
    like( $content, qr/Add/,  'template contains project name' );
    like( $content, qr/Tool/, 'template contains capitalized action' );

    chdir $orig or die;
};

subtest 'add configure non-interactive' => sub {
    my $orig = _setup_plugin();
    local $ENV{KOHA_PLUGIN_ROOT} = $PROJECT_ROOT;

    my $result = _quiet { run_add( 'action', type => 'configure' ) };
    ok( $result,                                    'add configure returns true' );
    ok( -e 'Koha/Plugin/Com/Test/Add/configure.tt', 'configure.tt created' );

    require Path::Tiny;
    my $content = Path::Tiny::path('Koha/Plugin/Com/Test/Add/configure.tt')->slurp_utf8;
    like( $content, qr/form/i,          'configure template has form' );
    like( $content, qr/name="save"/,    'configure template has save hidden field' );
    like( $content, qr/type="submit"/i, 'configure template has submit button' );

    chdir $orig or die;
};

# --- add api-route (non-interactive) ---

subtest 'add api-route non-interactive' => sub {
    my $orig = _setup_plugin();

    # Create empty openapi.json
    require Path::Tiny;
    Path::Tiny::path('Koha/Plugin/Com/Test/Add/openapi.json')->spew_utf8("{}\n");

    my $result = _quiet {
        run_add(
            'api-route',
            path       => '/widgets',
            method     => 'get',
            operation  => 'listWidgets',
            controller => 'WidgetController#list',
            permission => 'catalogue',
        )
    };
    ok( $result, 'add api-route returns true' );

    # Verify openapi.json
    my $spec = JSON::decode_json( Path::Tiny::path('Koha/Plugin/Com/Test/Add/openapi.json')->slurp_utf8 );
    ok( exists $spec->{'/widgets'},      'route added to spec' );
    ok( exists $spec->{'/widgets'}{get}, 'GET method added' );
    is( $spec->{'/widgets'}{get}{operationId}, 'listWidgets', 'operationId correct' );
    like( $spec->{'/widgets'}{get}{'x-mojo-to'}, qr/WidgetController#list/, 'x-mojo-to correct' );

    # Verify controller was created
    ok( -e 'Koha/Plugin/Com/Test/Add/WidgetController.pm', 'controller file created' );
    my $ctrl = Path::Tiny::path('Koha/Plugin/Com/Test/Add/WidgetController.pm')->slurp_utf8;
    like( $ctrl, qr/package Koha::Plugin::Com::Test::Add::WidgetController/, 'controller package correct' );
    like( $ctrl, qr/sub list/,                                               'list method stub present' );
    like( $ctrl, qr/openapi->valid_input/,                                   'uses openapi validation' );
    like( $ctrl, qr/Mojo::Base 'Mojolicious::Controller'/,                   'inherits from Mojolicious::Controller' );

    chdir $orig or die;
};

subtest 'add api-route with path params non-interactive' => sub {
    my $orig = _setup_plugin();

    require Path::Tiny;
    Path::Tiny::path('Koha/Plugin/Com/Test/Add/openapi.json')->spew_utf8("{}\n");

    my $result = _quiet {
        run_add(
            'api-route',
            path       => '/widgets/{widget_id}',
            method     => 'get',
            operation  => 'getWidget',
            controller => 'WidgetController#get',
        )
    };
    ok( $result, 'add api-route with path param returns true' );

    my $spec   = JSON::decode_json( Path::Tiny::path('Koha/Plugin/Com/Test/Add/openapi.json')->slurp_utf8 );
    my $params = $spec->{'/widgets/{widget_id}'}{get}{parameters};
    is( ref $params,        'ARRAY',     'parameters is array' );
    is( $params->[0]{name}, 'widget_id', 'path param name extracted' );
    is( $params->[0]{in},   'path',      'param is path type' );

    chdir $orig or die;
};

subtest 'add second route appends method to existing controller' => sub {
    my $orig = _setup_plugin();

    require Path::Tiny;
    Path::Tiny::path('Koha/Plugin/Com/Test/Add/openapi.json')->spew_utf8("{}\n");

    # First route
    _quiet {
        run_add(
            'api-route',
            path       => '/things',
            method     => 'get',
            operation  => 'listThings',
            controller => 'ThingController#list',
        )
    };

    # Second route, same controller
    my $result = _quiet {
        run_add(
            'api-route',
            path       => '/things/{thing_id}',
            method     => 'get',
            operation  => 'getThing',
            controller => 'ThingController#get',
        )
    };
    ok( $result, 'second api-route returns true' );

    my $ctrl = Path::Tiny::path('Koha/Plugin/Com/Test/Add/ThingController.pm')->slurp_utf8;
    like( $ctrl, qr/sub list/, 'first method present' );
    like( $ctrl, qr/sub get/,  'second method appended' );

    # Verify spec has both routes
    my $spec = JSON::decode_json( Path::Tiny::path('Koha/Plugin/Com/Test/Add/openapi.json')->slurp_utf8 );
    ok( exists $spec->{'/things'},            'list route in spec' );
    ok( exists $spec->{'/things/{thing_id}'}, 'get route in spec' );

    chdir $orig or die;
};

# --- add migration (non-interactive) ---

subtest 'add migration non-interactive' => sub {
    my $orig = _setup_plugin();

    my $result = _quiet {
        run_add( 'migration', description => 'create_widgets_table' )
    };
    ok( $result, 'add migration returns true' );

    my @files = glob 'Koha/Plugin/Com/Test/Add/migrations/*.sql';
    is( scalar @files, 1, 'one migration file created' );
    like( $files[0], qr/001_create_widgets_table\.sql/, 'filename correct' );

    require Path::Tiny;
    my $content = Path::Tiny::path( $files[0] )->slurp_utf8;
    like( $content, qr/Migration 1/, 'migration header present' );
    like( $content, qr/\{\{/,        'table name placeholder present' );

    # Add a second migration
    my $result2 = _quiet {
        run_add( 'migration', description => 'add_widget_status' )
    };
    ok( $result2, 'second migration returns true' );

    my @files2 = sort glob 'Koha/Plugin/Com/Test/Add/migrations/*.sql';
    is( scalar @files2, 2, 'two migration files exist' );
    like( $files2[1], qr/002_add_widget_status\.sql/, 'second file numbered correctly' );

    chdir $orig or die;
};

# --- add hook (non-interactive) ---

subtest 'add hook non-interactive' => sub {
    my $orig = _setup_plugin();
    local $ENV{KOHA_PLUGIN_ROOT} = $PROJECT_ROOT;

    # Create a minimal base module to add hooks to
    require Path::Tiny;
    Path::Tiny::path('Koha/Plugin/Com/Test/Add.pm')->spew_utf8(<<'MODULE');
package Koha::Plugin::Com::Test::Add v1.0.0;
use base qw(Koha::Plugins::Base);
1;
MODULE

    my $result = _quiet { run_add( 'hook', type => 'cronjob_nightly' ) };
    ok( $result, 'add hook returns true' );

    my $content = Path::Tiny::path('Koha/Plugin/Com/Test/Add.pm')->slurp_utf8;
    like( $content, qr/sub cronjob_nightly/,    'hook method added' );
    like( $content, qr/=head3 cronjob_nightly/, 'hook POD added' );
    like( $content, qr/1;\s*\z/smx,             'file still ends with 1;' );

    # Adding same hook again should not duplicate
    my $result2 = _quiet { run_add( 'hook', type => 'cronjob_nightly' ) };
    ok( $result2, 'duplicate hook returns true (no-op)' );
    my @matches = ( $content =~ /sub cronjob_nightly/g );
    is( scalar @matches, 1, 'hook not duplicated' );

    chdir $orig or die;
};

subtest 'add hook generates UI template for configure' => sub {
    my $orig = _setup_plugin();
    local $ENV{KOHA_PLUGIN_ROOT} = $PROJECT_ROOT;

    require Path::Tiny;
    Path::Tiny::path('Koha/Plugin/Com/Test/Add.pm')->spew_utf8(<<'MODULE');
package Koha::Plugin::Com::Test::Add v1.0.0;
use base qw(Koha::Plugins::Base);
1;
MODULE

    my $result = _quiet { run_add( 'hook', type => 'configure' ) };
    ok( $result,                                    'add hook configure returns true' );
    ok( -e 'Koha/Plugin/Com/Test/Add/configure.tt', 'configure.tt created' );

    my $content = Path::Tiny::path('Koha/Plugin/Com/Test/Add.pm')->slurp_utf8;
    like( $content, qr/sub configure/, 'configure method added' );
    like( $content, qr/store_data/,    'configure has store_data pattern' );

    chdir $orig or die;
};

# --- error cases ---

subtest 'add unknown component' => sub {
    my $result = _quiet { run_add('nonexistent') };
    ok( !$result, 'unknown component returns false' );
};

subtest 'add api-route without config' => sub {
    my $orig  = Cwd::getcwd();
    my $empty = tempdir( CLEANUP => 1 );
    chdir $empty or die;

    local %ENV = %ENV;
    delete $ENV{PLUGIN_NAME};

    my $result = _quiet {
        run_add( 'api-route', path => '/foo', method => 'get', operation => 'getFoo' )
    };
    ok( !$result, 'api-route fails without plugin name' );

    chdir $orig or die;
};

done_testing();
