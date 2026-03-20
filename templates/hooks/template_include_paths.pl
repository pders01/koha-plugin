=head3 template_include_paths

Context: Add Template::Toolkit INCLUDE_PATH entries for plugin templates.

=over 4

=item * Parameters

C<$self>

=item * Returns

ArrayRef of paths to include

=back

=cut

sub template_include_paths {
    my ($self) = @_;
    return [];
}


