package Local::Metadata;

use strict;
use warnings;

use DateTime     ();
use Data::Dumper ();

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
    max_koha_version
    min_koha_version
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

    if ( !$m->{max_koha_version} ) {
        l( 'warning', 'max_koha_version is unset' );
    }

    if ( !$m->{min_koha_version} ) {
        l( 'warning', 'min_koha_version is unset' );
    }

    if ( !$m->{name} ) {
        l( 'error', 'name is unset (required), use format: Koha::Plugin::<TLD>::<ORG>::<PROJECT>' );
        return;
    }

    if ( @{ [ split /::/smx, $m->{name} ] } != 5 ) {
        l( 'error', 'name validation failed, use format: Koha::Plugin::<TLD>::<ORG>::<PROJECT>' );
        return;
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

    my $dumper = Data::Dumper->new( [$m] );
    $dumper->Terse(1);
    $dumper->Sortkeys(1);

    my $stringified = $dumper->Dump;

    # Remove the enclosing curly braces.
    $stringified =~ s/^[{]|[}]$//smxg;

    # Trim leading and trailing whitespace
    $stringified =~ s/^\s+|\s+$//smxg;

    return $stringified;
}

1;
