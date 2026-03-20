=head3 check_password

Context: Validate password strength when a password is created or updated.

=over 4

=item * Parameters

=over 8

=item * C<$self> - Plugin instance

=item * C<$password> - Plain text password

=item * C<$borrowernumber> - Patron internal id

=back

=item * Returns

Undefined for OK; return a message or structure to indicate failure.

=back

=cut

sub check_password {
    my ( $self, $password, $borrowernumber ) = @_;

    return;
}


