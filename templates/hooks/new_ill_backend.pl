=head3 new_ill_backend

Context: Return the ILL backend class to use. Can be the plugin itself or a
class in the plugin namespace.

=over 4

=item * Parameters

C<$self>

=item * Returns

String fully qualified class name

=back

=cut

sub new_ill_backend {
    my ($self) = @_;
    return ref($self);
}


