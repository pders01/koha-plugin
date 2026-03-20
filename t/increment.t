#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use File::Temp qw( tempdir );
use File::Spec ();

use FindBin qw( $RealBin );
use lib "$RealBin/../lib";
BEGIN { my $l = "$RealBin/../local/lib/perl5"; unshift @INC, $l if -d $l }

use Local::Command::Increment qw( run_increment );
use Local::Config             qw( save_config load_config );

my $tmpdir = tempdir( CLEANUP => 1 );

# Helper to suppress log output
sub _quiet (&) {
    my ($code) = @_;
    my $output = q{};
    local *STDOUT;
    open STDOUT, '>', \$output or die;
    return $code->();
}

# --- Version incrementing with config file ---

subtest 'increment patch version via config' => sub {
    my $orig = Cwd::getcwd();
    chdir $tmpdir or die "Cannot chdir: $!";

    save_config( { name => 'Koha::Plugin::Com::Example::Inc', version => '1.0.0' }, 'koha-plugin.yml', );

    # Create a minimal base module
    my $mod_dir = File::Spec->catdir( $tmpdir, 'Koha', 'Plugin', 'Com', 'Example' );
    require File::Path;
    File::Path::make_path($mod_dir);
    my $mod_path = File::Spec->catfile( $mod_dir, 'Inc.pm' );
    open my $fh, '>', $mod_path or die;
    print {$fh} <<'MODULE';
package Koha::Plugin::Com::Example::Inc v1.0.0;
our $metadata = {
    'version'      => '1.0.0',
    'date_updated' => '2025-01-01',
};
1;
MODULE
    close $fh;

    my $result = _quiet {
        run_increment(
            version => '1.0.0',
            name    => 'Koha::Plugin::Com::Example::Inc',
            type    => 'patch',
            times   => 1,
        )
    };

    ok( $result, 'increment returns true' );

    # Check config was updated
    my $config = load_config('koha-plugin.yml');
    is( $config->{version}, '1.0.1', 'config version incremented' );
    like( $config->{date_updated}, qr/^\d{4}-\d{2}-\d{2}$/, 'date_updated set' );

    # Check base module was updated
    open $fh, '<', $mod_path or die;
    my $content = do { local $/; <$fh> };
    close $fh;
    like( $content, qr/v1\.0\.1/, 'module version incremented' );

    unlink 'koha-plugin.yml';
    chdir $orig or die;
};

subtest 'increment minor version multiple times' => sub {
    my $orig = Cwd::getcwd();
    chdir $tmpdir or die "Cannot chdir: $!";

    save_config( { name => 'Koha::Plugin::Com::Example::Inc', version => '1.0.0' }, 'koha-plugin.yml', );

    # Recreate base module
    my $mod_path = File::Spec->catfile( $tmpdir, 'Koha', 'Plugin', 'Com', 'Example', 'Inc.pm' );
    open my $fh, '>', $mod_path or die;
    print {$fh} <<'MODULE';
package Koha::Plugin::Com::Example::Inc v1.0.0;
our $metadata = {
    'version'      => '1.0.0',
    'date_updated' => '2025-01-01',
};
1;
MODULE
    close $fh;

    my $result = _quiet {
        run_increment(
            version => '1.0.0',
            name    => 'Koha::Plugin::Com::Example::Inc',
            type    => 'minor',
            times   => 3,
        )
    };

    ok( $result, 'increment returns true' );

    my $config = load_config('koha-plugin.yml');
    is( $config->{version}, '1.3.0', 'minor incremented 3 times' );

    unlink 'koha-plugin.yml';
    chdir $orig or die;
};

subtest 'increment fails with invalid version' => sub {
    my $result = _quiet {
        run_increment(
            version => 'not-semver',
            name    => 'Koha::Plugin::Com::Example::Inc',
            type    => 'patch',
            times   => 1,
        )
    };

    ok( !$result, 'rejects invalid semver' );
};

subtest 'increment fails with invalid type' => sub {
    my $result = _quiet {
        run_increment(
            version => '1.0.0',
            name    => 'Koha::Plugin::Com::Example::Inc',
            type    => 'supermajor',
            times   => 1,
        )
    };

    ok( !$result, 'rejects invalid type' );
};

subtest 'increment fails without version' => sub {
    my $result = _quiet {
        run_increment(
            name => 'Koha::Plugin::Com::Example::Inc',
            type => 'patch',
        )
    };

    ok( !$result, 'fails without version' );
};

subtest 'increment fails without name' => sub {
    my $result = _quiet {
        run_increment(
            version => '1.0.0',
            type    => 'patch',
        )
    };

    ok( !$result, 'fails without name' );
};

done_testing();
