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

## Koha core hook prototypes (to file at bugs.koha-community.org)

Prototypes drafted under `bugs/`. Each documents the seam, implementation
sketch, test plan, and plugin-side example. File the bug, replace the TBD
number, prototype the patch on a `bug-NNNNN` branch.

### Hooks for currently-workaround patterns (workarounds shipped in real plugins)

- [ ] **Bug TBD-0001** — `permissions` plugin hook + auto-register sub-permissions. ([prototype](bugs/0001-plugin-permissions-hook.md))
- [ ] **Bug TBD-0002** — `plugin_module` registration + `log_action` helper using ACTN1 JSON Diff. ([prototype](bugs/0002-plugin-audit-action-hook.md))
- [ ] **Bug TBD-0003** — `Koha::Database->txn(\&code)` re-entrant transaction helper. ([prototype](bugs/0003-koha-database-txn-helper.md))
- [ ] **Bug TBD-0004** — `Koha::Plugin::Cron` base with `mark_done` / `already_done` for idempotent cron. ([prototype](bugs/0004-plugin-cron-idempotency.md))
- [ ] **Bug TBD-0005** — Expose `Koha::Object::Mixin::AdditionalFields` to plain DBI consumers. ([prototype](bugs/0005-additional-fields-mixin-for-dbi.md))
- [ ] **Bug TBD-0011** — `Koha::Recurrence` shared RFC 5545 helper. ([prototype](bugs/0011-koha-recurrence-shared-module.md))
- [ ] **Bug TBD-0012** — Plugin gettext catalogs via `Koha::Plugins::Base->translator`. ([prototype](bugs/0012-plugin-i18n-catalog-hook.md))

### Hooks for newly-surveyed extension gaps (Koha is internally extensible, no plugin wiring today)

- [ ] **Bug TBD-0006** — `opac_user_menu_tab` plugin hook for the OPAC "Your account" sidebar. ([prototype](bugs/0006-opac-user-menu-tab-hook.md))
- [ ] **Bug TBD-0007** — `messaging_preferences` plugin hook to register patron message attributes. ([prototype](bugs/0007-plugin-messaging-preferences-hook.md))
- [ ] **Bug TBD-0008** — `opac_pages` plugin hook reusing `opac-page.tt` chrome. ([prototype](bugs/0008-plugin-opac-pages-hook.md))
- [ ] **Bug TBD-0009** — `additional_content` plugin hook merged at `Koha::AdditionalContents->get`. ([prototype](bugs/0009-additional-contents-plugin-merge-hook.md))
- [ ] **Bug TBD-0010** — Generalize `Koha::Plugins::Tab` to staff patron, admin home, OPAC main, acquisitions vendor surfaces. ([prototype](bugs/0010-generalize-plugins-tab.md))

### Coding-guideline cross-reference

Each prototype declares which Koha guidelines it follows in a "Coding guideline
compliance" section (PERL10 no-`$dbh`-in-sig, PERL15 namespace, PERL16 hashref
args, PERL26 exceptions, PERL30 ref-passing, PERL31 `use` over `require`,
ACTN1 JSON Diff for action_logs, SEC1 CSRF). The `bugs/README.md` index has
the full table.
