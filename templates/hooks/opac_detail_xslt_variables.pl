=head3 opac_detail_xslt_variables

This subroutine is a plugin hook used to inject custom variables into the OPAC detail XSLT.

Plugins can use this method to provide additional variables that can be utilized within
the OPAC detail XSLT for dynamic content generation. The method should return a hash reference
with key-value pairs, where the key is the variable name and the value is the content.

Context: Merge additional variables into XSLT context for OPAC detail.

=over 4

=item *

B<Parameters>

=over 8

=item *

C<$self> - Koha::Plugin object (plugin instance)

=item *

C<$params> - HashRef containing additional parameters for variable injection

=back

=item *

B<Returns>

HashRef - variables to merge into the XSLT context

=back

=cut

sub opac_detail_xslt_variables {
    my ( $self, $params ) = @_;

    # my $biblionumber = $params->{biblionumber};
    # return { MY_VAR => 'value' };

    return {};
}

