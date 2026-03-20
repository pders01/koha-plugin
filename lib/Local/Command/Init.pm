package Local::Command::Init;

use strict;
use warnings;

use Path::Tiny      qw( cwd path );
use Perl::Tidy      qw( perltidy );
use Readonly        qw( Readonly );
use Template        ();
use Term::Choose    qw( choose );
use Term::UI        ();
use Term::ReadLine  ();
use YAML::Tiny      ();

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

Readonly my $HOOKS => [
    qw(
        install
        upgrade
        uninstall
        admin
        configure
        report
        tool
        api
        static
        edifact
        intranet_catalog_biblio_enhancements_toolbar_button
        intranet_catalog_biblio_tab
        intranet_head
        intranet_js
        check_password
        after_biblio_action
        before_biblio_action
        after_item_action
        opac_detail_xslt_variables
        opac_head
        opac_js
        opac_online_payment
        opac_online_payment_threshold
        opac_results_xslt_variables
        patron_barcode_transform
        item_barcode_transform
        ill_availability_services
        ill_backend
        new_ill_backend
        after_hold_create
        after_circ_action
        after_authority_action
        after_hold_action
        after_recall_action
        after_account_action
        intranet_cover_images
        opac_cover_images
        patron_consent_type
        template_include_paths
        auth_client_get_user
        framework_defaults_override
        before_orderline_create
        overwrite_calc_fine
        elasticsearch_to_document
        notices_content
        background_tasks
        before_send_messages
        cronjob_nightly
        to_marc
        transform_prepared_letter
    )
];

sub run_init {
    my $metadata = metadata_from_env();
    _prompt_for_metadata($metadata) or do { l( 'info', 'aborting init...' ) and return };

    my $cwd        = cwd;
    my $components = [ split /::/smx, $metadata->{name} ];
    my $name       = join q{/}, $components->@*;
    my $path       = path("$cwd/$name");
    if ( !$path->mkdir ) {
        l( 'error', "plugin path could not be created: $path" ) and return;
    }

    if ( !$path->is_dir ) {
        l( 'error', "plugin path is not a directory: $path" ) and return;
    }

    my $tt = Template->new( { INCLUDE_PATH => asset_dir('templates') } );
    if ($Template::ERROR) {
        l( 'error', $Template::ERROR ) and return;
    }

    my $base  = _base_module_path( $path, $components->@[ $CONST->{'INDEX_PROJECT'} ] );
    my $hooks = [
        choose(
            $HOOKS,
            {
                color => 2,
                info  =>
                    q{Please choose the hooks you'd like to use in your plugin. Some are grouped: api, opac_online_payment.},
                prompt => q{Select as many as you like with SPACE, then hit ENTER. :)}
            }
        )
    ];

    $tt->process(
        '[a].pm.tt',
        {
            c        => $components->@[ $CONST->{'INDEX_TLD'} ],
            b        => $components->@[ $CONST->{'INDEX_ORG'} ],
            a        => $components->@[ $CONST->{'INDEX_PROJECT'} ],
            metadata => stringify_metadata($metadata),
            ( $hooks->@* ? map { $_ => 1 } $hooks->@* : () )
        },
        _base_module_path( $path, $components->@[ $CONST->{'INDEX_PROJECT'} ] ),
    );
    if ( $tt->error ) {
        l( 'error', $tt->error ) and return;
    }

    my $error = perltidy( source => $base, destination => $base );
    if ($error) {
        l( 'error', $error ) and return;
    }

    my $manifest = YAML::Tiny->new( { $metadata->%*, module => join q{::}, $components->@* } );
    if ( !$manifest ) {
        l( 'error', 'manifest could not be generated' ) and return;
    }

    $manifest->write("$path/PLUGIN.yml");

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
        } else {
            l( 'warning', 'Invalid name; expected Koha::Plugin::<TLD>::<ORG>::<PROJECT>' );
            next;
        }

        my $author = $term->get_reply( prompt => 'Author:', default => $metadata->{author} // q{} );
        $metadata->{author} = $author // q{};

        my $description = $term->get_reply( prompt => 'Description:', default => $metadata->{description} // q{} );
        $metadata->{description} = $description // q{};

        my $min_ver = $term->get_reply(
            prompt  => 'Minimum Koha version (e.g. 22.11.00.000):',
            default => $metadata->{min_koha_version} // q{}
        );
        $metadata->{min_koha_version} = $min_ver // q{};

        my $max_ver = $term->get_reply(
            prompt  => 'Maximum Koha version (e.g. 25.05.00.000):',
            default => $metadata->{max_koha_version} // q{}
        );
        $metadata->{max_koha_version} = $max_ver // q{};

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

    return 1;
}

1;
