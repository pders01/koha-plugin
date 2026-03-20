package Local::Util;

use strict;
use warnings;

use Carp            qw( croak );
use Term::ANSIColor qw( colored );

use Exporter 'import';

our @EXPORT_OK = qw( l );

## no critic qw(ValuesAndExpressions::RequireInterpolationOfMetachars)

sub l {
    my ( $type, $message ) = @_;

    print {
        info    => colored( "$message\n",          'bright_cyan' ),
        warning => colored( "warning: $message\n", 'bright_yellow' ),
        error   => colored( "error: $message\n",   'bright_red' ),
    }->{ $type // 'info' }
        or croak;

    return 1;
}

1;
