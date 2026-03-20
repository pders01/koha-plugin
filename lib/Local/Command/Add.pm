package Local::Command::Add;

use strict;
use warnings;

use Carp           qw( croak );
use DateTime       ();
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
use Local::Util     qw( l asset_dir resolve );

use Exporter 'import';

our @EXPORT_OK = qw( run_add );

Readonly my $CONST => { INDEX_PROJECT => 4 };

my %COMPONENTS = (
    action      => \&_add_action,
    node        => \&_add_node,
    'api-route' => \&_add_api_route,
    migration   => \&_add_migration,
);

sub run_add {
    my ( $component, %opts ) = @_;

    if ( !$component ) {
        l( 'error', 'component name is required (action, node, api-route, migration)' );
        return;
    }

    my $handler = $COMPONENTS{$component};
    if ( !$handler ) {
        my $available = join ', ', sort keys %COMPONENTS;
        l( 'error', "unknown component: $component (available: $available)" );
        return;
    }

    return $handler->(%opts);
}

sub _add_action {
    my (%opts) = @_;
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
    my $action   = resolve( $opts{type}, sub { choose( [qw(admin configure report tool)] ) } );

    my $cwd        = cwd;
    my $components = [ split /::/smx, $metadata->{name} ];
    my $name       = join q{/}, $components->@*;
    my $path       = path("$cwd/$name");

    my $source = $action eq 'configure' ? 'sites/configure.tt' : 'sites/action.tt';
    $tt->process(
        $source,
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
    my (%opts)     = @_;
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

    my $route_path = resolve(
        $opts{path},
        sub {
            $term->get_reply( prompt => 'Route path (e.g. /widgets or /widgets/{widget_id}):', default => q{} );
        }
    );
    my $method = lc(
        resolve(
            $opts{method},
            sub {
                choose( [qw(get post put patch delete)], { prompt => 'HTTP method:' } );
            }
        ) // q{}
    );
    my $operation_id = resolve(
        $opts{operation},
        sub {
            $term->get_reply( prompt => 'Operation ID (e.g. listWidgets, getWidget):', default => q{} );
        }
    );
    my $controller = resolve(
        $opts{controller},
        sub {
            $term->get_reply( prompt => 'Controller class::method (e.g. WidgetController#list):', default => q{} );
        }
    );
    my $permission_module = resolve(
        $opts{permission},
        sub {
            $term->get_reply(
                prompt  => 'Koha permission module (e.g. catalogue, borrowers, tools):',
                default => 'catalogue'
            );
        }
    );
    my $description = resolve(
        $opts{description},
        sub {
            $term->get_reply( prompt => 'Response description:', default => "Result of $operation_id" );
        }
    );

    if ( !$route_path || $route_path !~ m{^/}smx ) {
        l( 'error', 'route path must start with /' );
        return;
    }
    if ( !$method ) {
        l( 'error', 'HTTP method is required' );
        return;
    }
    if ( !$operation_id ) {
        l( 'error', 'operation ID is required' );
        return;
    }

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

    # Generate controller file if needed
    _ensure_controller( $mojo_to, $operation_id );

    return 1;
}

sub _ensure_controller {
    my ( $mojo_to, $operation_id ) = @_;

    # Parse "TLD::Org::Project::FooController#bar"
    my ( $class, $method_name ) = split /[#]/smx, $mojo_to, 2;
    $method_name //= $operation_id;

    # e.g. Koha/Plugin/TLD/Org/Project/FooController.pm
    my $controller_path = path( join( q{/}, 'Koha', 'Plugin', split( /::/smx, $class ) ) . '.pm' );

    if ( $controller_path->exists ) {
        my $content = $controller_path->slurp_utf8;
        if ( $content !~ /sub\s+\Q$method_name\E\b/smx ) {

            # Append method stub before the final 1;
            my $stub = _method_stub($method_name);
            $content =~ s/^(1;)$/$stub\n$1/smx;
            $controller_path->spew_utf8($content);
            l( 'info', "added method stub '$method_name' to $controller_path" );
        }
        return 1;
    }

    # Create new controller
    $controller_path->parent->mkpath;
    my $package = "Koha::Plugin::$class";
    $controller_path->spew_utf8( _controller_template( $package, $method_name ) );
    l( 'info', "created controller $controller_path" );

    return 1;
}

sub _controller_template {
    my ( $package, $method_name ) = @_;

    return <<"CONTROLLER";
package $package;

use Modern::Perl;

use Mojo::Base 'Mojolicious::Controller';

=head1 API

=head2 Methods

=head3 $method_name

=cut

@{[ _method_stub($method_name) ]}
1;
CONTROLLER
}

sub _method_stub {
    my ($method_name) = @_;

    return <<"STUB";
sub $method_name {
    my \$c = shift->openapi->valid_input or return;

    return \$c->render(
        status  => 200,
        openapi => {},
    );
}
STUB
}

sub _add_migration {
    my (%opts)     = @_;
    my $metadata   = metadata_from_env();
    my $components = [ split /::/smx, $metadata->{name} // q{} ];

    if ( @{$components} != 5 ) {
        l( 'error', 'plugin name must be set in config before adding migrations' );
        return;
    }

    my $plugin_path    = path( join q{/}, $components->@* );
    my $migrations_dir = path("$plugin_path/migrations");
    $migrations_dir->mkpath;

    # Determine next migration number
    my @existing    = sort glob "$migrations_dir/*.sql";
    my $next_number = 1;
    if (@existing) {
        my ($last_file) = reverse @existing;
        my ($last_name) = $last_file =~ m{/(\d+)_}smx;
        $next_number = ( $last_name // 0 ) + 1;
    }

    my $description = resolve(
        $opts{description},
        sub {
            my $term = Term::ReadLine->new('koha-plugin add migration');
            $term->get_reply( prompt => 'Migration description (e.g. create_widgets_table):', default => q{} );
        }
    );
    if ( !$description ) {
        l( 'error', 'description is required' );
        return;
    }

    # Sanitize for filename
    $description =~ s/[^a-zA-Z0-9_]/_/g;

    my $filename = sprintf '%03d_%s.sql', $next_number, $description;
    my $filepath = path("$migrations_dir/$filename");

    $filepath->spew_utf8(<<"SQL");
-- Migration $next_number: $description
-- Created: @{[ DateTime->now->ymd ]}

-- Use {{table_name}} placeholders for table names if using MigrationHelper.
-- Example:
-- CREATE TABLE IF NOT EXISTS {{my_table}} (
--     id INT AUTO_INCREMENT PRIMARY KEY,
--     name VARCHAR(255) NOT NULL,
--     created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
-- ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

SQL

    l( 'info', "created $filepath" );

    # Check if this is the first migration — suggest updating install/upgrade hooks
    if ( $next_number == 1 ) {
        l( 'info', 'this is your first migration — see install/upgrade hooks for integration patterns' );
        l( 'info', 'consider using LMSCloud MigrationHelper: github.com/LMSCloudPaulD/koha-plugin-lmscloud-util' );
    }

    return 1;
}

1;
