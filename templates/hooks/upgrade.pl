=head3 upgrade

This subroutine is triggered when a newer version of the plugin is installed over an existing older version.

It is typically used to handle any data migration, cleanup, or updates that need to occur when the plugin is upgraded. The method can store relevant upgrade data, such as the timestamp of the last upgrade.

Context: Run on plugin upgrade to handle migrations or data changes.

=over 4

=item *

B<Parameters>

=over 8

=item *

C<$self> - Koha::Plugin object (plugin instance)

=item *

C<$args> - HashRef containing optional parameters related to the upgrade process

=back

=item *

B<Returns>

Boolean - true if the upgrade succeeded

=back

=cut

sub upgrade {
    my ( $self, $args ) = @_;

    # Option 1: Version-conditional inline DDL
    # my $dt = dt_from_string();
    # if ( $self->retrieve_data('__version__') lt '1.1.0' ) {
    #     my $dbh = C4::Context->dbh;
    #     $dbh->do(q{ ALTER TABLE plugin_example ADD COLUMN status VARCHAR(50) });
    #     $self->store_data({ '__version__' => '1.1.0' });
    # }

    # Option 2: Use MigrationHelper with SQL files in migrations/
    # See: github.com/LMSCloudPaulD/koha-plugin-lmscloud-util
    # Create migration files with: koha-plugin add migration
    #
    # use Koha::Plugin::Com::LMSCloud::Util::MigrationHelper;
    # my $helper = Koha::Plugin::Com::LMSCloud::Util::MigrationHelper->new({
    #     bundle_path        => $self->bundle_path,
    #     table_name_mappings => { my_table => 'plugin_mytable' },
    # });
    # return $helper->upgrade({ plugin => $self });

    return 1;
}
