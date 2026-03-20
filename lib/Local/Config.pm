package Local::Config;

use strict;
use warnings;

use Carp       qw( croak );
use JSON       qw( decode_json encode_json );
use YAML::Tiny ();

use Local::Util qw( l json_encoder );

use Exporter 'import';

our @EXPORT_OK = qw(
    load_config
    save_config
    find_config
    migrate_from_dotenv
    config_to_env
);

my @CONFIG_NAMES = qw(
    koha-plugin.yml
    koha-plugin.yaml
    koha-plugin.json
);

my @FIELDS = qw(
    name
    author
    version
    description
    release_filename
    static_dir_name
    date_authored
    date_updated
    minimum_version
    maximum_version
);

sub find_config {
    for my $name (@CONFIG_NAMES) {
        return $name if -e $name;
    }
    return;
}

sub load_config {
    my ($path) = @_;
    $path //= find_config();

    if ( !$path || !-e $path ) {
        return;
    }

    if ( $path =~ /[.]ya?ml$/smx ) {
        return _load_yaml($path);
    }
    elsif ( $path =~ /[.]json$/smx ) {
        return _load_json($path);
    }

    l( 'error', "unsupported config format: $path" );
    return;
}

sub save_config {
    my ( $data, $path ) = @_;
    $path //= find_config();

    if ( !$path ) {
        l( 'error', 'no config file found to save to' );
        return;
    }

    if ( $path =~ /[.]ya?ml$/smx ) {
        return _save_yaml( $data, $path );
    }
    elsif ( $path =~ /[.]json$/smx ) {
        return _save_json( $data, $path );
    }

    l( 'error', "unsupported config format: $path" );
    return;
}

sub config_to_env {
    my ($config) = @_;
    return unless $config;

    for my $field (@FIELDS) {
        my $env_key = 'PLUGIN_' . uc $field;
        my $value   = $config->{$field} // q{};
        $value =~ s/[\x00\n\r]//g;    # Strip null bytes and newlines
        $ENV{$env_key} = $value;
    }
    return 1;
}

sub migrate_from_dotenv {
    my ($target_format) = @_;
    $target_format //= 'yml';

    if ( !-e '.env' ) {
        l( 'error', '.env file not found' );
        return;
    }

    my $config = _parse_dotenv('.env');

    my $target = "koha-plugin.$target_format";
    if ( -e $target ) {
        l( 'error', "$target already exists, aborting migration" );
        return;
    }

    save_config( $config, $target );
    rename '.env', '.env.bak' or l( 'warning', "could not rename .env to .env.bak: $!" );
    l( 'info', "migrated .env to $target (old .env saved as .env.bak)" );

    return $target;
}

# --- Private ---

sub _parse_dotenv {
    my ($path) = @_;
    my %config;

    open my $fh, '<', $path or croak "Cannot open $path: $!";
    while ( my $line = <$fh> ) {
        chomp $line;
        next if $line =~ /^\s*#/;
        next if $line =~ /^\s*$/;
        if ( $line =~ /^\s*PLUGIN_(\w+)=(.*)$/smx ) {
            my ( $key, $value ) = ( lc $1, $2 );

            # Strip surrounding quotes and dangerous characters
            $value =~ s/^["']|["']$//g;
            $value =~ s/[\x00\n\r]//g;
            $config{$key} = $value;
        }
    }
    close $fh;

    # Normalize legacy key names
    if ( exists $config{static_dirs} ) {
        $config{static_dir_name} //= delete $config{static_dirs};
    }
    if ( exists $config{min_koha_version} ) {
        $config{minimum_version} //= delete $config{min_koha_version};
    }
    if ( exists $config{max_koha_version} ) {
        $config{maximum_version} //= delete $config{max_koha_version};
    }

    return \%config;
}

sub _load_yaml {
    my ($path) = @_;
    my $yaml = YAML::Tiny->read($path);
    if ( !$yaml ) {
        l( 'error', "failed to read $path: " . YAML::Tiny->errstr );
        return;
    }
    return $yaml->[0];
}

sub _save_yaml {
    my ( $data, $path ) = @_;
    my $yaml = YAML::Tiny->new($data);
    if ( !$yaml->write($path) ) {
        l( 'error', "failed to write $path: " . YAML::Tiny->errstr );
        return;
    }
    return 1;
}

sub _load_json {
    my ($path) = @_;
    open my $fh, '<', $path or croak "Cannot open $path: $!";
    my $content = do { local $/; <$fh> };
    close $fh;
    return decode_json($content);
}

sub _save_json {
    my ( $data, $path ) = @_;
    my $j = json_encoder();
    open my $fh, '>', $path or croak "Cannot open $path for writing: $!";
    print {$fh} $j->encode($data) or croak "Cannot write to $path: $!";
    close $fh;
    return 1;
}

1;
