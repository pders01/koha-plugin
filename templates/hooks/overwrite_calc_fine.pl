=head3 overwrite_calc_fine

Context: Customize calculation for graduated fines.

=over 4

=item * Parameters

C<$self>, C<$context>

=item * Returns

Numeric fine value or undef to fallback to default

=back

=cut

sub overwrite_calc_fine {
    my ( $self, $context ) = @_;
    return;
}


