#!/usr/bin/env perl
use strict;
use warnings;
use feature 'say';
use Getopt::Long qw( GetOptions );
use Pod::Usage qw( pod2usage );
use File::Path qw( remove_tree );
use File::Basename qw( dirname );
use lib dirname(dirname(__FILE__)) . '/lib';

my $VERSION = 'v1.0.0';

# Load environment variables from .env file
load_env_file();

sub load_env_file {
    my $env_file = '.env';
    if (-e $env_file) {
        open my $fh, '<', $env_file or die "Cannot open $env_file: $!";
        while (my $line = <$fh>) {
            chomp $line;
            next if $line =~ /^\s*#/;  # Skip comments
            next if $line =~ /^\s*$/;  # Skip empty lines
            if ($line =~ /^\s*(\w+)=(.*)$/) {
                $ENV{$1} = $2;
            }
        }
        close $fh;
    }
}

sub version {
    say "koha-plugin $VERSION";
    exit;
}

sub help {
    pod2usage(-verbose => 2);
    exit;
}

sub clean {
    say "Cleaning...";
    if (-d 'Koha') {
        remove_tree('Koha');
    }
    if (-e 'package.json') {
        unlink('package.json');
    }
    say "Clean completed successfully";
}

sub init {
    say "Initializing new Koha plugin...";
    system('carton exec ./scripts/init.pl') == 0 
        or die "Init failed: $!";
    say "Initialization completed successfully";
}

sub add {
    my ($component) = @_;
    unless ($component) {
        die "Component name is required for add command";
    }
    say "Adding component: $component";
    system("carton exec ./scripts/add.pl $component") == 0 
        or die "Add component failed: $!";
    say "Component $component added successfully";
}

sub increment {
    my ($type, $times) = @_;
    $type //= 'patch';
    $times //= '1';
    
    say "Incrementing version ($type) by $times...";
    system("./scripts/increment.pl --version \"$ENV{PLUGIN_VERSION}\" --name \"$ENV{PLUGIN_NAME}\" --type $type --times $times") == 0 
        or die "Increment failed: $!";
    say "Version incremented successfully";
}

sub create_package {
    say "Packaging plugin...";
    system("./scripts/package.sh \"$ENV{PLUGIN_NAME}\" \"$ENV{PLUGIN_RELEASE_FILENAME}\" \"$ENV{PLUGIN_VERSION}\"") == 0 
        or die "Package failed: $!";
    say "Plugin packaged successfully";
}

sub staticapi {
    say "Updating static API...";
    system("./scripts/staticapi.sh \"$ENV{PLUGIN_NAME}\" \"$ENV{PLUGIN_STATIC_DIR_NAME}\"") == 0 
        or die "Static API update failed: $!";
    say "Static API updated successfully";
}

sub ktd {
    my ($container, $binary) = @_;
    $container //= "kohadev-koha-1";
    $binary //= "docker";
    
    say "Running ktd with container=$container, binary=$binary";
    system("./scripts/ktd.sh $container $binary") == 0 
        or die "KTD failed: $!";
    say "KTD completed successfully";
}

sub update_meta {
    say "Updating metadata...";
    system("./scripts/update-meta.sh") == 0 
        or die "Update metadata failed: $!";
    say "Metadata updated successfully";
}

# Command line argument parsing
my $cmd_clean = 0;
my $cmd_init = 0;
my $cmd_add = '';
my $cmd_increment_type = 'patch';
my $cmd_increment_times = '1';
my $cmd_package = 0;
my $cmd_staticapi = 0;
my $cmd_ktd_container = 'kohadev-koha-1';
my $cmd_ktd_binary = 'docker';
my $cmd_update_meta = 0;

GetOptions(
    'version' => \&version,
    'help|?' => \&help,
    'clean' => \$cmd_clean,
    'init' => \$cmd_init,
    'add=s' => \$cmd_add,
    'increment:s' => \$cmd_increment_type,
    'times=i' => \$cmd_increment_times,
    'package' => \$cmd_package,
    'staticapi' => \$cmd_staticapi,
    'ktd:s' => \$cmd_ktd_container,
    'binary=s' => \$cmd_ktd_binary,
    'update-meta' => \$cmd_update_meta,
) or pod2usage(2);

# Process command line arguments or positional command
my $command = $ARGV[0] // '';

if ($cmd_clean || $command eq 'clean') {
    clean();
}
elsif ($cmd_init || $command eq 'init') {
    init();
}
elsif ($cmd_add || $command eq 'add') {
    my $component = $cmd_add || $ARGV[1] || '';
    add($component);
}
elsif ($command eq 'increment') {
    my $type = $ARGV[1] || $cmd_increment_type;
    my $times = $ARGV[2] || $cmd_increment_times;
    increment($type, $times);
}
elsif ($cmd_package || $command eq 'package') {
    create_package();
}
elsif ($cmd_staticapi || $command eq 'staticapi') {
    staticapi();
}
elsif ($command eq 'ktd') {
    my $container = $ARGV[1] || $cmd_ktd_container;
    my $binary = $ARGV[2] || $cmd_ktd_binary;
    ktd($container, $binary);
}
elsif ($cmd_update_meta || $command eq 'update-meta') {
    update_meta();
}
elsif ($command eq '') {
    # Default command: list available commands
    help();
}
else {
    say "Unknown command: $command";
    help();
}

__END__

=head1 NAME

koha-plugin.pl - Koha Plugin Builder

=head1 SYNOPSIS

koha-plugin.pl [command] [options]

Commands:
    clean           Remove Koha/ directory and package.json
    init            Initialize a new Koha plugin
    add COMPONENT   Add a component to your plugin
    increment TYPE TIMES  Increment version (patch, minor, major)
    package         Create a kpz file
    staticapi       Update staticapi.json
    ktd CONTAINER BINARY  Run ktd script
    update-meta     Update the koha-plugin repository

Options:
    --version       Show version
    --help          Show this help
    --clean         Run clean command
    --init          Run init command
    --add=COMPONENT Add specified component
    --increment=TYPE Increment version (default: patch)
    --times=N       Number of increments (default: 1)
    --package       Run package command
    --staticapi     Run staticapi command
    --ktd=CONTAINER Run ktd with container (default: kohadev-koha-1)
    --binary=BINARY Binary for ktd (default: docker)
    --update-meta   Run update-meta command

=cut