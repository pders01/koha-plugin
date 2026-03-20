package Local::Command::Check;

use strict;
use warnings;

use JSON       qw( decode_json );
use Path::Tiny qw( path );

use Local::Metadata qw( metadata_from_env validate_metadata );
use Local::Config   qw( find_config load_config );
use Local::Util     qw( l );

use Exporter 'import';

our @EXPORT_OK = qw( run_check );

sub run_check {
    my $errors   = 0;
    my $warnings = 0;

    # --- Config ---
    my $config_file = find_config();
    if ( !$config_file ) {
        _err('no config file found (koha-plugin.yml or koha-plugin.json)');
        $errors++;
    }
    else {
        _ok("config: $config_file");
        my $config = load_config($config_file);
        if ( !$config->{name} ) {
            _err('config: name is not set');
            $errors++;
        }
        if ( !$config->{version} ) {
            _err('config: version is not set');
            $errors++;
        }
    }

    # --- Base module ---
    my $metadata   = metadata_from_env();
    my $components = [ split /::/smx, $metadata->{name} // q{} ];
    if ( !$metadata->{name} || @{$components} < 3 ) {
        _err('plugin name not set in config or environment');
        _err('run "koha-plugin init" first');
        $errors++;
        return _summary( $errors, $warnings );
    }

    my $base_path = path( join( q{/}, @{$components} ) . '.pm' );

    if ( !$base_path->exists ) {
        _err("base module not found: $base_path");
        _err('run "koha-plugin init" first');
        $errors++;
        return _summary( $errors, $warnings );
    }
    _ok("base module: $base_path");

    my $content    = $base_path->slurp_utf8;
    my $plugin_dir = path( join q{/}, @{$components} );

    # Check pragma
    if ( $content !~ /use \s+ Modern::Perl/smx ) {
        _warn('base module: missing "use Modern::Perl"');
        $warnings++;
    }

    # Check version in package declaration
    if ( $content !~ /^package \s+ \S+ \s+ v[\d.]+;/smx ) {
        _warn('base module: no version in package declaration');
        $warnings++;
    }

    # --- API consistency ---
    if ( $content =~ /sub \s+ api_routes\b/smx ) {
        my $openapi = path("$plugin_dir/openapi.json");
        if ( !$openapi->exists ) {
            _err('api_routes hook present but openapi.json not found');
            $errors++;
        }
        else {
            _ok('openapi.json exists');
            my $spec = eval { decode_json( $openapi->slurp_utf8 ) };
            if ( !$spec ) {
                _err("openapi.json: invalid JSON — $@");
                $errors++;
            }
            else {
                # Check each x-mojo-to points to an existing controller
                for my $route_path ( keys %{$spec} ) {
                    for my $method ( keys %{ $spec->{$route_path} } ) {
                        my $entry   = $spec->{$route_path}{$method};
                        my $mojo_to = $entry->{'x-mojo-to'} // next;

                        my ( $class, $method_name ) = split /[#]/smx, $mojo_to, 2;
                        my $ctrl_path = path( join( q{/}, 'Koha', 'Plugin', split( /::/smx, $class ) ) . '.pm' );

                        if ( !$ctrl_path->exists ) {
                            _err("$method $route_path: controller not found: $ctrl_path");
                            $errors++;
                        }
                        elsif ($method_name) {
                            my $ctrl_content = $ctrl_path->slurp_utf8;
                            if ( $ctrl_content !~ /sub\s+\Q$method_name\E\b/smx ) {
                                _err("$method $route_path: method '$method_name' not found in $ctrl_path");
                                $errors++;
                            }
                            else {
                                _ok("$method $route_path -> $mojo_to");
                            }
                        }
                    }
                }
            }
        }

        # Check JSON import
        if ( $content !~ /use \s+ (?:Mojo::)?JSON/smx ) {
            _err('api_routes hook present but no JSON module imported');
            $errors++;
        }
    }

    # --- Static routes ---
    if ( $content =~ /sub \s+ static_routes\b/smx ) {
        my $staticapi = path("$plugin_dir/staticapi.json");
        if ( !$staticapi->exists ) {
            _err('static_routes hook present but staticapi.json not found');
            $errors++;
        }
        else {
            _ok('staticapi.json exists');
        }
    }

    # --- UI hooks have matching templates ---
    for my $hook (qw(admin configure report tool)) {
        if ( $content =~ /sub \s+ $hook\b/smx ) {
            my $tt_file = path("$plugin_dir/$hook.tt");
            if ( !$tt_file->exists ) {
                _warn("hook '$hook' present but $tt_file not found (run: koha-plugin add action --type $hook)");
                $warnings++;
            }
            else {
                _ok("$hook.tt exists");
            }
        }
    }

    # --- PLUGIN.yml ---
    my $manifest = path("$plugin_dir/PLUGIN.yml");
    if ( !$manifest->exists ) {
        _warn('PLUGIN.yml manifest not found');
        $warnings++;
    }
    else {
        _ok('PLUGIN.yml exists');
    }

    return _summary( $errors, $warnings );
}

sub _ok {
    my ($msg) = @_;
    l( 'info', "  ok: $msg" );
    return;
}

sub _warn {
    my ($msg) = @_;
    l( 'warning', $msg );
    return;
}

sub _err {
    my ($msg) = @_;
    l( 'error', $msg );
    return;
}

sub _summary {
    my ( $errors, $warnings ) = @_;

    if ( $errors == 0 && $warnings == 0 ) {
        l( 'info', 'check passed — no issues found' );
    }
    elsif ( $errors == 0 ) {
        l( 'info', "check passed with $warnings warning(s)" );
    }
    else {
        l( 'error', "check failed: $errors error(s), $warnings warning(s)" );
    }

    return $errors == 0 ? 1 : 0;
}

1;
