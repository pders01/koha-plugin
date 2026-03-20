## Quickstart

Get from zero to a working Koha plugin in under 5 minutes.

### Prerequisites

- Perl 5.10+ (any recent system Perl works)
- [Carton](https://metacpan.org/pod/Carton) (recommended) or install CPAN deps globally
- [just](https://just.systems/) (optional — you can use the CLI directly)

### Setup

```bash
# Clone the scaffolding tool
git clone https://github.com/pders01/koha-plugin.git my-plugin
cd my-plugin
rm -rf .git && git init

# Install dependencies (pick one)
carton install          # via carton (recommended)
cpanm --installdeps .   # via cpanm (global install)
```

### Create your plugin

```bash
# Interactive — prompts for name, author, hooks, etc.
perl bin/koha-plugin.pl init
# or: just init
```

This creates:
- Your plugin module at `Koha/Plugin/<TLD>/<ORG>/<Project>.pm`
- A `PLUGIN.yml` manifest
- A `koha-plugin.yml` config file
- `.gitignore`
- Template files for any UI hooks you selected
- `openapi.json` if you selected API hooks
- `staticapi.json` if you selected static file serving

### Add components

```bash
# Add an API route (interactive — prompts for path, method, etc.)
perl bin/koha-plugin.pl add api-route

# Add a UI page template
perl bin/koha-plugin.pl add action

# Add a Node.js frontend project
perl bin/koha-plugin.pl add node
```

### Develop

Edit your plugin module and templates. The generated code includes working stubs for every hook you selected.

### Version and package

```bash
# Bump the patch version
perl bin/koha-plugin.pl increment

# Bump minor version
perl bin/koha-plugin.pl increment --type minor

# Create a .kpz file for installation
perl bin/koha-plugin.pl package
```

### Test in KTD

```bash
# Deploy to a running KTD container
perl bin/koha-plugin.pl ktd

# With podman instead of docker
perl bin/koha-plugin.pl ktd kohadev-koha-1 podman
```

### Project structure

After running `init` and selecting some hooks, your project looks like:

```
my-plugin/
  Koha/Plugin/<TLD>/<ORG>/
    <Project>.pm          # Your plugin (generated, edit this)
    PLUGIN.yml            # Manifest
    openapi.json          # API spec (if api hooks selected)
    staticapi.json        # Static routes (if static hook selected)
    admin.tt              # UI templates (if action hooks selected)
    configure.tt
  koha-plugin.yml         # Tool config (version, name, etc.)
  .gitignore
  bin/koha-plugin.pl      # The CLI tool
  scripts/                # Shell scripts for packaging, KTD, etc.
  templates/              # Scaffolding templates (not your plugin templates)
  lib/                    # Tool internals
```

### Without carton

The tool doesn't require carton. If you install dependencies globally:

```bash
cpanm --installdeps .
perl bin/koha-plugin.pl init
```

Or set `PERL5LIB` to wherever your modules live. The tool auto-detects carton's `local/lib/perl5` if present, but doesn't require it.

### Standalone binary

Build a self-contained binary that bundles all dependencies:

```bash
just binary
# or: carton exec -- perl scripts/build-binary.pl

# Then distribute and use without any Perl setup:
./dist/koha-plugin init
```

### Migrating from .env

If you have an existing project using `.env`:

```bash
perl bin/koha-plugin.pl migrate yml   # or: migrate json
```

This creates `koha-plugin.yml` and renames `.env` to `.env.bak`.

### Next steps

- Read the [command reference](commands.md) for all options
- Browse the [hooks reference](koha-plugin-hooks.md) to understand each hook
- Check the [Kitchen Sink plugin](https://github.com/bywatersolutions/dev-koha-plugin-kitchen-sink) for working examples of every hook
- For database migrations, see [LMSCloud plugin utils](https://github.com/LMSCloudPaulD/koha-plugin-lmscloud-util)
