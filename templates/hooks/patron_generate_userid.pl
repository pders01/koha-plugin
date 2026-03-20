=head3 patron_generate_userid

Context: Generate a userid when creating patrons.

=over 4

=item * Parameters

C<$self>, C<$patron_context>

=item * Returns

String userid (or undef to skip)

=back

=cut

sub patron_generate_userid {
    my ( $self, $patron ) = @_;
    return;
}


