package Local::Command::Init;

use strict;
use warnings;

use File::Path     qw( remove_tree );
use Path::Tiny     qw( cwd path );
use Perl::Tidy     qw( perltidy );
use Readonly       qw( Readonly );
use Template       ();
use Term::Choose   qw( choose );
use Term::UI       ();
use Term::ReadLine ();
use YAML::Tiny     ();

use Local::Config   qw( save_config );
use Local::Metadata qw( metadata_from_env validate_metadata stringify_metadata );
use Local::Util     qw( l asset_dir );

use Exporter 'import';

our @EXPORT_OK = qw( run_init );

Readonly my $CONST => {
    INDEX_TLD         => 2,
    INDEX_ORG         => 3,
    INDEX_PROJECT     => 4,
    LENGTH_COMPONENTS => 5
};

# Hooks are grouped by category for the selection UI.
# Some entries are bundles: 'api' expands to api_namespace + api_routes,
# 'opac_online_payment' includes begin/end/threshold.
Readonly my $HOOKS => [

    # --- Lifecycle ---
    qw( install upgrade uninstall ),

    # --- UI pages ---
    qw( admin configure report tool ),

    # --- API & static files ---
    qw( api static ),

    # --- Staff interface ---
    qw( intranet_head intranet_js
        intranet_catalog_biblio_enhancements_toolbar_button
        intranet_catalog_biblio_tab
        intranet_cover_images ),

    # --- OPAC ---
    qw( opac_head opac_js
        opac_detail_xslt_variables opac_results_xslt_variables
        opac_cover_images
        opac_online_payment ),

    # --- Patron ---
    qw( check_password patron_barcode_transform
        patron_generate_userid patron_consent_type
        auth_client_get_user ),

    # --- Catalog CRUD ---
    qw( before_biblio_action after_biblio_action
        after_item_action after_authority_action ),

    # --- Circulation ---
    qw( after_circ_action after_hold_create after_hold_action
        after_recall_action after_account_action ),

    # --- Notices & messaging ---
    qw( notices_content transform_prepared_letter before_send_messages ),

    # --- ILL ---
    qw( ill_backend new_ill_backend ill_availability_services ),

    # --- Background & scheduling ---
    qw( background_tasks cronjob_nightly ),

    # --- Miscellaneous ---
    qw( edifact to_marc item_barcode_transform
        template_include_paths framework_defaults_override
        before_orderline_create overwrite_calc_fine
        elasticsearch_to_document ),
];

sub run_init {
    my (%opts) = @_;

    my $metadata = metadata_from_env();

    # Non-interactive: skip prompts if metadata is already populated (from config/env)
    if ( !$opts{hooks} ) {
        _prompt_for_metadata($metadata) or do { l( 'info', 'aborting init...' ) and return };
    }
    else {
        # In non-interactive mode, validate what we have
        if ( !validate_metadata($metadata) ) {
            l( 'error', 'metadata validation failed; set values via config file or env vars' );
            return;
        }
    }

    my $cwd        = cwd;
    my $components = [ split /::/smx, $metadata->{name} ];
    my $name       = join q{/}, $components->@*;
    my $path       = path("$cwd/$name");
    if ( !$path->mkpath ) {
        l( 'error', "plugin path could not be created: $path" ) and return;
    }

    if ( !$path->is_dir ) {
        l( 'error', "plugin path is not a directory: $path" ) and return;
    }

    my $ok = eval {
        my $tt = Template->new( { INCLUDE_PATH => asset_dir('templates') } );
        if ($Template::ERROR) {
            die "Template error: $Template::ERROR\n";
        }

        my $base = _base_module_path( $path, $components->@[ $CONST->{'INDEX_PROJECT'} ] );

        # Non-interactive: use provided hooks list; interactive: use Term::Choose
        my $hooks;
        if ( $opts{hooks} ) {
            $hooks = [ split /,/smx, $opts{hooks} ];
        }
        else {
            $hooks = [
                choose(
                    $HOOKS,
                    {   color => 2,
                        info  => qq{Hooks are grouped by category. Bundles:\n}
                            . qq{  api = api_namespace + api_routes\n}
                            . qq{  opac_online_payment = payment + begin/end/threshold},
                        prompt => q{Select with SPACE, confirm with ENTER.}
                    }
                )
            ];
        }

        $tt->process(
            '[a].pm.tt',
            {   tld      => $components->@[ $CONST->{'INDEX_TLD'} ],
                org      => $components->@[ $CONST->{'INDEX_ORG'} ],
                project  => $components->@[ $CONST->{'INDEX_PROJECT'} ],
                version  => $metadata->{version} // '0.0.1',
                metadata => stringify_metadata( { $metadata->%*, name => $components->@[ $CONST->{'INDEX_PROJECT'} ], } ),
                ( $hooks->@* ? map { $_ => 1 } $hooks->@* : () )
            },
            _base_module_path( $path, $components->@[ $CONST->{'INDEX_PROJECT'} ] ),
        );
        if ( $tt->error ) {
            die 'Template processing failed: ' . $tt->error . "\n";
        }

        my $tidy_error = perltidy( argv => q{}, source => $base, destination => $base );
        if ($tidy_error) {
            die "Perl::Tidy failed: $tidy_error\n";
        }

        my $manifest = YAML::Tiny->new( { $metadata->%*, module => join q{::}, $components->@* } );
        if ( !$manifest ) {
            die "manifest could not be generated\n";
        }

        $manifest->write("$path/PLUGIN.yml");

        # Write config file from collected metadata
        save_config( $metadata, 'koha-plugin.yml' );
        l( 'info', 'created koha-plugin.yml' );

        # Create .gitignore for tool artifacts (Koha/ is conventionally committed)
        my $gitignore = path('.gitignore');
        if ( !$gitignore->exists ) {
            $gitignore->spew_utf8(<<'GITIGNORE');
dist/
local/
node_modules/
.env
.env.bak
.DS_Store
*.kpz
GITIGNORE
            l( 'info', 'created .gitignore' );
        }

        my %selected = map { $_ => 1 } $hooks->@*;

        # Generate action templates for selected UI hooks
        my @action_hooks = grep { $selected{$_} } qw(admin configure report tool);
        if (@action_hooks) {
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
            for my $action (@action_hooks) {

                # configure gets its own template with form handling
                my $source = $action eq 'configure' ? 'sites/configure.tt' : 'sites/action.tt';
                $action_tt->process( $source, { project => $components->@[ $CONST->{'INDEX_PROJECT'} ], action => $action },
                    "$path/$action.tt", );
                if ( $action_tt->error ) {
                    l( 'warning', "failed to generate $action.tt: " . $action_tt->error );
                }
                else {
                    l( 'info', "created $action.tt" );
                }
            }
        }

        # Create empty openapi.json when api hooks are selected
        if ( $selected{api} ) {
            my $openapi_dest = path("$path/openapi.json");
            $openapi_dest->spew_utf8("{}\n");
            l( 'info', "created openapi.json — run 'koha-plugin add api-route' to add routes" );
        }

        # Copy staticapi.json template when static hook is selected
        if ( $selected{static} ) {
            my $src  = path( asset_dir('templates/staticapi.json') );
            my $dest = path("$path/staticapi.json");
            if ( $src->exists ) {
                $src->copy($dest);
                l( 'info', 'created staticapi.json' );
            }
            else {
                l( 'warning', 'staticapi.json template not found — create it manually' );
            }
        }

        1;
    };

    if ( !$ok ) {
        l( 'error',   $@ );
        l( 'warning', "cleaning up $path" );
        remove_tree("$path");

        # Also remove the base module file if it was created outside the dir
        my $base_file = _base_module_path( $path, $components->@[ $CONST->{'INDEX_PROJECT'} ] );
        unlink $base_file if -e $base_file;
        return;
    }

    return 1;
}

sub _base_module_path {
    my ( $path, $name ) = @_;
    return join q{.}, $path->sibling($name), 'pm';
}

sub _prompt_for_metadata {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my ($metadata) = @_;
    my $term = Term::ReadLine->new('koha-plugin init');

    my $name_pattern = qr/^Koha::Plugin::[[:alnum:]]+::[[:alnum:]]+::[[:alnum:]]+$/smx;

    while (1) {
        my $name = $term->get_reply(
            prompt  => 'Plugin package name (Koha::Plugin::<TLD>::<ORG>::<PROJECT>):',
            default => $metadata->{name} // q{},
        );
        if ( defined $name && $name =~ $name_pattern ) {
            $metadata->{name} = $name;
        }
        else {
            l( 'warning', 'Invalid name; expected Koha::Plugin::<TLD>::<ORG>::<PROJECT>' );
            next;
        }

        my $author = $term->get_reply( prompt => 'Author:', default => $metadata->{author} // q{} );
        $metadata->{author} = $author // q{};

        my $description = $term->get_reply( prompt => 'Description:', default => $metadata->{description} // q{} );
        $metadata->{description} = $description // q{};

        my $min_ver = $term->get_reply(
            prompt  => 'Minimum Koha version (e.g. 22.11.00.000):',
            default => $metadata->{minimum_version} // q{}
        );
        $metadata->{minimum_version} = $min_ver // q{};

        my $max_ver = $term->get_reply(
            prompt  => 'Maximum Koha version (e.g. 25.05.00.000):',
            default => $metadata->{maximum_version} // q{}
        );
        $metadata->{maximum_version} = $max_ver // q{};

        my $version = $term->get_reply(
            prompt  => 'Plugin version (semver, e.g. 0.1.0):',
            default => $metadata->{version} // '0.1.0'
        );
        $metadata->{version} = $version // q{};

        my $date_authored = $term->get_reply(
            prompt  => 'Date authored (YYYY-MM-DD or today):',
            default => $metadata->{date_authored} // 'today'
        );
        $metadata->{date_authored} = $date_authored // 'today';

        my $date_updated = $term->get_reply(
            prompt  => 'Date updated (YYYY-MM-DD or today):',
            default => $metadata->{date_updated} // 'today'
        );
        $metadata->{date_updated} = $date_updated // 'today';

        # Derive sensible defaults for optional fields
        my $release_default = q{};
        my $static_default  = $metadata->{static_dir_name} // 'static';
        my $parts           = [ split /::/smx, ( $metadata->{name} // q{} ) ];
        if ( @{$parts} == $CONST->{'LENGTH_COMPONENTS'} ) {
            my ( undef, undef, undef, $org, $project ) = @{$parts};
            $release_default = lc join q{-}, $org, $project;
        }

        my $release_filename = $term->get_reply(
            prompt  => 'Release filename (basename for .kpz):',
            default => $metadata->{release_filename} // $release_default
        );
        $metadata->{release_filename} = $release_filename // $release_default;

        my $static_dir = $term->get_reply( prompt => 'Static directory name:', default => $static_default );
        $metadata->{static_dir_name} = $static_dir // $static_default;

        # Validate and loop if errors
        return 1 if validate_metadata($metadata);

        my $retry = $term->get_reply( prompt => 'Validation failed. Retry? (y/N):', default => 'N' );
        return 0 if ( ( $retry // 'N' ) =~ /^[Nn]/smx );

    }
}

1;
