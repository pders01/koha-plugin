#!/usr/bin/env just --justfile

# Wrapper for running the CLI with the right lib paths.
# Uses carton if available, otherwise relies on PERL5LIB / system modules.
cli := if path_exists("local/lib/perl5") == "true" { "carton exec -- perl bin/koha-plugin.pl" } else { "perl bin/koha-plugin.pl" }
perl_exec := if path_exists("local/lib/perl5") == "true" { "carton exec -- perl" } else { "perl" }

# Lists available commands.
default:
  @just --list

# Careful! This removes Koha/ and package.json
clean:
  {{cli}} clean

# Initialises a new koha plugin based on your input.
init:
  {{cli}} init

# Adds a component to your initialised koha plugin based on your input.
add component:
  {{cli}} add {{component}}

# Increments the version in your local config, base module and package.json if present. This also updates date_updated!
increment type='patch' times='1':
  {{cli}} increment --type {{type}} --times {{times}}

# Creates a kpz file by zipping the current state of the `Koha` directory.
package:
  {{cli}} package

# Updates the staticapi.json file within the plugin to expose all files within the `static` directory.
staticapi:
  {{cli}} staticapi

ktd container="kohadev-koha-1" binary="docker":
  {{cli}} ktd {{container}} {{binary}}

# Attempts to update the koha-plugin repository itself. If you've updated core components, you'll have to resolve the conflicts yourself, though.
update-meta:
  {{cli}} update-meta

# Migrate legacy .env to config file
migrate format='yml':
  {{cli}} migrate {{format}}

# Validate plugin for common issues
check:
  {{cli}} check

# Build standalone binary
binary:
  {{perl_exec}} scripts/build-binary.pl
