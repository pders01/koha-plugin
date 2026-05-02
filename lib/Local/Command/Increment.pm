package Local::Command::Increment;

use strict;
use warnings;

use DateTime   ();
use JSON       qw( decode_json encode_json );
use List::Util qw( none );
use Path::Tiny qw( path );
use Readonly   qw( Readonly );

use Local::Config qw( load_config save_config find_config );
use Local::Util   qw( l json_encoder );

use Exporter 'import';

our @EXPORT_OK = qw( run_increment );

Readonly my $CONST => {
    INDEX_MAJOR              => 0,
    INDEX_MINOR              => 1,
    INDEX_PATCH              => 2,
    LENGTH_SEMVER_COMPONENTS => 3,
};

sub run_increment {
    my (%opts) = @_;

    my $version = $opts{version};
    my $name    = $opts{name};
    my $type    = $opts{type}  // 'patch';
    my $times   = $opts{times} // 1;

    if ( !$version ) {
        l( 'error', 'version is required for increment' );
        return;
    }

    if ( !$name ) {
        l( 'error', 'name is required for increment' );
        return;
    }

    my $components = [ split /[.]/smx, $version ];
    if ( scalar @{$components} != $CONST->{'LENGTH_SEMVER_COMPONENTS'} ) {
        l( 'error', "invalid semver format: $version (expected X.Y.Z)" );
        return;
    }

    $components = _incremented_components( $components, $type, $times );
    return if !$components;

    my $new_version = _join_components($components);
    if ( !_update_config($new_version) ) {
        l( 'error', 'Updating version in config failed' ) and return;
    }

    if ( !_update_package_json($new_version) ) {
        l( 'error', 'Updating version in package.json failed' ) and return;
    }

    if ( !_update_base_module( $new_version, $name ) ) {
        l( 'error', 'Updating version in package declaration or metadata in base module failed' ) and return;
    }

    return 1;
}

sub _incremented_components {
    my ( $components, $type, $times ) = @_;

    my $clone = [ $components->@* ];
    if ( none { $type eq $_ } qw(major minor patch) ) {
        l( 'error', "unrecognized type: $type" );
        return;
    }

    my $index = $CONST->{ join q{_}, 'INDEX', uc $type };
    while ( $times-- ) {
        $clone->[$index]++;
    }

    # Reset lower-order components per semver convention
    for my $i ( ( $index + 1 ) .. 2 ) {
        $clone->[$i] = 0;
    }

    l( 'info', join q{ }, "incrementing $type version from", _join_components($components), 'to', _join_components($clone) );

    return $clone;
}

sub _update_config {
    my ($new_version) = @_;

    my $config_path = find_config();

    # Fall back to legacy .env if no config file found
    if ( !$config_path ) {
        return _update_dotenv_legacy($new_version);
    }

    my $config = load_config($config_path);
    if ( !$config ) {
        l( 'error', "failed to load config from $config_path" ) and return 0;
    }

    $config->{version}      = $new_version;
    $config->{date_updated} = DateTime->now->ymd(q{-});

    return save_config( $config, $config_path );
}

sub _update_dotenv_legacy {
    my ($new_version) = @_;

    my $dotenv = path('.env');
    if ( !$dotenv->exists ) {
        l( 'error', 'no config file or .env found, aborting...' ) and return 0;
    }

    l( 'warning', 'updating legacy .env file; consider running: koha-plugin migrate' );

    my $lines           = [ $dotenv->lines_utf8( { chomp => 1 } ) ];
    my $version_updated = 0;
    for ( $lines->@* ) {
        if ( /^PLUGIN_VERSION=/smx ) {
            $_               = "PLUGIN_VERSION=$new_version";
            $version_updated = 1;
        }

        if ( $version_updated and /^PLUGIN_DATE_UPDATED=/smx ) {
            $_ = join q{}, 'PLUGIN_DATE_UPDATED=', DateTime->now->ymd(q{-});
        }
    }

    return $dotenv->spew_utf8( join( "\n", $lines->@* ) . "\n" );
}

sub _update_package_json {
    my ($new_version) = @_;

    my $package_json = path('package.json');
    if ( !$package_json->exists ) {
        l( 'info', 'package.json not found, skipping...' ) and return 1;
    }

    my $contents = $package_json->slurp_utf8;
    my $data     = decode_json($contents);

    $data->{version} = $new_version;

    my $j = json_encoder();
    return $package_json->spew_utf8( $j->encode($data) );
}

sub _update_base_module {
    my ( $new_version, $name ) = @_;

    my $base_module = path( join( q{/}, split /::/smx, $name ) . '.pm' );
    if ( !$base_module->exists ) {
        l( 'error', 'Base module not found' ) and return 0;
    }

    my $lines       = [ $base_module->lines_utf8( { chomp => 1 } ) ];
    my $in_metadata = 0;
    for ( $lines->@* ) {

        # Update the version in the package declaration
        if ( /^package\s+([[:alnum:]:]+)\s+v([\d]+[.][\d]+[.][\d]+);/smx ) {
            my $package_name = $1;
            $_ = "package $package_name v$new_version;";
        }

        # Detect if we are inside the $metadata block
        if ( /\$metadata\s*=\s*{/smx ) {
            $in_metadata = 1;
        }

        # Only handle lines inside $metadata block — preserve user's formatting
        if ($in_metadata) {
            if ( /^(\s*'?version'?\s*=>\s*')[\d]+[.][\d]+[.][\d]+(',?)$/smx ) {
                $_ = "${1}${new_version}${2}";
            }

            if ( /^(\s*'?date_updated'?\s*=>\s*')[\d]+-[\d]+-[\d]+(',?)$/smx ) {
                my $date = DateTime->now->ymd(q{-});
                $_ = "${1}${date}${2}";
            }

            if ( /\s*};\s*/smx ) {
                $in_metadata = 0;
            }
        }

    }

    return $base_module->spew_utf8( join "\n", $lines->@* );
}

sub _join_components {
    my ($components) = @_;
    return join q{.}, $components->@*;
}

1;
