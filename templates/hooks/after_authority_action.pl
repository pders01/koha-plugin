=pod


=head3 after_authority_action

Context: Called after AddAuthority, ModAuthority, or DelAuthority.

=over 4

=item * Parameters

C<$self>, C<$action>, C<$authority>

=item * Returns

Void

=back

=cut

sub after_authority_action {
    my ( $self, $action, $authority ) = @_;
    return;
}


