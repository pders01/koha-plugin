package Local::Command::Add;

use strict;
use warnings;

use Carp           qw( croak );
use IPC::Open3     qw( open3 );
use JSON           qw( decode_json );
use Path::Tiny     qw( cwd path );
use Readonly       qw( Readonly );
use Symbol         qw( gensym );
use Template       ();
use Term::Choose   qw( choose );
use Term::UI       ();
use Term::ReadLine ();

use Local::Metadata qw( metadata_from_env );
use Local::Util     qw( l asset_dir );

use Exporter 'import';

our @EXPORT_OK = qw( run_add );

Readonly my $CONST => { INDEX_PROJECT => 4 };

my %COMPONENTS = (
    action      => \&_add_action,
    node        => \&_add_node,
    'api-route' => \&_add_api_route,
);

sub run_add {
    my ($component) = @_;

    if ( !$component ) {
        l( 'error', 'component name is required (action, node, api-route)' );
        return;
    }

    my $handler = $COMPONENTS{$component};
    if ( !$handler ) {
        my $available = join ', ', sort keys %COMPONENTS;
        l( 'error', "unknown component: $component (available: $available)" );
        return;
    }

    return $handler->();
}

sub _add_action {
    my $tt = Template->new(
        {   INCLUDE_PATH => asset_dir('templates'),
            START_TAG    => '<%',
            END_TAG      => '%>',
            FILTERS      => {
                capitalize => sub {
                    my $text = shift;
                    $text =~ s/^(\w)/\U$1/smx;
                    return $text;
                }
            }
        }
    );
    if ($Template::ERROR) {
        l( 'error', $Template::ERROR ) and return;
    }

    my $metadata = metadata_from_env();
    my $action   = choose( [qw(admin configure report tool)] );

    my $cwd        = cwd;
    my $components = [ split /::/smx, $metadata->{name} ];
    my $name       = join q{/}, $components->@*;
    my $path       = path("$cwd/$name");

    $tt->process(
        'sites/action.tt',
        {   project => $components->@[-1],
            action  => $action,
        },
        "$path/$action.tt"
    );
    if ( $tt->error ) {
        l( 'error', $tt->error ) and return;
    }

    return 1;
}

sub _add_node {
    my $metadata = metadata_from_env();

    my $j     = JSON->new;
    my $error = gensym;
    my $pid   = open3( undef, undef, $error, 'npm', 'init', '-y' );

    waitpid $pid, 0;

    while (<$error>) {
        print or croak;
    }

    my $path = path('package.json');
    if ( !$path->exists ) {
        l( 'error', 'package.json was not created by `npm init`' );
        return;
    }

    my $json = $j->utf8->decode( $path->slurp_utf8 );
    if ( $metadata->{name} ) {
        $json->{'name'} = lc join q{-}, [ split /::/smx, $metadata->{name} ]->@[ 0 .. 1, $CONST->{'INDEX_PROJECT'} ];
    }

    if ( $metadata->{version} ) {
        $json->{'version'} = $metadata->{version};
    }

    if ( $metadata->{description} ) {
        $json->{'description'} = $metadata->{description};
    }

    if ( $metadata->{author} ) {
        $json->{'author'} = $metadata->{author};
    }

    my $src = path('src');
    if ( !$src->mkdir ) {
        l( 'warning', "src directory could not be created: $src" );
    }

    if ( $src->is_dir ) {
        $json->{'main'} = 'src/index';
    }

    $path->spew_utf8( $j->utf8->pretty->encode($json) );

    return 1;
}

sub _add_api_route {
    my $metadata   = metadata_from_env();
    my $components = [ split /::/smx, $metadata->{name} // q{} ];

    if ( @{$components} != 5 ) {
        l( 'error', 'plugin name must be set in config before adding API routes' );
        return;
    }

    my $plugin_path = path( join q{/}, $components->@* );
    my $spec_file   = path("$plugin_path/openapi.json");

    # Load existing spec or start fresh
    my $spec = {};
    if ( $spec_file->exists ) {
        $spec = decode_json( $spec_file->slurp_utf8 );
    }

    my $term = Term::ReadLine->new('koha-plugin add api-route');

    my $route_path = $term->get_reply(
        prompt  => 'Route path (e.g. /widgets or /widgets/{widget_id}):',
        default => q{},
    );
    if ( !$route_path || $route_path !~ m{^/}smx ) {
        l( 'error', 'route path must start with /' );
        return;
    }

    my $method = lc( choose( [qw(get post put patch delete)], { prompt => 'HTTP method:' } ) // q{} );
    if ( !$method ) {
        l( 'error', 'HTTP method is required' );
        return;
    }

    my $operation_id = $term->get_reply(
        prompt  => 'Operation ID (e.g. listWidgets, getWidget):',
        default => q{},
    );
    if ( !$operation_id ) {
        l( 'error', 'operation ID is required' );
        return;
    }

    my $controller = $term->get_reply(
        prompt  => 'Controller class::method (e.g. WidgetController#list):',
        default => q{},
    );

    my $permission_module = $term->get_reply(
        prompt  => 'Koha permission module (e.g. catalogue, borrowers, tools):',
        default => 'catalogue',
    );

    my $description = $term->get_reply(
        prompt  => 'Response description:',
        default => "Result of $operation_id",
    );

    # Build the route entry
    my $tld     = $components->@[2];
    my $org     = $components->@[3];
    my $project = $components->@[4];
    my $mojo_to
        = $controller
        ? "${tld}::${org}::${project}::${controller}"
        : "${tld}::${org}::${project}::DefaultController#${operation_id}";

    my $route = {
        "x-mojo-to" => $mojo_to,
        operationId => $operation_id,
        tags        => [$project],
        produces    => ['application/json'],
        responses   => {
            '200' => {
                description => $description,
                schema      => { type => 'object' },
            },
            '404' => {
                description => 'Not found',
                schema      => {
                    type       => 'object',
                    properties => {
                        error => {
                            description => 'Error message',
                            type        => 'string',
                        },
                    },
                },
            },
            '500' => {
                description => 'Internal error',
                schema      => {
                    type       => 'object',
                    properties => {
                        error => {
                            description => 'Error message',
                            type        => 'string',
                        },
                    },
                },
            },
        },
        'x-koha-authorization' => { permissions => { $permission_module => '1' }, },
    };

    # Extract path parameters from the route path
    my @path_params;
    while ( $route_path =~ /\{(\w+)\}/g ) {
        push @path_params,
            {
            name        => $1,
            in          => 'path',
            description => "$1 identifier",
            required    => JSON::true,
            type        => 'integer',
            };
    }
    if (@path_params) {
        $route->{parameters} = \@path_params;
    }

    # Merge into spec
    $spec->{$route_path} //= {};
    if ( exists $spec->{$route_path}{$method} ) {
        l( 'warning', "$method $route_path already exists, overwriting" );
    }
    $spec->{$route_path}{$method} = $route;

    # Write back
    my $j = JSON->new->utf8->pretty->canonical;
    $spec_file->parent->mkpath;
    $spec_file->spew_utf8( $j->encode($spec) );

    l( 'info', "added $method $route_path -> $mojo_to" );

    return 1;
}

1;
