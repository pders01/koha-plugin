=head3 ill_availability_services

Context: Intercept ILL request creation; search and return potential relevant
items/services from installed availability providers.

=over 4

=item * Parameters

C<$self>, C<$metadata>

=item * Returns

ArrayRef of availability entries

=back

=cut

sub ill_availability_services {
    my ( $self, $metadata ) = @_;

    return [];
}


