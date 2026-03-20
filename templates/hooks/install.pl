=head3 install

This is the 'install' method. Any database tables or other setup that should
be done when the plugin is first installed should be executed in this method.

The installation method should always return true if the installation succeeded
or false if it failed.

Context: One-time setup when the plugin is first installed.

=over 4

=item *

B<Parameters>

=over 8

=item *

C<$self> - Koha::Plugin object (plugin instance)

=item *

C<$args> - HashRef containing arguments for installation

=back

=item *

B<Returns>

Boolean (true on success, false on failure)

=back

=cut

sub install() {
    my ( $self, $args ) = @_;

    # Option 1: Inline DDL
    # my $dbh = C4::Context->dbh;
    # $dbh->do(q{
    #     CREATE TABLE IF NOT EXISTS plugin_example (
    #         id INT AUTO_INCREMENT PRIMARY KEY,
    #         name VARCHAR(255) NOT NULL
    #     ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    # });

    # Option 2: Use MigrationHelper with SQL files in migrations/
    # See: github.com/LMSCloudPaulD/koha-plugin-lmscloud-util
    # Create migration files with: koha-plugin add migration
    #
    # use Koha::Plugin::Com::LMSCloud::Util::MigrationHelper;
    # my $helper = Koha::Plugin::Com::LMSCloud::Util::MigrationHelper->new({
    #     bundle_path        => $self->bundle_path,
    #     table_name_mappings => { my_table => 'plugin_mytable' },
    # });
    # return $helper->install({ plugin => $self });

    return 1;
}
