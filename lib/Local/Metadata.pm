package Local::Metadata;

use strict;
use warnings;

use DateTime ();

use Local::Util qw( l );

use Exporter 'import';

our @EXPORT_OK = qw(
    metadata_from_env
    validate_metadata
    stringify_metadata
);

## no critic qw(ValuesAndExpressions::RequireInterpolationOfMetachars)

my @FIELDS = qw(
    author
    date_authored
    date_updated
    description
    maximum_version
    minimum_version
    name
    release_filename
    static_dir_name
    version
);

sub metadata_from_env {
    my %metadata;
    for my $field (@FIELDS) {
        my $env_key = 'PLUGIN_' . uc $field;
        $metadata{$field} = $ENV{$env_key} // undef;
    }
    return \%metadata;
}

sub validate_metadata {
    my ($m) = @_;

    if ( !$m->{author} ) {
        l( 'warning', 'author is unset' );
    }

    if ( !$m->{date_authored} || $m->{date_authored} eq 'today' ) {
        l( 'warning', q{date_authored is set to default: today; rewriting to iso format} );
        $m->{date_authored} = DateTime->now->ymd;
    }

    if ( !$m->{date_updated} || $m->{date_updated} eq 'today' ) {
        l( 'warning', q{date_updated is set to default: today; rewriting to iso format} );
        $m->{date_updated} = DateTime->now->ymd;
    }

    if ( !$m->{description} ) {
        l( 'warning', 'description is unset' );
    }

    if ( !$m->{maximum_version} ) {
        l( 'warning', 'maximum_version is unset' );
    }

    if ( !$m->{minimum_version} ) {
        l( 'warning', 'minimum_version is unset' );
    }

    if ( !$m->{name} ) {
        l( 'error', 'name is unset (required), use format: Koha::Plugin::<TLD>::<ORG>::<PROJECT>' );
        return;
    }

    my @name_parts = split /::/smx, $m->{name};
    if ( @name_parts != 5 ) {
        l( 'error', 'name validation failed, use format: Koha::Plugin::<TLD>::<ORG>::<PROJECT>' );
        return;
    }

    # Each component must be alphanumeric to prevent path traversal
    for my $part (@name_parts) {
        if ( $part !~ /^[A-Za-z][A-Za-z0-9]*$/smx ) {
            l( 'error', "name component '$part' must be alphanumeric; no dots, slashes, or special characters" );
            return;
        }
    }

    if ( !$m->{release_filename} ) {
        l( 'warning', 'release_filename is unset' );
    }

    if ( !$m->{static_dir_name} ) {
        l( 'warning', 'static_dir_name is unset' );
    }

    if ( !$m->{version} ) {
        l( 'warning', 'version is unset' );
    }

    return 1;
}

sub stringify_metadata {
    my ($m) = @_;

    # Emit each field as a safe Perl hash entry.
    # Values are single-quoted with embedded single quotes escaped,
    # preventing code injection through crafted metadata values.
    my @lines;
    for my $key ( sort keys %{$m} ) {
        my $value = $m->{$key} // q{};
        $value =~ s/'/\\'/g;
        push @lines, sprintf q{    '%s' => '%s',}, $key, $value;
    }

    return join "\n", @lines;
}

1;
