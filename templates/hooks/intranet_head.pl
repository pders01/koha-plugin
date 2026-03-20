=head3 intranet_head

This subroutine allows the plugin to add custom CSS to the staff intranet interface.

You can return a string of CSS here, wrapped in C<< <style> >> tags if needed, or include external CSS files by constructing the appropriate HTML. This flexibility allows plugins to style the intranet interface in various ways, including injecting inline styles or linking to external resources.

Context: Global CSS/HTML injection into intranet head.

=over 4

=item *

B<Parameters>

=over 8

=item *

C<$self> - Koha::Plugin object (plugin instance)

=back

=item *

B<Returns>

String - HTML/CSS/JS to include in intranet head

=back

=cut

sub intranet_head {
    my $self = shift;

    return <<~'CSS';
[%- IF static %]
    <link rel="stylesheet" href="/api/v1/contrib/[% project %]/static/main.css">
[%- END %]
    CSS
}
