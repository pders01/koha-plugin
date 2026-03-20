
=pod


=head3 api_namespace

Context: Define the API namespace for the plugin (subdomain-like component).

=over 4

=item * Parameters

C<$self>

=item * Returns

String representing the subdomain (C<[a]>), e.g., for C<[c].[b].[a]>.

=back

=cut

sub api_namespace {
    my $self = shift;

    # [a] here represents the <project> part of your name, but you can use
    # whatever you want here as long as it doesn't clash with other plugins.
    return '[% a %]';
}

