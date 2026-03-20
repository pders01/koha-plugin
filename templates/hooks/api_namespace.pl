=head3 api_namespace

Context: Define the API namespace for the plugin (subdomain-like component).

=over 4

=item * Parameters

C<$self>

=item * Returns

String representing the subdomain, e.g., the project part of your plugin name.

=back

=cut

sub api_namespace {
    my $self = shift;

    # This should be unique to your plugin to avoid namespace clashes.
    return '[% project %]';
}

