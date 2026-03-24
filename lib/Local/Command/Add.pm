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
use Local::Util     qw( l asset_dir resolve json_encoder );

use Exporter 'import';

our @EXPORT_OK = qw( run_add );

Readonly my $CONST => { INDEX_PROJECT => 4 };

my %COMPONENTS = (
    action           => \&_add_action,
    node             => \&_add_node,
    'api-route'      => \&_add_api_route,
    migration        => \&_add_migration,
    hook             => \&_add_hook,
    'background-job' => \&_add_background_job,
    vue              => \&_add_vue,
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
    my (%opts)     = @_;
    my $metadata   = metadata_from_env();
    my $components = [ split /::/smx, $metadata->{name} // q{} ];

    if ( @{$components} != 5 ) {
        l( 'error', 'plugin name must be set in config before adding actions' );
        return;
    }

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

    my $action = resolve( $opts{type}, sub { choose( [qw(admin configure report tool)] ) } );

    my $cwd  = cwd;
    my $name = join q{/}, $components->@*;
    my $path = path("$cwd/$name");

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

    my $json = decode_json( $path->slurp_utf8 );
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

    $path->spew_utf8( json_encoder()->encode($json) );

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

    if ( !$route_path || $route_path !~ m{^/[a-zA-Z0-9_/{}\-]*$}smx ) {
        l( 'error', 'route path must start with / and contain only alphanumeric, _, -, {, } characters' );
        return;
    }
    if ( !$method || $method !~ /^(get|post|put|patch|delete)$/smx ) {
        l( 'error', 'HTTP method must be one of: get, post, put, patch, delete' );
        return;
    }
    if ( !$operation_id || $operation_id !~ /^[A-Za-z_][A-Za-z0-9_]*$/smx ) {
        l( 'error', 'operation ID must be a valid identifier (alphanumeric + underscore)' );
        return;
    }
    if ( $controller && $controller !~ m{^[A-Za-z][A-Za-z0-9:]*(\#[A-Za-z_][A-Za-z0-9_]*)?$}sm ) {
        l( 'error', 'controller must match ClassName or ClassName#method format (no spaces or special chars)' );
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

    my $error_schema = {
        type       => 'object',
        properties => { error => { description => 'Error message', type => 'string' }, },
    };

    # Method-specific response codes and schemas
    my %method_config = (
        get    => { success_code => '200', response_schema => { type => 'object' } },
        post   => { success_code => '201', response_schema => { type => 'object' } },
        put    => { success_code => '200', response_schema => { type => 'object' } },
        patch  => { success_code => '200', response_schema => { type => 'object' } },
        delete => { success_code => '204', response_schema => undef },
    );

    my $config       = $method_config{$method};
    my $success_code = $config->{success_code};

    # List endpoints (no path params + GET) return arrays
    my $is_list = ( $method eq 'get' && $route_path !~ /\{/smx );
    if ($is_list) {
        $config->{response_schema} = {
            type  => 'array',
            items => { type => 'object' },
        };
    }

    my %responses = (
        $success_code => {
            description => $description,
            ( $config->{response_schema} ? ( schema => $config->{response_schema} ) : () ),
        },
        '403' => { description => 'Access forbidden', schema => $error_schema },
        '500' => { description => 'Internal error',   schema => $error_schema },
    );

    # Add 404 for single-resource endpoints
    if ( !$is_list && $method ne 'post' ) {
        $responses{'404'} = { description => 'Not found', schema => $error_schema };
    }

    my $route = {
        "x-mojo-to"            => $mojo_to,
        operationId            => $operation_id,
        summary                => $description,
        tags                   => [$project],
        produces               => ['application/json'],
        responses              => \%responses,
        'x-koha-authorization' => { permissions => { $permission_module => '1' } },
    };

    # POST/PUT/PATCH accept JSON bodies
    if ( $method =~ /^(post|put|patch)$/smx ) {
        $route->{consumes} = ['application/json'];
    }

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
    my $j = json_encoder();
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

use Try::Tiny qw( catch try );

=head1 API

=head2 Methods

=cut

@{[ _method_stub($method_name) ]}
1;
CONTROLLER
}

sub _method_stub {
    my ($method_name) = @_;

    # Method-specific response patterns matching Koha conventions
    my %responses = (
        add => <<'ADD',
        return $c->render(
            status  => 201,
            openapi => {},
        );
ADD
        delete => <<'DELETE',
        return $c->render_resource_deleted;
DELETE
    );

    my $response = $responses{$method_name} // <<'DEFAULT';
        return $c->render(
            status  => 200,
            openapi => {},
        );
DEFAULT

    return <<"STUB";
=head3 $method_name

=cut

sub $method_name {
    my \$c = shift->openapi->valid_input or return;

    return try {
$response    }
    catch {
        \$c->unhandled_exception(\$_);
    };
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

my %HOOK_BUNDLES = (
    'api (api_namespace + api_routes)'                    => [qw( api_namespace api_routes )],
    'static (static_routes + api_namespace)'              => [qw( api_namespace static_routes )],
    'opac_online_payment (payment + begin/end/threshold)' =>
        [qw( opac_online_payment opac_online_payment_begin opac_online_payment_end opac_online_payment_threshold )],
);

# Reverse lookup: CLI shorthand -> bundle
my %HOOK_ALIASES = (
    api                 => $HOOK_BUNDLES{'api (api_namespace + api_routes)'},
    static              => $HOOK_BUNDLES{'static (static_routes + api_namespace)'},
    opac_online_payment => $HOOK_BUNDLES{'opac_online_payment (payment + begin/end/threshold)'},
);

sub _add_hook {
    my (%opts)     = @_;
    my $metadata   = metadata_from_env();
    my $components = [ split /::/smx, $metadata->{name} // q{} ];

    if ( @{$components} != 5 ) {
        l( 'error', 'plugin name must be set in config before adding hooks' );
        return;
    }

    # Discover available hooks from templates
    my $hooks_dir     = asset_dir('templates/hooks');
    my @available     = map {s{.*/|\.pl$}{}gr} glob "$hooks_dir/*.pl";
    my %available_set = map { $_ => 1 } @available;

    # Build chooser list: bundles first, then individual hooks
    my @chooser_items = ( sort keys %HOOK_BUNDLES, '---', sort @available );

    my $selection = resolve( $opts{type}, sub { choose( \@chooser_items, { prompt => 'Select hook or bundle to add:' } ) } );

    return if !$selection || $selection eq '---';

    # Resolve selection to a list of hooks
    my @hooks_to_add;
    if ( $HOOK_BUNDLES{$selection} ) {
        @hooks_to_add = $HOOK_BUNDLES{$selection}->@*;
    }
    elsif ( $HOOK_ALIASES{$selection} ) {
        @hooks_to_add = $HOOK_ALIASES{$selection}->@*;
    }
    elsif ( $available_set{$selection} ) {
        @hooks_to_add = ($selection);
    }
    else {
        l( 'error', "unknown hook: $selection" );
        return;
    }

    # Find the base module
    my $base_module = path( join( q{/}, $components->@* ) . '.pm' );
    if ( !$base_module->exists ) {
        l( 'error', "base module not found: $base_module" );
        return;
    }

    my $content    = $base_module->slurp_utf8;
    my $project    = $components->@[4];
    my $plugin_dir = path( join q{/}, $components->@* );
    my $tt         = Template->new( { INCLUDE_PATH => $hooks_dir } );

    my $added = 0;
    for my $hook_name (@hooks_to_add) {

        # Skip if already present
        if ( $content =~ /sub \s+ \Q$hook_name\E\b/smx ) {
            l( 'warning', "$hook_name is already implemented, skipping" );
            next;
        }

        # Render the hook template
        my $rendered;
        $tt->process( "$hook_name.pl", { project => $project }, \$rendered );
        if ( $tt->error ) {
            l( 'error', "template processing failed for $hook_name: " . $tt->error );
            next;
        }

        # Insert before the final 1;
        $content =~ s/^(1;\s*)$/\n$rendered\n$1/smx;
        l( 'info', "added hook '$hook_name'" );
        $added++;

        # Generate companion files
        _hook_companions( $hook_name, $project, $plugin_dir );
    }

    if ($added) {
        $base_module->spew_utf8($content);
    }

    return $added ? 1 : 0;
}

sub _hook_companions {
    my ( $hook_name, $project, $plugin_dir ) = @_;

    # UI hooks get a template file
    my %ui_hooks = map { $_ => 1 } qw(admin configure report tool);
    if ( $ui_hooks{$hook_name} ) {
        my $source = $hook_name eq 'configure' ? 'sites/configure.tt' : 'sites/action.tt';
        my $dest   = "$plugin_dir/$hook_name.tt";
        if ( !-e $dest ) {
            my $action_tt = Template->new(
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
            $action_tt->process( $source, { project => $project, action => $hook_name }, $dest );
            l( 'info', "created $dest" ) unless $action_tt->error;
        }
    }

    # API hooks get openapi.json
    if ( $hook_name eq 'api_namespace' || $hook_name eq 'api_routes' ) {
        my $openapi = path("$plugin_dir/openapi.json");
        if ( !$openapi->exists ) {
            $openapi->parent->mkpath;
            $openapi->spew_utf8("{}\n");
            l( 'info', "created openapi.json" );
        }
    }

    # Static routes get staticapi.json
    if ( $hook_name eq 'static_routes' ) {
        my $dest = path("$plugin_dir/staticapi.json");
        if ( !$dest->exists ) {
            my $src = path( asset_dir('templates/staticapi.json') );
            if ( $src->exists ) {
                $dest->parent->mkpath;
                $src->copy($dest);
                l( 'info', 'created staticapi.json' );
            }
        }
    }

    return;
}

sub _add_background_job {
    my (%opts)     = @_;
    my $metadata   = metadata_from_env();
    my $components = [ split /::/smx, $metadata->{name} // q{} ];

    if ( @{$components} != 5 ) {
        l( 'error', 'plugin name must be set in config before adding background jobs' );
        return;
    }

    my $job_name = resolve(
        $opts{type},
        sub {
            my $term = Term::ReadLine->new('koha-plugin add background-job');
            $term->get_reply( prompt => 'Job type name (e.g. sync_records):', default => q{} );
        }
    );

    if ( !$job_name || $job_name !~ /^[a-z][a-z0-9_]*$/smx ) {
        l( 'error', 'job type must be lowercase alphanumeric with underscores' );
        return;
    }

    # Derive class name: sync_records -> SyncRecords
    my $class_name = resolve( $opts{class}, join( q{}, map { ucfirst $_ } split /_/smx, $job_name ) );

    my $tld     = $components->@[2];
    my $org     = $components->@[3];
    my $project = $components->@[4];

    my $full_class = "Koha::Plugin::${tld}::${org}::${project}::${class_name}";
    my $job_path   = path( join( q{/}, 'Koha', 'Plugin', $tld, $org, $project, $class_name ) . '.pm' );

    # Create the job class
    if ( $job_path->exists ) {
        l( 'warning', "$job_path already exists, skipping class creation" );
    }
    else {
        $job_path->parent->mkpath;
        $job_path->spew_utf8( _background_job_template( $full_class, $job_name ) );
        l( 'info', "created job class $job_path" );
    }

    # Update background_tasks in the base module
    my $base_module = path( join( q{/}, $components->@* ) . '.pm' );
    if ( !$base_module->exists ) {
        l( 'error', "base module not found: $base_module" );
        return;
    }

    my $content = $base_module->slurp_utf8;

    # Check if background_tasks hook exists
    if ( $content !~ /sub \s+ background_tasks\b/smx ) {
        l( 'error', "background_tasks hook not found in $base_module (run: koha-plugin add hook --type background_tasks)" );
        return;
    }

    # Check if this job is already registered
    if ( $content =~ /\Q$job_name\E\s*=>/smx ) {
        l( 'warning', "job '$job_name' is already registered in background_tasks" );
        return 1;
    }

    # Update the return hash in background_tasks
    my $entry = "        $job_name => '$full_class',\n";
    if ( $content =~ s/(sub \s+ background_tasks \s* \{ \s* return \s*) \{\}; /$1\{\n$entry    };/smx ) {

        # Replaced empty hash
    }
    elsif ( $content =~ s/(sub \s+ background_tasks \s* \{ \s* return \s* \{ .+?) (\n \s* \}; )/$1\n$entry$2/smx ) {

        # Appended to existing hash
    }
    else {
        l( 'warning', "could not auto-register '$job_name' — add to background_tasks manually:" );
        l( 'info',    "    $job_name => '$full_class'" );
    }

    $base_module->spew_utf8($content);
    l( 'info', "registered job '$job_name' in background_tasks" );

    return 1;
}

sub _background_job_template {
    my ( $package, $job_type ) = @_;

    return <<"JOB";
package $package;

use Modern::Perl;

use base 'Koha::BackgroundJob';

=head1 NAME

$package - Background job

=head1 API

=head2 Class methods

=head3 job_type

=cut

sub job_type {
    return '$job_type';
}

=head3 process

=cut

sub process {
    my ( \$self, \$args ) = \@_;

    \$self->start;

    my \$data = {};

    # TODO: implement job logic here

    \$self->finish( { data => \$data } );
}

=head3 enqueue

=cut

sub enqueue {
    my ( \$self, \$args ) = \@_;

    \$self->SUPER::enqueue(
        {
            job_size  => 1,
            job_args  => \$args,
            job_queue => 'default',
        }
    );
}

1;
JOB
}

sub _add_vue {
    my (%opts)     = @_;
    my $metadata   = metadata_from_env();
    my $components = [ split /::/smx, $metadata->{name} // q{} ];

    if ( @{$components} != 5 ) {
        l( 'error', 'plugin name must be set in config before adding vue components' );
        return;
    }

    my $project    = $components->@[4];
    my $plugin_dir = path( join q{/}, $components->@* );

    my $component_name = resolve(
        $opts{name},
        sub {
            my $term = Term::ReadLine->new('koha-plugin add vue');
            $term->get_reply( prompt => 'Component name (e.g. NotesPanel):', default => "${project}Widget" );
        }
    );

    if ( !$component_name || $component_name !~ /^[A-Z][A-Za-z0-9]*$/smx ) {
        l( 'error', 'component name must be PascalCase (e.g. NotesPanel)' );
        return;
    }

    # Derive tag name: NotesPanel -> plugin-notes-panel
    my $default_tag = 'plugin-' . lc( join '-', ( $component_name =~ /([A-Z][a-z0-9]*)/g ) );
    my $tag_name    = resolve(
        $opts{tag},
        sub {
            my $term = Term::ReadLine->new('koha-plugin add vue');
            $term->get_reply( prompt => 'Custom element tag name:', default => $default_tag );
        }
    );

    if ( !$tag_name || $tag_name !~ /^[a-z][a-z0-9]*-[a-z0-9-]*$/smx ) {
        l( 'error', 'tag name must be lowercase with a hyphen (e.g. plugin-notes-panel)' );
        return;
    }

    # Create directories
    my $src_dir    = path('src/components');
    my $static_dir = path("$plugin_dir/dist");
    $src_dir->mkpath;
    $static_dir->mkpath;

    # Write Vue SFC
    my $vue_file = path("src/components/$component_name.vue");
    if ( $vue_file->exists ) {
        l( 'warning', "$vue_file already exists, skipping" );
    }
    else {
        $vue_file->spew_utf8( _vue_sfc_template( $component_name, $tag_name ) );
        l( 'info', "created $vue_file" );
    }

    # Write entry point
    my $entry = path('src/main.js');
    if ( $entry->exists ) {
        l( 'warning', "src/main.js already exists, skipping" );
    }
    else {
        $entry->spew_utf8( _vue_entry_template($component_name) );
        l( 'info', 'created src/main.js' );
    }

    # Write vite config
    my $vite_config = path('vite.config.js');
    if ( $vite_config->exists ) {
        l( 'warning', 'vite.config.js already exists, skipping' );
    }
    else {
        my $out_dir = "$plugin_dir";
        $vite_config->spew_utf8( _vite_config_template( $component_name, $out_dir ) );
        l( 'info', 'created vite.config.js' );
    }

    # Write or update package.json
    my $pkg = path('package.json');
    if ( $pkg->exists ) {
        my $json = decode_json( $pkg->slurp_utf8 );
        $json->{scripts}{'build'} //= 'vite build';
        $json->{scripts}{'dev'}   //= 'vite build --watch';
        my $j = json_encoder();
        $pkg->spew_utf8( $j->encode($json) );
        l( 'info', 'updated package.json with build scripts' );
    }
    else {
        my $j        = json_encoder();
        my $pkg_data = {
            name    => lc "koha-plugin-$project",
            version => $metadata->{version} // '0.1.0',
            private => JSON::true,
            type    => 'module',
            scripts => {
                build => 'vite build',
                dev   => 'vite build --watch',
            },
            dependencies    => { vue => '^3.5.0', },
            devDependencies => {
                vite                  => '^6.0.0',
                "\@vitejs/plugin-vue" => '^5.0.0',
            },
        };
        $pkg->spew_utf8( $j->encode($pkg_data) );
        l( 'info', 'created package.json' );
    }

    # Auto-wire intranet_js hook with island registration
    my $api_ns      = lc $project;
    my $base_module = path( join( q{/}, $components->@* ) . '.pm' );

    if ( $base_module->exists ) {
        my $content    = $base_module->slurp_utf8;
        my $js_snippet = _island_js_snippet( $api_ns, $component_name, $tag_name );

        if ( $content =~ /sub \s+ intranet_js\b/smx ) {

            # Append island registration to the intranet_js heredoc
            if ( $content =~ s/(return \s* <<~\s*'JS'\s*;)\n/$1\n$js_snippet\n/smx ) {
                $base_module->spew_utf8($content);
                l( 'info', "wired $tag_name into intranet_js" );
            }
            else {
                l( 'warning', 'could not auto-wire intranet_js — add the registration manually' );
            }
        }
        else {
            l( 'info', 'intranet_js hook not found — adding it' );

            # Use the hook mechanism to add it, then wire
            run_add( 'hook', type => 'intranet_js' );

            # Re-read and inject
            $content = $base_module->slurp_utf8;
            if ( $content =~ s/(return \s* <<~\s*'JS'\s*;)\n/$1\n$js_snippet\n/smx ) {
                $base_module->spew_utf8($content);
                l( 'info', "wired $tag_name into intranet_js" );
            }
        }
    }

    l( 'info', 'next steps:' );
    l( 'info', '  1. npm install' );
    l( 'info', "  2. edit src/components/$component_name.vue" );
    l( 'info', '  3. npm run build' );
    l( 'info', '  4. koha-plugin staticapi && koha-plugin ktd' );

    return 1;
}

sub _island_js_snippet {
    my ( $api_ns, $component_name, $tag_name ) = @_;

    return <<"SNIPPET";
    <link rel="stylesheet" href="/api/v1/contrib/$api_ns/static/$component_name.css">
    <script type="module">
      const islandsSrc = document.querySelector("script[src*='islands.esm']")?.src;
      if (islandsSrc) {
        const { registerIsland, hydrate } = await import(islandsSrc);
        registerIsland("$tag_name", {
          importFn: async () => {
            const mod = await import("/api/v1/contrib/$api_ns/static/$component_name.js");
            return mod.default;
          },
          config: { stores: [] },
        });
        const main = document.querySelector(".main.container-fluid");
        if (main) {
          const el = document.createElement("$tag_name");
          main.prepend(el);
        }
        hydrate();
      }
    </script>
SNIPPET
}

sub _vue_sfc_template {
    my ( $name, $tag ) = @_;

    return <<"VUE";
<script setup>
defineProps({
  greeting: {
    type: String,
    default: "Hello from $name!",
  },
});
</script>

<template>
  <div class="plugin-island">
    <h4>$name</h4>
    <p>{{ greeting }}</p>
  </div>
</template>

<style>
.plugin-island {
  font-family: inherit;
  padding: 1.5em;
  margin: 1em 0;
  border-left: 4px solid #4caf50;
  background: #f8fdf8;
  border-radius: 4px;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.08);
}

.plugin-island h4 {
  margin: 0 0 0.5em;
  color: #2e7d32;
}

.plugin-island p {
  margin: 0;
}
</style>
VUE
}

sub _vue_entry_template {
    my ($name) = @_;

    return <<"ENTRY";
import $name from "./components/$name.vue";
export default $name;
ENTRY
}

sub _vite_config_template {
    my ( $name, $out_dir ) = @_;

    return <<"VITE";
import { defineConfig } from "vite";
import vue from "\@vitejs/plugin-vue";

export default defineConfig({
  plugins: [vue()],
  define: {
    "process.env.NODE_ENV": JSON.stringify("production"),
  },
  build: {
    lib: {
      entry: "src/main.js",
      formats: ["es"],
      fileName: "$name",
    },
    outDir: "$out_dir",
    emptyOutDir: false,
    rollupOptions: {
      external: ["vue"],
    },
  },
});
VITE
}

1;
