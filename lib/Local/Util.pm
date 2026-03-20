package Local::Util;

use strict;
use warnings;

use Carp            qw( croak );
use File::Spec      ();
use JSON            qw( );
use Term::ANSIColor qw( colored );

use Exporter 'import';

our @EXPORT_OK = qw( l asset_dir resolve json_encoder );

## no critic qw(ValuesAndExpressions::RequireInterpolationOfMetachars)

sub l {
    my ( $type, $message ) = @_;
    $type //= 'info';

    my %messages = (
        info    => colored( "$message\n",          'bright_cyan' ),
        warning => colored( "warning: $message\n", 'bright_yellow' ),
        error   => colored( "error: $message\n",   'bright_red' ),
    );

    my $fh = ( $type eq 'info' ) ? *STDOUT : *STDERR;
    print {$fh} $messages{$type} or croak;

    return 1;
}

sub asset_dir {
    my ($subdir) = @_;

    my $base
        = $ENV{PAR_TEMP}         ? File::Spec->catdir( $ENV{PAR_TEMP}, 'inc' )
        : $ENV{KOHA_PLUGIN_ROOT} ? $ENV{KOHA_PLUGIN_ROOT}
        :                          q{.};

    return defined $subdir
        ? File::Spec->catdir( $base, $subdir )
        : $base;
}

sub json_encoder {
    return JSON->new->utf8->pretty->canonical->indent_length(4)->space_before(0);
}

sub resolve {
    my ( $value, $fallback ) = @_;

    return $value if defined $value;
    return ref $fallback eq 'CODE' ? $fallback->() : $fallback;
}

1;
