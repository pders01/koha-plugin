=head3 ill_backend

Context: Identify this plugin as an ILL backend by returning a backend name.
Backend class must implement required ILL backend methods.

=over 4

=item * Parameters

C<$self>

=item * Returns

String backend identifier

=back

=cut

sub ill_backend {
    my ($self) = @_;
    return '[% project %]';
}


