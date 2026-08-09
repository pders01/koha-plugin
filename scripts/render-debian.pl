#!/usr/bin/env perl
use strict;
use warnings;

my ( $template_path, $output_path ) = @ARGV;
die "Usage: render-debian.pl TEMPLATE OUTPUT\n" if !defined $template_path || !defined $output_path;

open my $input, '<', $template_path or die "Cannot open template $template_path: $!\n";
my $content = do { local $/; <$input> };
close $input or die "Cannot close template $template_path: $!\n";

$content =~ s[\{\{([A-Z][A-Z0-9_]*)\}\}]
    [exists $ENV{"DEB_TEMPLATE_$1"}
        ? $ENV{"DEB_TEMPLATE_$1"}
        : die "Template variable $1 is not set for $template_path\n"]gex;

die "Unresolved template variable in $template_path\n" if $content =~ /\{\{[A-Z][A-Z0-9_]*\}\}/;

open my $output, '>', $output_path or die "Cannot open output $output_path: $!\n";
print {$output} $content or die "Cannot write output $output_path: $!\n";
close $output or die "Cannot close output $output_path: $!\n";
