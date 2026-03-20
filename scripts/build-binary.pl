#!/usr/bin/env perl
use strict;
use warnings;
use feature 'say';
use File::Basename        qw( dirname );
use File::Spec::Functions qw( catfile catdir );
use Cwd                   qw( abs_path );
use File::Path            qw( make_path );

my $script_dir  = abs_path( dirname($0) );
my $project_dir = dirname($script_dir);
my $bin_dir     = catdir( $project_dir, 'bin' );
my $dist_dir    = catdir( $project_dir, 'dist' );
my $local_bin   = catdir( $project_dir, 'local', 'bin' );
my $script_path = catfile( $bin_dir, 'koha-plugin.pl' );
my $output_path = catfile( $dist_dir, 'koha-plugin' );

# Resolve pp from local/bin (carton-installed) to avoid system pp conflicts
my $pp = catfile( $local_bin, 'pp' );
if ( !-x $pp ) {
    # Fall back to PATH (e.g. when run via carton exec)
    $pp = 'pp';
}

# Ensure pp can find its own modules and project dependencies
$ENV{PERL5LIB} = join ':', catdir( $project_dir, 'local', 'lib', 'perl5' ),
    catdir( $project_dir, 'lib' ), ( $ENV{PERL5LIB} // '' );

unless ( -d $dist_dir ) {
    make_path($dist_dir);
}

# PAR asset paths use "source;target" to control extraction layout
my @assets = (
    catdir( $project_dir, 'scripts' )   . ';scripts',
    catdir( $project_dir, 'templates' ) . ';templates',
    catdir( $project_dir, 'lib' )       . ';lib',
);

my $lib_dir   = catdir( $project_dir, 'lib' );
my $local_lib = catdir( $project_dir, 'local', 'lib', 'perl5' );

my @command = (
    $pp,
    '-o', $output_path,

    # Include paths so pp can find Local:: and CPAN modules
    '-I', $lib_dir,
    '-I', $local_lib,

    # Local modules
    '-M', 'Local::Util',
    '-M', 'Local::Metadata',
    '-M', 'Local::Command::Init',
    '-M', 'Local::Command::Add',
    '-M', 'Local::Command::Increment',
    '-M', 'Local::Config',

    # CPAN dependencies used across all commands
    '-M', 'DateTime',
    '-M', 'Data::Dumper',
    '-M', 'File::Basename',
    '-M', 'File::Path',
    '-M', 'Getopt::Long',
    '-M', 'JSON',
    '-M', 'List::Util',
    '-M', 'Path::Tiny',
    '-M', 'Perl::Tidy',
    '-M', 'Readonly',
    '-M', 'Template',
    '-M', 'Term::ANSIColor',
    '-M', 'Term::Choose',
    '-M', 'Term::ReadLine',
    '-M', 'Term::UI',
    '-M', 'YAML::Tiny',

    # Hidden deps (runtime-loaded, not caught by pp's static scanner)
    '-M', 'Log::Message',
    '-M', 'Log::Message::Simple',
    '-M', 'Module::Runtime',
    '-M', 'Module::Implementation',
    '-M', 'parent',

    # Bundle asset directories and .env
    ( map { ( '-a', $_ ) } @assets ),

    # Main script
    $script_path,
);

say 'Building binary...';
say "Command: @command";

system(@command) == 0 or die "Build failed: $!\n";

chmod 0755, $output_path;
say "Binary created at: $output_path";
