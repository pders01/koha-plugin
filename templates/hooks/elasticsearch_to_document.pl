=head3 elasticsearch_to_document

Context: Modify the document sent to Elasticsearch post marc_records_to_documents().
Use to add fields, sanitize, or normalize data.

=over 4

=item * Parameters

C<$self>, C<$document>, C<$context>

=item * Returns

Modified document HashRef (or undef for no change)

=back

=cut

sub elasticsearch_to_document {
    my ( $self, $document, $context ) = @_;
    return $document;
}


