## Command Reference

### `koha-plugin init`

Interactive plugin initialization. Prompts for metadata, lets you select hooks, and generates all files.

**Creates:**
- `Koha/Plugin/<TLD>/<ORG>/<PROJECT>.pm` — main plugin module with selected hooks
- `Koha/Plugin/<TLD>/<ORG>/PLUGIN.yml` — plugin manifest
- `koha-plugin.yml` — project config file
- `.gitignore` — ignores tool artifacts (dist/, local/, node_modules/, .env)
- `<plugin_dir>/<action>.tt` — for each selected UI hook (admin, configure, report, tool)
- `<plugin_dir>/openapi.json` — empty spec when `api` hook is selected
- `<plugin_dir>/staticapi.json` — static routes spec when `static` hook is selected

On failure, all generated files are cleaned up automatically.

---

### `koha-plugin add <component>`

Add a component to an existing plugin.

#### `koha-plugin add action`

Generate a UI page template for admin, configure, report, or tool hooks.

**Creates:** `<plugin_dir>/<action>.tt`

Use this when you want to add a UI hook after initial scaffolding.

#### `koha-plugin add node`

Initialize a Node.js project for frontend development (Vue, React, etc.).

**Creates:** `package.json`, `src/` directory

The generated `package.json` is pre-filled with plugin metadata (name, version, author, description).

#### `koha-plugin add api-route`

Interactively add an OpenAPI route to your plugin's API.

**Prompts for:** route path, HTTP method, operation ID, controller class, Koha permission, response description.

**Creates/updates:**
- `<plugin_dir>/openapi.json` — adds the route entry
- `Koha/Plugin/<TLD>/<ORG>/<PROJECT>/<Controller>.pm` — creates controller with method stub, or appends method to existing controller

Path parameters (e.g., `/widgets/{widget_id}`) are auto-detected and added to the spec.

---

### `koha-plugin increment [--type TYPE] [--times N]`

Increment the plugin version following semver conventions.

**Options:**
- `--type` — `patch` (default), `minor`, or `major`
- `--times` — number of increments (default: 1)

**Updates:**
- `koha-plugin.yml` (or legacy `.env`) — version and date_updated
- `package.json` — version (if present)
- Base plugin module — package version declaration and `$metadata` hash

Lower-order components are reset on minor/major bumps (e.g., `1.2.5 --type minor` becomes `1.3.0`).

---

### `koha-plugin package`

Create a `.kpz` (Koha Plugin Zip) file from the `Koha/` directory.

**Creates:** `<release_filename>-<version>.kpz`

Run `increment` before packaging to ensure the version is correct.

---

### `koha-plugin clean`

Remove the `Koha/` directory and `package.json`. Use this to start fresh.

---

### `koha-plugin staticapi`

Regenerate `staticapi.json` from files in the plugin's static directory.

---

### `koha-plugin ktd [container] [binary]`

Deploy the plugin to a KTD (Koha Testing Docker) container.

**Defaults:** container=`kohadev-koha-1`, binary=`docker`

Also supports `podman` as the container binary.

---

### `koha-plugin migrate [format]`

Migrate a legacy `.env` file to `koha-plugin.yml` or `koha-plugin.json`.

**Format:** `yml` (default) or `json`

The old `.env` is renamed to `.env.bak` automatically.

---

### `koha-plugin update-meta`

Pull the latest version of the koha-plugin scaffolding tool from upstream. Preserves local changes via git stash.

---

### `koha-plugin --version`

Show the tool version.

### `koha-plugin --help`

Show the help text with all commands and options.
