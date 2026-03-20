## Live Circulation Feed — Example Plugin

A real-time circulation activity feed that demonstrates the full Vue island
plugin architecture: hook capture, REST API, and a pre-built Vue component
registered via `registerIsland()`.

### What it does

- Captures checkout, check-in, and renewal events via `after_circ_action`
- Stores events in `plugin_circ_feed_events` table
- Serves recent events via `/api/v1/contrib/CircFeed/events/recent`
- Renders a Vue island (`<plugin-circ-feed>`) that polls the API every
  3 seconds and shows a live feed with colored badges and animations

### Prerequisites

- Koha with the islands patch (Bug 42150) for `registerIsland()` and the
  Vue import map
- KTD or any Koha development environment

### How it was built

Every file was scaffolded using the `koha-plugin` tool:

```bash
# 1. Create config
cat > koha-plugin.yml <<'YAML'
name: "Koha::Plugin::Com::Hackfest::CircFeed"
author: "Paul Derscheid"
version: "0.1.0"
description: "Live circulation activity feed"
release_filename: "hackfest-circfeed"
static_dir_name: "dist"
minimum_version: "23.11.00.000"
YAML

# 2. Scaffold
koha-plugin init --hooks install,upgrade,uninstall,configure,api,static,intranet_js,after_circ_action
koha-plugin add api-route --path /events/recent --method get --operation getRecentEvents \
  --controller EventController#recent --permission catalogue --description "Recent circulation events"
koha-plugin add migration --description create_circ_events_table
koha-plugin add vue --name CircFeed --tag plugin-circ-feed

# 3. Build
npm install
npm run build

# 4. Regenerate static routes and deploy
koha-plugin staticapi
koha-plugin ktd
```

Then the generated stubs were filled in with actual logic (see below).

### Files

```
Koha/Plugin/Com/Hackfest/CircFeed.pm              # Base module (hooks)
Koha/Plugin/Com/Hackfest/CircFeed/
  EventController.pm                                # REST controller
  openapi.json                                      # API spec
  staticapi.json                                    # Static file routes
  migrations/001_create_circ_events_table.sql       # DB schema
  CircFeed.js                                       # Built Vue component
  CircFeed.css                                      # Component styles
  PLUGIN.yml                                        # Manifest
src/
  main.js                                           # Vite entry point
  components/CircFeed.vue                           # Vue SFC source
vite.config.js                                      # Build config
package.json                                        # Node dependencies
koha-plugin.yml                                     # Tool config
```

### Key implementation details

**`after_circ_action` hook** — captures the action type, patron name, item
title, barcode, and library from the checkout object. Events older than 24
hours are automatically purged.

**`EventController#recent`** — returns the last 50 events as JSON, ordered
by ID ascending. The Vue component deduplicates by tracking the last seen
event ID.

**Vue component** — polls `/events/recent` every 3 seconds. Uses
`TransitionGroup` for animated entry of new events. Color-coded badges:
blue (checkout), green (check-in), orange (renewal).

**Why polling, not SSE** — Koha runs on Starman (pre-fork blocking server)
which doesn't support long-lived connections or event loops. SSE/WebSockets
require an async server like Hypnotoad. Polling at 3 seconds is visually
indistinguishable from real-time for a circulation feed.

**Static file path** — files are built directly into the plugin directory
(not a subdirectory) because Koha's `Static#get` resolves paths relative
to `bundle_path`. See the Vue Islands guide for details.

### Architecture

```
[Koha Circulation]
       |
       v
[after_circ_action hook]  -->  [plugin_circ_feed_events table]
                                        |
                                        v
                               [/events/recent API endpoint]
                                        |
                                        v
                               [Vue island polls every 3s]
                                        |
                                        v
                               [Live feed renders in browser]
```
