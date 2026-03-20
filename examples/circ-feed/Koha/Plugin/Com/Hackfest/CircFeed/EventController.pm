package Koha::Plugin::Com::Hackfest::CircFeed::EventController;

use Modern::Perl;

use Mojo::Base 'Mojolicious::Controller';

use C4::Context ();
use Try::Tiny qw( catch try );

=head1 API

=head2 Methods

=head3 recent

Return the most recent circulation events as JSON.

=cut

sub recent {
    my $c = shift->openapi->valid_input or return;

    return try {
        my $dbh  = C4::Context->dbh;
        my $rows = $dbh->selectall_arrayref(
            q{SELECT id, event_type, title, patron_name, barcode, library, created_at
              FROM plugin_circ_feed_events
              ORDER BY id DESC
              LIMIT 50},
            { Slice => {} },
        );

        return $c->render(
            status  => 200,
            openapi => [ reverse @{$rows} ],
        );
    }
    catch {
        $c->unhandled_exception($_);
    };
}

1;
