=head3 auth_client_get_user

Context: Map an authenticated external user to a Koha patron or mutate patron
data based on the external identity.

=over 4

=item * Parameters

C<$self>, C<$auth_context>

=item * Returns

HashRef with mapped/modified patron data (implementation-defined)

=back

=cut

sub auth_client_get_user {
    my ( $self, $auth_context ) = @_;
    return;
}


