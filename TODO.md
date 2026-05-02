# To-Do

## Done

- [x] Rewrite all the hook templates w/ an LLM to follow the style of install.pl.
- [x] Remove the .bak file after perltidy was executed.
- [x] Find another name for the .env file as it can throw a warning by GitGuardian (assumes exposed credentials). => Migrated to koha-plugin.yml/json.
- [x] Write a base template for the _Actions_.
- [x] Integrate scaffolding of node project components, e.g. Vue front ends or similar.
- [x] Create an easy integration w/ the pages feature. => Hooks are now grouped by category with all 50+ supported.
- [x] Provide a template for openapi.json as well, best generated from existing controllers if possible. => Composable via `add api-route` with controller generation.
- [x] Bundle the whole thing w/ PPI so users don't need perl ^v5.038 or perlbrew. => PAR::Packer binary, dropped feature 'class' dependency.

## Next

- [x] `add vue` — scaffold a Vue island component with vite build setup and static_routes integration.
- [ ] Explore plugin-provided Pinia store sharing with core islands (needs Koha-side design).
- [ ] Address CSP nonce for plugin inline scripts when Koha enforces CSP.
