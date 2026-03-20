#!/usr/bin/env perl
use strict;
use warnings;
use feature 'say';
use File::Basename qw( dirname );
use File::Path     qw( remove_tree );

# In dev mode, add local lib paths; in PAR mode, modules are bundled
BEGIN {
    unless ( $ENV{PAR_TEMP} ) {
        my $root = dirname( dirname(__FILE__) );
        require lib;
        lib->import("$root/lib");
        lib->import("$root/local/lib/perl5");
    }
}

use Local::Command::Init      qw( run_init );
use Local::Command::Add       qw( run_add );
use Local::Command::Increment qw( run_increment );
use Local::Util               qw( asset_dir );

my $VERSION = 'v1.0.0';

# Load .env: CWD first, then PAR-bundled fallback
_load_env_file();

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
    init                        Initialize a new Koha plugin
    add <component>             Add a component (action, node)
    increment [options]         Increment version (patch, minor, major)
    package                     Create a .kpz file
    clean                       Remove Koha/ directory and package.json
    staticapi                   Update staticapi.json
    ktd [container] [binary]    Deploy to KTD container
    update-meta                 Update the koha-plugin repository

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
    say 'Cleaning...';
    if ( -d 'Koha' ) {
        remove_tree('Koha');
    }
    if ( -e 'package.json' ) {
        unlink 'package.json';
    }
    say 'Clean completed successfully';
}

sub _cmd_init {
    say 'Initializing new Koha plugin...';
    run_init();
    say 'Initialization completed successfully';
}

sub _cmd_add {
    my ($component) = @_;
    if ( !$component ) {
        say 'Usage: koha-plugin add <component>';
        say 'Components: action, node';
        exit 1;
    }
    say "Adding component: $component";
    run_add($component);
    say "Component $component added successfully";
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

    say "Incrementing version ($type) by $times...";
    run_increment(
        version => $ENV{PLUGIN_VERSION},
        name    => $ENV{PLUGIN_NAME},
        type    => $type,
        times   => $times,
    );
    say 'Version incremented successfully';
}

sub _cmd_package {
    say 'Packaging plugin...';
    _run_script( 'package.sh', $ENV{PLUGIN_NAME}, $ENV{PLUGIN_RELEASE_FILENAME}, $ENV{PLUGIN_VERSION} );
    say 'Plugin packaged successfully';
}

sub _cmd_staticapi {
    say 'Updating static API...';
    _run_script( 'staticapi.sh', $ENV{PLUGIN_NAME}, $ENV{PLUGIN_STATIC_DIR_NAME} );
    say 'Static API updated successfully';
}

sub _cmd_ktd {
    my ( $container, $binary ) = @_;
    $container //= 'kohadev-koha-1';
    $binary    //= 'docker';
    say "Running ktd with container=$container, binary=$binary";
    _run_script( 'ktd.sh', $container, $binary );
    say 'KTD completed successfully';
}

sub _cmd_update_meta {
    say 'Updating metadata...';
    _run_script('update-meta.sh');
    say 'Metadata updated successfully';
}

# --- Helpers ---

sub _load_env_file {
    # Prefer CWD .env, fall back to PAR-bundled .env
    my $env_file = -e '.env' ? '.env' : asset_dir('.env');
    return unless -e $env_file;

    open my $fh, '<', $env_file or die "Cannot open $env_file: $!";
    while ( my $line = <$fh> ) {
        chomp $line;
        next if $line =~ /^\s*#/;
        next if $line =~ /^\s*$/;
        if ( $line =~ /^\s*(\w+)=(.*)$/ ) {
            $ENV{$1} = $2;
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
    my @cmd = ( $script, @args );
    system(@cmd) == 0 or die "Command failed: @cmd\n";
    return;
}
