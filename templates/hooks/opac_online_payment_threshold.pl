=head3 opac_online_payment_threshold

Context: Minimum allowed OPAC payment. Deny payments below this number.

=over 4

=item * Parameters

C<$self>

=item * Returns

Numeric threshold (e.g., 0, 1.00); can vary by environment/library.

=back

=cut

sub opac_online_payment_threshold {
    my ($self) = @_;
    return 0;
}


