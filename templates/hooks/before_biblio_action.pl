=pod


=head3 before_biblio_action

Context: Pre-CRUD biblio hook. Return a value to influence or block the operation.

=over 4

=item * Parameters

C<$self>, C<$action>, C<$biblio>

=item * Returns

Implementation-defined (e.g., undef for OK; a message/structure to block).

=back

=cut

sub before_biblio_action {
    my ( $self, $action, $biblio ) = @_;

    return;
}


