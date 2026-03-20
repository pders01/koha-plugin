=head3 after_account_action

Context: Called after account-related actions are performed.

=over 4

=item * Parameters

C<$self>, C<$action>, C<$account_context>

=item * Returns

Void

=back

=cut

sub after_account_action {
    my ( $self, $action, $account_context ) = @_;
    return;
}


