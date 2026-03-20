
=pod


=head3 configure

This subroutine provides a hook for adding a configuration interface to the plugin.

Plugins can use this method to either display a configuration page where users can adjust
settings or save the updated settings submitted via a form. The actual logic for rendering
the configuration page or storing data is flexible and up to the plugin’s needs.

Commonly, the configuration might include fields for enabling or disabling features, setting values,
and storing user-specific data.

The method is designed to be extended and adapted to various plugin requirements.

Context: Add a configuration interface for the plugin (render and/or save form data).

=over 4

=item * Parameters

=over 8

=item * C<$self> - Koha::Plugin object (plugin instance)

=item * C<$args> - HashRef of optional arguments for configuration handling

=back

=item * Returns

Void (HTML output via output_html)

=back

=cut

sub configure {
    my ( $self, $args ) = @_;

    my $template = $self->get_template( { file => 'configure.tt' } );

    return $self->output_html( $template->output );
}
