=head3 opac_js

This subroutine allows the plugin to inject custom JavaScript into the OPAC.

You can return a string of JavaScript wrapped in C<< <script> >> tags if necessary, or include external JavaScript files by constructing the appropriate HTML. This gives the plugin flexibility to include inline JavaScript or reference external JavaScript resources as needed.

Context: Global JS/HTML injection into OPAC body.

=over 4

=item *

B<Parameters>

=over 8

=item *

C<$self> - Koha::Plugin object (plugin instance)

=back

=item *

B<Returns>

String - HTML/JS to include in OPAC

=back

=cut

sub opac_js {
    my $self = shift;

    return <<~'JS';
[%- IF static %]
    <script src="/api/v1/contrib/[% project %]/static/main.js"></script>
[%- END %]
    JS
}
