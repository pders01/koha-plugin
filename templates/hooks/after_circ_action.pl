=pod


=head3 after_circ_action

Context: Called at the end of AddRenewal, AddIssue and AddReturn.

=over 4

=item * Parameters

C<$self>, C<$action>, C<$context>

=item * Returns

Void

=back

=cut

sub after_circ_action {
    my ( $self, $action, $context ) = @_;
    return;
}


