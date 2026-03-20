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
        $self->store_data({
            # example_setting => $cgi->param('example_setting'),
        });
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
