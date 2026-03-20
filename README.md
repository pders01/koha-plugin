# koha-plugin

A scaffolding tool for Koha plugins. Generates correct, working plugin code with interactive hook selection, API route composition, and version management.

[![GPLv3 License](https://img.shields.io/badge/License-GPL%20v3-yellow.svg)](https://opensource.org/licenses/)

## What it does

- **`init`** — Interactive plugin initialization: prompts for metadata, lets you pick from 50+ Koha hooks, generates the plugin module with working stubs, config file, manifest, templates, and `.gitignore`
- **`add`** — Incrementally add components: UI page templates, API routes (with controller generation), Node.js frontend projects
- **`increment`** — Semver-aware version bumping across config, module, and package.json
- **`package`** — Create `.kpz` files for Koha plugin installation
- **`ktd`** — One-command deployment to KTD containers

The generated plugin code is standard Koha — no runtime dependency on this tool. You can stop using the scaffolder at any time and continue developing by hand.

## Quick start

```bash
git clone https://github.com/pders01/koha-plugin.git my-plugin
cd my-plugin && rm -rf .git && git init
carton install    # or: cpanm --installdeps .
perl bin/koha-plugin.pl init
```

See the [quickstart guide](docs/quickstart.md) for the full walkthrough.

## Installation

### Dependencies

Install via [Carton](https://metacpan.org/pod/Carton) (recommended) or any CPAN client:

```bash
carton install
# or: cpanm --installdeps .
```

The tool also works with globally installed modules or `local::lib`. Carton is not required.

### Task runner (optional)

[just](https://just.systems/) provides convenient shortcuts. Run `just` for available commands. Everything `just` does can also be done directly with `perl bin/koha-plugin.pl`.

### Standalone binary

Build a self-contained binary that needs no Perl setup on the target system:

```bash
just binary
# Binary at dist/koha-plugin
```

## Documentation

- [Quickstart](docs/quickstart.md) — zero to working plugin in 5 minutes
- [Command reference](docs/commands.md) — all commands and options
- [Hook reference](docs/koha-plugin-hooks.md) — every Koha plugin hook with descriptions, return types, and groupings
- [Vue Islands guide](docs/vue-islands.md) — Vue micro frontends in Koha plugins
- [Writing a simple plugin](docs/how-to-write-a-simple-plugin.md) — minimal example
- [POD style guide](docs/pod-style-guide.md) — conventions for hook stubs
- [Live Circ Feed example](examples/circ-feed/) — full-featured demo plugin with API, Vue island, and polling

## Configuration

The tool reads plugin metadata from `koha-plugin.yml` (or `koha-plugin.json`):

```yaml
name: "Koha::Plugin::Com::Example::MyPlugin"
author: "Your Name"
version: "0.1.0"
description: "What your plugin does"
minimum_version: "22.11.00.000"
maximum_version: ""
release_filename: "example-myplugin"
static_dir_name: "static"
date_authored: "2026-03-20"
date_updated: "2026-03-20"
```

Legacy `.env` files are still supported. Migrate with `koha-plugin migrate yml`.

## Examples

- [koha-plugin-pomodoro](https://github.com/pders01/koha-plugin-pomodoro)
- [koha-plugin-command-palette](https://github.com/pders01/koha-plugin-command-palette)

## Related

- [LMSCloud plugin utils](https://github.com/LMSCloudPaulD/koha-plugin-lmscloud-util) — shared utilities for database migrations, OPAC pages, and i18n
- [Kitchen Sink plugin](https://github.com/bywatersolutions/dev-koha-plugin-kitchen-sink) — reference implementation of every Koha plugin hook

## Contributing

Contributions welcome. Please use `perltidy` and `perlimports` with the shipped configuration files.

## License

[GPL v3](https://github.com/pders01/koha-plugin?tab=GPL-3.0-1-ov-file#readme)

## Support

Ping me on [Koha's Mattermost](https://chat.koha-community.org) **@paulderscheid**.

## Author

[@pders01](https://www.github.com/pders01)
