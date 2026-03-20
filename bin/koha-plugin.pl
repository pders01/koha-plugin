#!/usr/bin/env perl
use strict;
use warnings;
use feature 'say';
use File::Basename qw( dirname );
use File::Path     qw( remove_tree );

# In dev mode, add lib paths; in PAR mode, modules are bundled
BEGIN {
    unless ( $ENV{PAR_TEMP} ) {
        my $root = dirname( dirname(__FILE__) );
        require lib;
        lib->import("$root/lib");

        # Support carton (local/lib/perl5), but don't require it.
        # Users can also set PERL5LIB, use local::lib, or install deps globally.
        my $carton_lib = "$root/local/lib/perl5";
        lib->import($carton_lib) if -d $carton_lib;

        # Set project root so asset_dir() resolves templates and scripts
        $ENV{KOHA_PLUGIN_ROOT} //= $root;
    }
}

use Local::Command::Init      qw( run_init );
use Local::Command::Add       qw( run_add );
use Local::Command::Check     qw( run_check );
use Local::Command::Increment qw( run_increment );
use Local::Config             qw( load_config find_config config_to_env migrate_from_dotenv );
use Local::Util               qw( l asset_dir );

my $VERSION = 'v1.1.0';

# Load config: YAML/JSON config file, .env fallback, PAR-bundled last
_load_config();

my $command = shift @ARGV // '';

my %COMMANDS = (
    'version'     => \&_cmd_version,
    'help'        => \&_cmd_help,
    'clean'       => \&_cmd_clean,
    'init'        => \&_cmd_init,
    'add'         => \&_cmd_add,
    'increment'   => \&_cmd_increment,
    'package'     => \&_cmd_package,
    'staticapi'   => \&_cmd_staticapi,
    'ktd'         => \&_cmd_ktd,
    'update-meta' => \&_cmd_update_meta,
    'migrate'     => \&_cmd_migrate,
    'check'       => \&_cmd_check,
);

if ( $command eq '' || $command eq '--help' || $command eq '-h' ) {
    _cmd_help();
}
elsif ( $command eq '--version' || $command eq '-v' ) {
    _cmd_version();
}
elsif ( my $handler = $COMMANDS{$command} ) {
    $handler->(@ARGV);
}
else {
    say "Unknown command: $command";
    _cmd_help();
    exit 1;
}

# --- Commands ---

sub _cmd_version {
    say "koha-plugin $VERSION";
    exit;
}

sub _cmd_help {
    print <<"USAGE";
koha-plugin $VERSION - Koha Plugin Builder

Usage: koha-plugin <command> [arguments]

Commands:
    init                        Initialize a new Koha plugin (interactive)
    add <component>             Add a component to your plugin:
        action                    UI page template (admin, configure, report, tool)
        node                      Node.js project (package.json + src/)
        api-route                 OpenAPI route + controller stub
        migration                 Numbered SQL migration file
        hook                      Add a hook method to an existing plugin module
        background-job            Background job class + registration
        vue                       Vue island component with vite build
    increment [options]         Increment version (patch, minor, major)
    package                     Create a .kpz file
    clean                       Remove Koha/ directory and package.json
    staticapi                   Update staticapi.json
    ktd [container] [binary]    Deploy to KTD container
    update-meta                 Update the koha-plugin repository
    migrate [format]            Migrate .env to config file (yml or json; default: yml)
    check                       Validate plugin for common issues

Options:
    --version, -v               Show version
    --help, -h                  Show this help

Increment options:
    --type TYPE                 Version part to increment (patch, minor, major; default: patch)
    --times N                   Number of increments (default: 1)
USAGE
    exit;
}

sub _cmd_clean {
    l( 'info', 'cleaning...' );
    if ( -d 'Koha' ) {
        remove_tree('Koha');
    }
    if ( -e 'package.json' ) {
        unlink 'package.json';
    }
    l( 'info', 'clean completed' );
}

sub _cmd_init {
    require Getopt::Long;
    my $hooks;
    Getopt::Long::GetOptionsFromArray( \@_, 'hooks=s' => \$hooks );
    run_init( $hooks ? ( hooks => $hooks ) : () );
}

sub _cmd_add {
    my $component = shift;
    if ( !$component ) {
        l( 'error', 'usage: koha-plugin add <component> [options]' );
        l( 'info',  '  action     - UI page template (--type admin|configure|report|tool)' );
        l( 'info',  '  node       - Node.js project (package.json + src/)' );
        l( 'info',  '  api-route  - OpenAPI route (--path, --method, --operation, --controller, --permission)' );
        l( 'info',  '  migration  - SQL migration file (--description)' );
        l( 'info',  '  hook       - Add hook to existing plugin (--type <hook_name>)' );
        l( 'info',  '  background-job - Job class + registration (--type <job_name>)' );
        l( 'info',  '  vue            - Vue island with vite (--name <Component> --tag <tag-name>)' );
        exit 1;
    }

    # Parse component-specific options
    require Getopt::Long;
    my %opts;
    Getopt::Long::GetOptionsFromArray(
        \@_,
        'type=s'        => \$opts{type},
        'path=s'        => \$opts{path},
        'method=s'      => \$opts{method},
        'operation=s'   => \$opts{operation},
        'controller=s'  => \$opts{controller},
        'permission=s'  => \$opts{permission},
        'description=s' => \$opts{description},
        'name=s'        => \$opts{name},
        'tag=s'         => \$opts{tag},
        'class=s'       => \$opts{class},
    );

    # Remove undef entries so handlers can distinguish "not provided" from "empty"
    delete $opts{$_} for grep { !defined $opts{$_} } keys %opts;

    run_add( $component, %opts );
}

sub _cmd_increment {

    # Parse increment-specific options from remaining @ARGV
    require Getopt::Long;
    my $type  = 'patch';
    my $times = 1;
    Getopt::Long::GetOptionsFromArray(
        \@_,
        'type=s'  => \$type,
        'times=i' => \$times,
    );

    run_increment(
        version => $ENV{PLUGIN_VERSION},
        name    => $ENV{PLUGIN_NAME},
        type    => $type,
        times   => $times,
    );
}

sub _cmd_package {
    l( 'info', 'packaging plugin...' );
    _run_script( 'package.sh', $ENV{PLUGIN_NAME}, $ENV{PLUGIN_RELEASE_FILENAME}, $ENV{PLUGIN_VERSION} );
    l( 'info', 'plugin packaged' );
}

sub _cmd_staticapi {
    l( 'info', 'updating static API...' );
    _run_script( 'staticapi.sh', $ENV{PLUGIN_NAME}, $ENV{PLUGIN_STATIC_DIR_NAME} );
    l( 'info', 'static API updated' );
}

sub _cmd_ktd {
    my ( $container, $binary ) = @_;
    $container //= 'kohadev-koha-1';
    $binary    //= 'docker';

    my %allowed_binaries = map { $_ => 1 } qw( docker podman nerdctl );
    if ( !$allowed_binaries{$binary} ) {
        l( 'error', "binary must be one of: docker, podman, nerdctl (got: $binary)" );
        return;
    }

    l( 'info', "deploying to ktd container=$container binary=$binary" );
    _run_script( 'ktd.sh', $container, $binary );
    l( 'info', 'ktd deployment completed' );
}

sub _cmd_update_meta {
    l( 'info', 'updating repository...' );
    _run_script('update-meta.sh');
    l( 'info', 'repository updated' );
}

sub _cmd_migrate {
    my ($format) = @_;
    $format //= 'yml';

    if ( $format !~ /^(ya?ml|json)$/smx ) {
        say "Unsupported format: $format (use yml or json)";
        exit 1;
    }

    my $result = migrate_from_dotenv($format);
    if ($result) {
        say "Migration complete: $result";
    }
}

sub _cmd_check {
    my $ok = run_check();
    exit( $ok ? 0 : 1 );
}

# --- Helpers ---

sub _load_config {

    # 1. Try config file (koha-plugin.yml, koha-plugin.yaml, koha-plugin.json)
    my $config = load_config();
    if ($config) {
        config_to_env($config);
        return;
    }

    # 2. Fall back to legacy .env
    if ( -e '.env' ) {
        _load_dotenv_legacy('.env');
        return;
    }

    # 3. In PAR mode, try bundled .env as last resort
    my $par_env = asset_dir('.env');
    if ( $par_env ne '.env' && -e $par_env ) {
        _load_dotenv_legacy($par_env);
    }

    return;
}

sub _load_dotenv_legacy {
    my ($env_file) = @_;

    open my $fh, '<', $env_file or die "Cannot open $env_file: $!";
    while ( my $line = <$fh> ) {
        chomp $line;
        next if $line =~ /^\s*#/;
        next if $line =~ /^\s*$/;
        if ( $line =~ /^\s*(\w+)=(.*)$/ ) {
            my $value = $2;
            $value =~ s/[\x00\n\r]//g;    # Strip null bytes and newlines
            $ENV{$1} = $value;
        }
    }
    close $fh;
    return;
}

sub _run_script {
    my ( $name, @args ) = @_;
    my $script = asset_dir("scripts/$name");
    if ( !-e $script ) {
        die "Script not found: $script\n";
    }

    # Export root so shell scripts can find templates and other assets
    local $ENV{KOHA_PLUGIN_ROOT} = asset_dir();
    my @cmd = ( $script, @args );
    system(@cmd) == 0 or die "Command failed: @cmd\n";
    return;
}
