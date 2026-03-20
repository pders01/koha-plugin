=head3 before_orderline_create

Context: Prior to creating an orderline from a MARC record file.

=over 4

=item * Parameters

C<$self>, C<$marc_record>, C<$context>

=item * Returns

Implementation-defined

=back

=cut

sub before_orderline_create {
    my ( $self, $marc, $context ) = @_;
    return;
}


