=head3 after_item_action

Context: Post-CRUD item hook. Use to trigger side-effects (async recommended).

=over 4

=item * Parameters

=over 8

=item * C<$self>

=item * C<$params> - HashRef with keys: C<action> ('create'|'update'|'delete'), C<payload> (HashRef with C<item>)

=back

=item * Returns

Void

=back

=cut

sub after_item_action {
    my ( $self, $params ) = @_;

    # my $action = $params->{action};
    # my $item   = $params->{payload}{item};

    return;
}
