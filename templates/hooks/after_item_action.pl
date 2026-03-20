=head3 after_item_action

Context: Post-CRUD item hook. Use to trigger side-effects (async recommended).

=over 4

=item * Parameters

C<$self>, C<$action>, C<$item>

=item * Returns

Void

=back

=cut

sub after_item_action {
    my ( $self, $action, $item ) = @_;

    return;
}


