## Plugin i18n via JSON dictionaries

Koha core uses `gettext` / `.po` files compiled by the translation toolchain. Plugins are not part of that pipeline — `.po` files for a plugin's strings would be invisible to Pootle/Weblate, and Koha's gettext compile step doesn't traverse plugin directories. Plugins that need translation either ship English-only or roll their own dictionary.

The lightest pattern that works in both Perl and TypeScript is a flat JSON dictionary per language, English source as key, missing keys falling through to English. `koha-plugin-staff-roster` ships this end-to-end: a Perl helper for `.pm` and `.tt` callers, a parallel TypeScript shim for Lit components.

### Layout

```
Koha/Plugin/.../StaffRoster/
    Lib/
        I18N.pm                    # Perl helper, request-scoped translator
    locales/
        de.json                    # flat { key => translation }, server-side
src/
    i18n/
        index.ts                   # bundle-time module shared by Lit components
        de.ts                      # one TypeScript file per language, baked in
```

Two parallel dictionaries (server-side JSON, frontend bundled TS) is intentional. The server-side JSON is loaded per request from disk so admins can drop in a new locale without rebuilding; the TS dictionary is bundled because the Lit components are static assets and Vite tree-shakes unused locales.

### Perl side

```perl
package Koha::Plugin::Xyz::Paulderscheid::StaffRoster::Lib::I18N;
use Modern::Perl;
use Exporter qw( import );
our @EXPORT_OK = qw( tr translator load );

use File::Spec;
use Mojo::JSON qw( decode_json );

# Cache: { lang => hashref } — load once per language per worker.
my %CACHE;

sub _locales_dir {
    my $here = __FILE__;
    $here =~ s{Lib/I18N\.pm$}{locales};
    return $here;
}

sub load {
    my ($lang) = @_;
    return $CACHE{$lang} if exists $CACHE{$lang};
    my $path = File::Spec->catfile( _locales_dir(), "$lang.json" );
    my $dict = {};
    if ( -r $path ) {
        my $bytes = do {
            open my $fh, '<:raw', $path or return $CACHE{$lang} = $dict;
            local $/;
            <$fh>;
        };
        $dict = eval { decode_json($bytes) } || {};
    }
    return $CACHE{$lang} = $dict;
}

sub _current_lang {
    require C4::Languages;
    my $lang = C4::Languages::getlanguage() // 'en';
    # Koha returns codes like 'de-DE'; key by the two-letter prefix so
    # 'de-DE' and 'de-AT' share de.json.
    $lang =~ s/[-_].*$//;
    return $lang || 'en';
}

sub translator {
    my ($lang) = @_;
    $lang //= _current_lang();
    return sub { $_[0] } if $lang eq 'en';
    my $dict = load($lang);
    return sub {
        my ($key) = @_;
        return $key if !defined $key;
        return $dict->{$key} // $key;
    };
}

sub tr {
    my ($key) = @_;
    state $current = translator();
    return $current->($key);
}

1;
```

Three deliberate choices:

- **Disk-cache per worker, not request** — Plack workers are persistent; reading the JSON once per worker per language costs nothing on subsequent requests. The cache key is the language string, so adding `fr.json` doesn't bust the loaded `de.json`.
- **Two-letter prefix grouping** — `de-DE` and `de-AT` share `de.json`. Locale variants get their own file only when a real divergence appears.
- **`return sub { $_[0] }` for English** — skip the dict lookup entirely so the English source path stays free.

### Wiring `tr` into templates

Pass the translator into the template once per render:

```perl
sub _common_template_params {
    my ($self) = @_;
    return (
        tr          => Koha::Plugin::Xyz::Paulderscheid::StaffRoster::Lib::I18N::translator(),
        plugin_lang => Koha::Plugin::Xyz::Paulderscheid::StaffRoster::Lib::I18N::_current_lang(),
    );
}

sub tool {
    my ($self, $args) = @_;
    my $template = $self->get_template({ file => 'tool.tt' });
    $template->param( $self->_common_template_params, ... );
    return $self->output_html( $template->output );
}
```

Templates call it like a function:

```html
<h1>[% tr('Staff Roster') | html %]</h1>
<button>[% tr('Save configuration') | html %]</button>
```

`plugin_lang` lands as a separate parameter so templates can `[% IF plugin_lang == 'de' %]...[% END %]` for locale-specific markup (date format hints, RTL toggles, etc.).

### TypeScript side

Bundle one TS file per locale; pick the active one at module load from `<html lang>`:

```ts
// src/i18n/index.ts
import { de } from "./de.js";

type Dict = Readonly<Record<string, string>>;
const DICTS: Readonly<Record<string, Dict>> = { de };

function detectLang(): string {
  const raw = (typeof document !== "undefined" && document.documentElement.lang) || "en";
  return raw.toLowerCase().split(/[-_]/)[0] ?? "en";
}

const ACTIVE: Dict = DICTS[detectLang()] ?? {};

export function __(key: string): string {
  return ACTIVE[key] ?? key;
}
```

```ts
// src/i18n/de.ts
export const de: Readonly<Record<string, string>> = {
  "Staff Roster": "Personalplan",
  "Save configuration": "Konfiguration speichern",
  "Loading...": "Wird geladen...",
};
```

Components import `__` and use it like `gettext`:

```ts
import { __ } from "../i18n/index.js";

render() {
  return html`<button aria-label=${__("Edit shift")}>${__("Edit")}</button>`;
}
```

Koha sets `<html lang="de-DE">` from the staff intranet language preference, so the choice mirrors the TT side automatically. No separate frontend toggle.

### Shared label maps as functions, not consts

Static `const STATUS_LABELS = { scheduled: __("Scheduled"), ... }` evaluates `__()` at module import time — before `<html lang>` is necessarily set, before the dictionary is loaded for some build modes. The translations bake in as English. Wrap the map in a thunk so each render rebuilds with the active language:

```ts
// src/labels.ts
import type { Assignment } from "./api.js";
import { __ } from "./i18n/index.js";

export type AssignmentStatus = Assignment["status"];

export const STATUS_LABELS = (): Record<AssignmentStatus, string> => ({
  scheduled: __("Scheduled"),
  confirmed: __("Confirmed"),
  completed: __("Completed"),
  cancelled: __("Cancelled"),
  no_show: __("No-show"),
});
```

```ts
// In a Lit component
render() {
  const labels = STATUS_LABELS();
  // bind once per render so the per-cell loop doesn't re-call __() per assignment
  return html`${this.assignments.map(a => html`<span>${labels[a.status]}</span>`)}`;
}
```

Two wins: translations resolve correctly under module-load timing edge cases, and binding to a local once per render keeps the per-row loop from re-running `__()` and reallocating the map on every iteration.

### Translator's view of "what to translate"

Adding a new locale is one file on each side:

1. Copy `locales/en-template.json` (an English-source-keyed file shipped for translators) to `locales/<lang>.json`. Translate values. Untranslated keys fall through to English.
2. Copy `src/i18n/de.ts` to `<lang>.ts`, translate, register in `DICTS` in `index.ts`. Build the bundle.

Two friction points compared to gettext:

- **No plural forms.** Flat dictionaries don't model `n=0,1,n>1`. Koha-plugin-staff-roster emits separate keys (`"1 shift"`, `"shifts"`) and joins client-side. For plugins with heavy pluralisation, `Intl.PluralRules` on the JS side and `Locale::PO`-shaped helpers on the Perl side are options — but at the cost of either losing the simplicity or growing the helper.
- **No translator tooling integration.** Pootle, Weblate, Crowdin all expect `.po` / `.xliff`. Plugin authors shipping JSON dictionaries are off the standard pipeline. Worth flagging in the README so contributors know the workflow.

### Pitfalls

| Pitfall | Symptom | Fix |
|---------|---------|-----|
| Cache the translator at module load instead of per-call | Language change mid-request never propagates | `state $current = translator()` is per-instance — use `translator()` each time the language might change, or invalidate the state when wiring a multi-language admin tool |
| Forget the `<html lang>` source on the JS side | Frontend stays English while server side translates | Confirm Koha actually sets `<html lang>` on intranet pages; OPAC requires `OPACShowLanguageSelectionInModal` or similar to render it |
| Pass dict refs into templates instead of `tr` | Template mutates the cached dict | Always pass the translator code-ref; the dict stays private to the helper |
| Hardcoded English in `aria-label` / `title` | Screen readers stay English even with a translation | Wrap every user-facing string in `tr(...)` / `__(...)`, including ARIA |
| English source string contains punctuation that drifts | "Save..." vs "Save…" mismatch silently falls through | Pick one variant, audit with grep before shipping a release |

### Where native integration would help

- A first-class plugin gettext catalog so plugins join the standard `.po` / Pootle pipeline alongside core.
- A `Koha::Plugins::Base->translator` method backed by core's translation infrastructure so plugins drop the per-plugin helper.
- A documented contract for translator tooling (where to look for plugin `.po` files, how to compile, where the `.mo` lands).
