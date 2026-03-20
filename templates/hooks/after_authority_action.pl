=head3 after_authority_action

Context: Called after AddAuthority, ModAuthority, or DelAuthority.

=over 4

=item * Parameters

=over 8

=item * C<$self>

=item * C<$params> - HashRef with keys: C<action>, C<payload> (HashRef with C<authority>)

=back

=item * Returns

Void

=back

=cut

sub after_authority_action {
    my ( $self, $params ) = @_;

    # my $action    = $params->{action};
    # my $authority = $params->{payload}{authority};

    return;
}
