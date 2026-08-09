#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use File::Path qw( make_path );
use File::Temp qw( tempdir );
use Path::Tiny qw( path );
use Cwd qw( getcwd );

use FindBin qw( $RealBin );

my $script = "$RealBin/../scripts/package-deb.sh";
ok( -x $script, 'Debian package script is executable' );

my $tmp = tempdir( CLEANUP => 1 );
make_path("$tmp/Koha/Plugin/Com/Example/Demo");
path("$tmp/Koha/Plugin/Com/Example/Demo.pm")->spew_utf8(<<'PLUGIN');
package Koha::Plugin::Com::Example::Demo;
1;
PLUGIN

my $orig = getcwd();
chdir $tmp or die "Cannot chdir to $tmp: $!";

{
    local %ENV = %ENV;
    $ENV{DEB_GENERATE_ONLY}  = 1;
    $ENV{DEB_MAINTAINER}     = 'Jane Doe <jane@example.org>';
    $ENV{PLUGIN_DESCRIPTION} = 'Demo Koha plugin';
    $ENV{PLUGIN_AUTHOR}      = 'Jane Doe';

    is(
        system(
            $script,
            'Koha::Plugin::Com::Example::Demo',
            'demo', '1.2.3', '24.11.00.000', '25.05.00.000', 'out'
        ),
        0,
        'generate-only package command succeeds'
    );
}

my $source = path("$tmp/out/source");
ok( -d $source, 'generated source directory exists' );

my $control = $source->child('debian/control')->slurp_utf8;
like( $control, qr/^Package: koha-plugin-demo$/m, 'package name is derived from release filename' );
like( $control, qr/^Architecture: all$/m, 'package is architecture independent' );
like( $control, qr/koha-common \(>= 24[.]11[.]00\)/, 'minimum Koha package version is enforced' );
like( $control, qr/koha-common \(<< 25[.]06\)/, 'maximum Koha line becomes an exclusive upper bound' );
like( $control, qr/^Maintainer: Jane Doe <jane\@example[.]org>$/m, 'maintainer is emitted' );
ok(
    !grep( { /^ / && length > 80 } split /\n/, $control ),
    'extended description lines do not exceed 80 characters'
);

my $copyright = $source->child('debian/copyright')->slurp_utf8;
like( $copyright, qr/^Copyright: \d{4} Jane Doe$/m, 'copyright notice includes a year and holder' );

my $lintian_overrides = $source->child('debian/koha-plugin-demo.lintian-overrides')->slurp_utf8;
like(
    $lintian_overrides,
    qr/^koha-plugin-demo: initial-upload-closes-no-bugs$/m,
    'non-Debian initial release warning has a narrow documented override'
);

is(
    $source->child('debian/install')->slurp_utf8,
    "Koha usr/share/koha/plugins\n"
        . "debian/configure-instance usr/lib/koha-plugin-demo\n"
        . "debian/unregister usr/lib/koha-plugin-demo\n",
    'shared plugin code and lifecycle helpers have package-managed destinations'
);

my $configure_instance = $source->child('debian/configure-instance')->slurp_utf8;
like( $configure_instance, qr{/usr/share/koha/plugins}, 'instance helper configures the shared plugin directory' );
like( $configure_instance, qr/xmlstarlet ed/, 'instance helper edits Koha configuration as XML' );
like( $configure_instance, qr/before-\$\{PACKAGE_NAME\}/, 'instance helper retains one configuration backup' );
unlike( $configure_instance, qr/\bsed\b/, 'instance helper does not edit XML with sed' );
ok( -x $source->child('debian/configure-instance'), 'instance configuration helper is executable' );

my $smoke = $source->child('debian/tests/smoke')->slurp_utf8;
like( $smoke, qr{/usr/share/koha/plugins/Koha/Plugin/}, 'smoke test checks the shared plugin path' );

my $postinst = $source->child('debian/postinst')->slurp_utf8;
like( $postinst, qr{/usr/share/koha/bin/devel/install_plugins[.]pl}, 'postinst uses packaged Koha plugin installer' );
like( $postinst, qr/--include \$PLUGIN_CLASS/, 'postinst limits registration to this plugin' );
like( $postinst, qr/\$CONFIGURE_INSTANCE.*\$instance/, 'postinst configures each Koha instance first' );
like( $postinst, qr{\$writable_plugins_dir/\$PLUGIN_MODULE}, 'postinst rejects a duplicate writable KPZ copy' );
like(
    $postinst,
    qr{PLUGIN_MODULE='Koha/Plugin/Com/Example/Demo[.]pm'},
    'duplicate check uses the complete path below the instance plugins directory'
);

my $unregister = $source->child('debian/unregister')->slurp_utf8;
like( $unregister, qr/RemovePlugins/, 'unregister helper removes plugin method registrations' );
like( $unregister, qr/disable\s+=> 1/, 'unregister helper preserves plugin data by disabling non-destructively' );
unlike( $unregister, qr/Handler->delete/, 'unregister helper does not invoke destructive plugin uninstall' );
ok( -x $source->child('debian/unregister'), 'unregister helper is executable' );

my $prerm = $source->child('debian/prerm')->slurp_utf8;
like( $prerm, qr{/usr/lib/koha-plugin-demo/unregister}, 'prerm runs the package lifecycle helper' );
unlike( $prerm, qr/perl -[Me]/, 'prerm avoids nested shell quoting of inline Perl' );
like( $prerm, qr/koha-plack --reload/, 'prerm reloads Plack after disabling the plugin' );
like( $prerm, qr/koha-worker --restart/, 'prerm restarts workers after disabling the plugin' );

is( system( 'sh', '-n', $source->child('debian/postinst')->stringify ),          0, 'postinst shell syntax is valid' );
is( system( 'sh', '-n', $source->child('debian/prerm')->stringify ),            0, 'prerm shell syntax is valid' );
is( system( 'sh', '-n', $source->child('debian/configure-instance')->stringify ), 0, 'instance helper shell syntax is valid' );

{
    local %ENV = %ENV;
    $ENV{DEB_GENERATE_ONLY} = 1;
    $ENV{DEB_MAINTAINER}    = 'Jane Doe <jane@example.org>';

    is(
        system(
            $script,
            'Koha::Plugin::Com::Example::Demo',
            'koha-plugin-demo', '1.2.3', '24.11', q{}, 'prefixed'
        ),
        0,
        'an already-prefixed release filename can be generated'
    );
}

my $prefixed_control = path("$tmp/prefixed/source/debian/control")->slurp_utf8;
like( $prefixed_control, qr/^Package: koha-plugin-demo$/m, 'koha-plugin prefix is not duplicated' );

chdir $orig or die "Cannot restore cwd: $!";

done_testing();
