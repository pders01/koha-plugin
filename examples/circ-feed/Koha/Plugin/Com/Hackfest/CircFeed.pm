package Koha::Plugin::Com::Hackfest::CircFeed v0.1.0;

use Modern::Perl;

use base qw(Koha::Plugins::Base);

use Mojo::JSON qw( decode_json );

use C4::Context ();
use Koha::Items  ();
use Koha::Patrons ();

our $metadata = {
    'author'           => 'Paul Derscheid',
    'date_authored'    => '2026-03-20',
    'date_updated'     => '2026-03-20',
    'description'      => 'Live circulation activity feed via SSE and Vue island',
    'maximum_version'  => '',
    'minimum_version'  => '23.11.00.000',
    'name'             => 'CircFeed',
    'release_filename' => 'hackfest-circfeed',
    'static_dir_name'  => 'static',
    'version'          => '0.1.0',
};

sub new {
    my ( $class, $args ) = @_;

    return $class->SUPER::new( { ( $args // {} )->%*, metadata => { $metadata->%*, class => $class } } );
}

=head3 install

This is the 'install' method. Any database tables or other setup that should
be done when the plugin is first installed should be executed in this method.

The installation method should always return true if the installation succeeded
or false if it failed.

Context: One-time setup when the plugin is first installed.

=over 4

=item *

B<Parameters>

=over 8

=item *

C<$self> - Koha::Plugin object (plugin instance)

=item *

C<$args> - HashRef containing arguments for installation

=back

=item *

B<Returns>

Boolean (true on success, false on failure)

=back

=cut

sub install() {
    my ( $self, $args ) = @_;

    my $dbh = C4::Context->dbh;
    my $sql = $self->mbf_read('migrations/001_create_circ_events_table.sql');
    for my $stmt ( grep { /\S/ } split /;\s*\n/smx, $sql ) {
        $dbh->do($stmt);
    }

    return 1;
}

=head3 upgrade

This subroutine is triggered when a newer version of the plugin is installed over an existing older version.

It is typically used to handle any data migration, cleanup, or updates that need to occur when the plugin is upgraded. The method can store relevant upgrade data, such as the timestamp of the last upgrade.

Context: Run on plugin upgrade to handle migrations or data changes.

=over 4

=item *

B<Parameters>

=over 8

=item *

C<$self> - Koha::Plugin object (plugin instance)

=item *

C<$args> - HashRef containing optional parameters related to the upgrade process

=back

=item *

B<Returns>

Boolean - true if the upgrade succeeded

=back

=cut

sub upgrade {
    my ( $self, $args ) = @_;

    # Option 1: Version-conditional inline DDL
    # my $dt = dt_from_string();
    # if ( $self->retrieve_data('__version__') lt '1.1.0' ) {
    #     my $dbh = C4::Context->dbh;
    #     $dbh->do(q{ ALTER TABLE plugin_example ADD COLUMN status VARCHAR(50) });
    #     $self->store_data({ '__version__' => '1.1.0' });
    # }

    # Option 2: Use MigrationHelper with SQL files in migrations/
    # See: github.com/LMSCloudPaulD/koha-plugin-lmscloud-util
    # Create migration files with: koha-plugin add migration
    #
    # use Koha::Plugin::Com::LMSCloud::Util::MigrationHelper;
    # my $helper = Koha::Plugin::Com::LMSCloud::Util::MigrationHelper->new({
    #     bundle_path        => $self->bundle_path,
    #     table_name_mappings => { my_table => 'plugin_mytable' },
    # });
    # return $helper->upgrade({ plugin => $self });

    return 1;
}

=head3 uninstall

This subroutine is run just before the plugin files are deleted when a plugin is uninstalled.

It is good practice to clean up any data or database changes made by the plugin during its use. 
This might include removing custom database tables or other resources used by the plugin.

Context: Cleanup operations prior to plugin removal.

=over 4

=item *

B<Parameters>

=over 8

=item *

C<$self> - Koha::Plugin object (plugin instance)

=item *

C<$args> - HashRef containing additional arguments for cleanup (optional)

=back

=item *

B<Returns>

Void

=back

=cut

sub uninstall {
    my ( $self, $args ) = @_;

    return;
}

=head3 configure

This subroutine provides the plugin's configuration interface.

On GET (no 'save' param): renders the configure.tt template with current settings
pre-filled via C<retrieve_data>. On POST (save param present): stores form data
via C<store_data> and redirects to the plugin home page.

Context: Add a configuration interface for the plugin (render and/or save form data).

=over 4

=item * Parameters

=over 8

=item * C<$self> - Koha::Plugin object (plugin instance)

=item * C<$args> - HashRef of optional arguments for configuration handling

=back

=item * Returns

Void (HTML output via output_html, or redirect via go_home)

=back

=cut

sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    if ( $cgi->param('save') ) {

        # Store settings from the form submission
        $self->store_data(
            {
                # example_setting => $cgi->param('example_setting'),
            }
        );
        $self->go_home();
        return;
    }

    # Render the configuration form with current values
    my $template = $self->get_template( { file => 'configure.tt' } );
    $template->param(

        # example_setting => $self->retrieve_data('example_setting'),
    );

    return $self->output_html( $template->output );
}

=head3 api_namespace

Context: Define the API namespace for the plugin (subdomain-like component).

=over 4

=item * Parameters

C<$self>

=item * Returns

String representing the subdomain, e.g., the project part of your plugin name.

=back

=cut

sub api_namespace {
    my $self = shift;

    # This should be unique to your plugin to avoid namespace clashes.
    return 'CircFeed';
}

=head3 api_routes

This subroutine returns valid OpenAPI 2.0 paths serialized as a hash reference.

If your plugin implements API routes, the `api_routes` method should be implemented
to provide OpenAPI-compliant routes. It is a good practice to write the OpenAPI 2.0 path
specifications in JSON and store them in the plugin, then read the spec within this method.
This allows for the reuse of the OpenAPI spec in mainline Koha, making this a good
prototyping tool for developing API routes.

This subroutine depends on the C<JSON> module for decoding the JSON specification.

Context: Extend Koha REST API via plugin-defined OpenAPI 2.0 routes.

=over 4

=item *

B<Parameters>

=over 8

=item *

C<$self> - Koha::Plugin object (plugin instance)

=item *

C<$args> - HashRef containing additional arguments for route processing (optional)

=back

=item *

B<Returns>

HashRef of deserialized OpenAPI 2.0 paths

=back

=cut

sub api_routes {
    my ( $self, $args ) = @_;

    my $spec_str = $self->mbf_read('openapi.json');
    my $spec     = decode_json($spec_str);

    return $spec;
}

=head3 static_routes

This subroutine returns static API routes from a predefined JSON specification file.

It reads the JSON file, parses it, and returns the resulting data structure as a hash reference.
This method is typically used to provide static API routes that do not change dynamically and
are predefined in the plugin.

This subroutine depends on the C<JSON> module for decoding the JSON specification.

Context: Serve static files through the API without Apache changes.

=over 4

=item * Parameters

=over 8

=item * C<$self> - Koha::Plugin object (plugin instance)

=item * C<$args> - HashRef containing parameters related to route handling

=back

=item * Returns

HashRef - The parsed JSON structure representing static API routes.

=back

=cut

sub static_routes {
    my ( $self, $args ) = @_;

    my $spec_str = $self->mbf_read('staticapi.json');
    my $spec     = decode_json($spec_str);

    return $spec;
}

=head3 intranet_js

This subroutine allows the plugin to inject custom JavaScript into the staff intranet interface.

You can return a string of JavaScript wrapped in C<< <script> >> tags if necessary, or include external JavaScript files by constructing the appropriate HTML. This gives the plugin flexibility to include inline JavaScript or reference external JavaScript resources as needed.

Context: Global JS/HTML injection for the staff interface.

=over 4

=item *

B<Parameters>

=over 8

=item *

C<$self> - Koha::Plugin object (plugin instance)

=back

=item *

B<Returns>

String - HTML/JS to include in intranet

=back

=cut

sub intranet_js {
    my $self = shift;

    return <<~'JS';
    <link rel="stylesheet" href="/api/v1/contrib/CircFeed/static/CircFeed.css">
    <script type="module">
      const islandsSrc = document.querySelector("script[src*='islands.esm']")?.src;
      if (islandsSrc) {
        const { registerIsland, hydrate } = await import(islandsSrc);

        registerIsland("plugin-circ-feed", {
          importFn: async () => {
            const mod = await import("/api/v1/contrib/CircFeed/static/CircFeed.js");
            return mod.default;
          },
          config: { stores: [] },
        });

        const main = document.querySelector(".main.container-fluid");
        if (main) {
          const el = document.createElement("plugin-circ-feed");
          el.setAttribute("api-base", "/api/v1/contrib/CircFeed");
          main.prepend(el);
        }

        hydrate();
      }
    </script>
    JS
}

=head3 after_circ_action

Context: Called at the end of AddRenewal, AddIssue and AddReturn.

=over 4

=item * Parameters

=over 8

=item * C<$self>

=item * C<$params> - HashRef with keys: C<action>, C<payload> (HashRef with context-specific data)

=back

=item * Returns

Void

=back

=cut

sub after_circ_action {
    my ( $self, $params ) = @_;

    my $action   = $params->{action} // return;
    my $checkout = $params->{payload}{checkout} // return;

    my $dbh = C4::Context->dbh;

    # Gather event details
    my $borrowernumber = $checkout->borrowernumber;
    my $itemnumber     = $checkout->itemnumber;

    my $patron = eval { Koha::Patrons->find($borrowernumber) };
    my $item   = eval { Koha::Items->find($itemnumber) };

    my $patron_name = $patron
        ? join( q{ }, grep { $_ } $patron->firstname, $patron->surname )
        : 'Unknown';
    my $title   = $item ? ( $item->biblio->title // 'Unknown' ) : 'Unknown';
    my $barcode = $item ? ( $item->barcode // q{} ) : q{};
    my $library = $checkout->branchcode // q{};

    $dbh->do(
        q{INSERT INTO plugin_circ_feed_events
          (event_type, borrowernumber, itemnumber, barcode, title, patron_name, library)
          VALUES (?, ?, ?, ?, ?, ?, ?)},
        undef,
        $action, $borrowernumber, $itemnumber, $barcode, $title, $patron_name, $library,
    );

    # Keep table manageable — purge events older than 24 hours
    $dbh->do(q{DELETE FROM plugin_circ_feed_events WHERE created_at < NOW() - INTERVAL 1 DAY});

    return;
}

1;
