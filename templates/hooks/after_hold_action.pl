=pod


=head3 after_hold_action

Context: Triggered on hold status changes; C<$action> indicates context (fill,
cancel, suspend, resume, transfer, waiting, processing).

=over 4

=item * Parameters

C<$self>, C<$action>, C<$hold>

=item * Returns

Void

=back

=cut

sub after_hold_action {
    my ( $self, $action, $hold ) = @_;
    return;
}


