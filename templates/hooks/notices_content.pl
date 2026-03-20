=head3 notices_content

Context: Add variables to the notices context before templates are processed.
Receives the same parameters as C<GetPreparedLetter()>.

=over 4

=item * Parameters

C<$self>, C<%args> (same as GetPreparedLetter)

=item * Returns

HashRef of variables to merge into the notice context

=back

=cut

sub notices_content {
    my ( $self, %args ) = @_;
    return {};
}


