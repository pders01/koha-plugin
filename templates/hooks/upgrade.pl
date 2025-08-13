
=pod

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

    return 1;
}
