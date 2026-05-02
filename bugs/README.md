# Koha bug prototypes

Prototype bugs to file at https://bugs.koha-community.org for the plugin hooks identified in `../docs/`. Each file follows the convention used by recent hook-adding commits in `~/Projects/kcom/koha`:

- Bug 39870 — `notices_content` hook (Koha::Plugins->call dispatch)
- Bug 40972 — `xslt_record_processor_filters` hook (Koha::Plugins->call with mutable list)
- Bug 27114 — `intranet_catalog_biblio_tab` via `KohaPlugins.get_plugins_*` template helper
- Bug 31503 — `patron_consent_type` hook + `KohaPlugins.feature_enabled` predicate

Each prototype here mirrors that shape:

- One subject line per bug, conventional commit style.
- Summary that names the seam being opened and the plugin author benefit.
- Implementation sketch — minimum viable diff, no extra polish.
- Test plan with numbered steps that an signer-off-er can replay verbatim.
- Plugin-side example so the hook contract is unambiguous.

Bug numbers are placeholders (`Bug TBD-NNNN`). Replace with the real Bugzilla id when filed.

## Index

### Hooks for currently-workaround patterns

| File | Subject | Replaces workaround |
|------|---------|---------------------|
| [0001](0001-plugin-permissions-hook.md) | Add `permissions` plugin hook + auto-register sub-permissions | [`plugin-permissions.md`](../docs/plugin-permissions.md) — INSERT/intranet_js label injector |
| [0002](0002-plugin-audit-action-hook.md) | Add `before_plugin_action` / `after_plugin_action` hook + module registry | [`plugin-audit-logging.md`](../docs/plugin-audit-logging.md) — `_audit` helper |
| [0003](0003-koha-database-txn-helper.md) | Add `Koha::Database->txn(\&code)` helper | [`plugin-transactions.md`](../docs/plugin-transactions.md) — `_txn` helper |
| [0004](0004-plugin-cron-idempotency.md) | Add `Koha::Plugin::Cron` base with `mark_done` / `already_done` | [`plugin-cron-idempotency.md`](../docs/plugin-cron-idempotency.md) — action_logs sentinel |
| [0005](0005-additional-fields-mixin-for-dbi.md) | Expose `Koha::Object::Mixin::AdditionalFields` to plain DBI consumers | [`plugin-additional-fields.md`](../docs/plugin-additional-fields.md) — five private helpers |
| [0011](0011-koha-recurrence-shared-module.md) | Add `Koha::Recurrence` shared RFC 5545 module | [`plugin-rrule.md`](../docs/plugin-rrule.md) — per-plugin RRULE parsing |
| [0012](0012-plugin-i18n-catalog-hook.md) | Plugin gettext catalogs via `Koha::Plugins::Base->translator` | [`plugin-i18n.md`](../docs/plugin-i18n.md) — per-plugin JSON dictionary |

### Hooks for newly-surveyed extension gaps

| File | Subject | Gap |
|------|---------|-----|
| [0006](0006-opac-user-menu-tab-hook.md) | Add `opac_user_menu_tab` plugin hook | Hardcoded `usermenu.inc` |
| [0007](0007-plugin-messaging-preferences-hook.md) | Add `messaging_preferences` plugin hook | Hardcoded message_attributes labels |
| [0008](0008-plugin-opac-pages-hook.md) | Add plugin-rendered OPAC pages | `additional_contents.category='pages'` enum |
| [0009](0009-additional-contents-plugin-merge-hook.md) | Add `additional_content` plugin hook merged at `AdditionalContents->get` | Closed location enum |
| [0010](0010-generalize-plugins-tab.md) | Generalize `Koha::Plugins::Tab` to staff patron + admin home | Tab shape unused beyond biblio detail |

## How to use

1. Pick a bug file. Read it end-to-end.
2. File a bug at https://bugs.koha-community.org with the subject line as-is and the body of the file as the description.
3. Prototype the patch on a branch named `bug-NNNNN`.
4. When merged, mark the row in `../TODO.md` and delete the file from this directory.

## Conventions

- **Hook signatures** mirror the closest existing hook. Don't invent new shapes when `notices_content` / `intranet_catalog_biblio_tab` already work.
- **`Koha::Plugins->call('hook', \$arg_or_\%args)`** for hooks that return values, passing arguments by reference per PERL30 so each plugin sees mutations applied by prior plugins (Bug 40972, Bug 39870 pattern).
- **`KohaPlugins.get_plugins_<area>`** TT helper for hooks that contribute UI (Bug 27114 pattern).
- **`KohaPlugins.feature_enabled('hook_name')`** for opt-in UI gating (Bug 31503 pattern).
- **`enable_plugins` short-circuit** at the top of every dispatcher — every shipped hook starts with `return ... unless C4::Context->config('enable_plugins')`.
- **Try/catch around plugin calls** so one buggy plugin can't break core. Warn with the plugin class name.

## Coding-guideline cross-reference

Every prototype here adheres to the relevant Koha coding guidelines (see `../KOHA_CODING_GUIDELINES.md`):

| Guideline | Applies how |
|-----------|-------------|
| **PERL10** | No `$dbh` in helper signatures — every helper reaches for `C4::Context->dbh` itself. |
| **PERL15** | Shared helpers live in `Koha::` (Plugins::Base, Database, AdditionalFields, Recurrence) and avoid `C4::` except `C4::Context`. |
| **PERL16** | Multi-arg subs take a hashref so call sites stay readable as fields are added. |
| **PERL26** | Errors raise `Koha::Exception` subclasses, not bare `die`. |
| **PERL30** | Every `Koha::Plugins->call` passes `\$ref` / `\@ref` / `\%ref` so hooks compose. |
| **PERL31** | New hooks `use` Koha::Plugins at the top of the consuming module — `require` only inside plugin code that loads-by-name. |
| **ACTN1** | Audit log writes pass both `$infos` (post-modification) and `$original` (pre-modification, via `clone`/`get_from_storage`) for JSON-Diff rendering. |
| **SEC1** | Hook-driven forms still go through the global CSRF middleware; controllers reject stateful methods without a token. |
