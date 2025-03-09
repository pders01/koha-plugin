#!/usr/bin/env perl
use strict;
use warnings;
use feature 'say';
use File::Spec::Functions qw( catfile );
use Cwd qw( abs_path );
use File::Path qw( make_path );

my $script_dir = abs_path(dirname($0));
my $project_dir = dirname($script_dir);
my $bin_dir = catfile($project_dir, 'bin');
my $dist_dir = catfile($project_dir, 'dist');
my $script_path = catfile($bin_dir, 'koha-plugin.pl');
my $output_path = catfile($dist_dir, 'koha-plugin');

# Create dist directory if it doesn't exist
unless (-d $dist_dir) {
    make_path($dist_dir);
}

# Build the command to run pp
my @command = (
    'pp',
    '-o', $output_path,
    # Include required modules
    '-M', 'Getopt::Long',
    '-M', 'Pod::Usage',
    '-M', 'File::Path',
    '-M', 'File::Basename',
    # Include scripts directory
    '-a', catfile($project_dir, 'scripts'),
    # Include templates directory
    '-a', catfile($project_dir, 'templates'),
    # Include lib directory
    '-a', catfile($project_dir, 'lib'),
    # Include .env file
    '-a', catfile($project_dir, '.env'),
    # Main script
    $script_path
);

say "Building binary...";
say "Command: " . join(' ', @command);

system(@command) == 0 or die "Build failed: $!";

say "Binary created at: $output_path";

# Make the binary executable
chmod 0755, $output_path;
say "Made binary executable";

sub dirname {
    my ($path) = @_;
    return File::Basename::dirname($path);
}
