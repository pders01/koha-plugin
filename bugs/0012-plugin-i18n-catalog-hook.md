# Bug TBD-0012: Plugin gettext catalogs

## Subject

`Bug TBD: Add plugin gettext catalog support so plugin strings join the .po pipeline`

## Summary

Plugins are not part of Koha's gettext / `.po` pipeline. Strings inside plugin `.pm` / `.tt` / `.ts` files are invisible to Pootle and Weblate, so translators have no way to localize a plugin without bespoke tooling per plugin. The current workaround is per-plugin JSON dictionaries (one for Perl, one for the bundled frontend) that fall back to the English source key.

This patch adds plugin gettext catalog support:

1. `Koha::Plugins::Base->translator` returns a per-request translator backed by Koha's `Locale::Messages` infrastructure.
2. A scaffold helper extracts strings from a plugin and produces a `.po` template (`<pluginslug>.pot`) that the gettext toolchain compiles into `.mo` files alongside core translations.
3. A documented directory contract: plugin ships `locales/<plugin>.pot`, compiled `.mo` files land at install time under `<plugin>/locales/<lang>/LC_MESSAGES/`.

Result: plugin authors stop hand-rolling JSON dictionaries; translators use the standard pipeline.

## Coding guideline compliance

- **PERL10** — translator helper uses `C4::Languages::getlanguage()` and `C4::Context` internally; no `$dbh` / `$env` parameters.
- **PERL15** — translator method lives on `Koha::Plugins::Base`.
- **PERL31** — `use Locale::Messages;` at the top of the base class.

## Rationale

`koha-plugin-staff-roster` ships its own `Lib/I18N.pm` + `locales/<lang>.json` + parallel `src/i18n/<lang>.ts` per locale. The pattern works, but:

- Translators have to learn a per-plugin format. They lose Pootle/Weblate web UIs.
- No plural forms.
- Two parallel dictionaries (Perl / TS) drift.
- Adding a locale is two files per language plus a bundle rebuild.

Reusing core's gettext pipeline keeps plugins in the standard workflow.

## Files touched

- `Koha/Plugins/Base.pm` — add `translator($lang)` method; load `.mo` from the plugin directory.
- `Koha/Plugins/I18N.pm` — new module wrapping `Locale::Messages` for plugin scope.
- `misc/translator/PluginPOTExtractor.pm` — new module that walks a plugin directory and extracts translatable strings to a `.pot`.
- `bin/koha-plugin.pl extract-pot` — CLI to invoke the extractor.
- Documented directory layout: `<plugin>/locales/<lang>/LC_MESSAGES/<slug>.mo`.

## API

```perl
# Plugin-side
sub tool {
    my ($self, $args) = @_;
    my $tr       = $self->translator;       # closure: $tr->('English source')
    my $template = $self->get_template({ file => 'tool.tt' });
    $template->param( tr => $tr );
    return $self->output_html($template->output);
}
```

```html
[% tr('Save configuration') | html %]
[% tr('You have %d unread messages', count) | html %]
```

For the JS side, expose the same dictionary as a JSON blob via the static API:

```perl
# Plugin-side
sub static_routes {
    my ($self) = @_;
    return $self->_static_routes_with_locale_dump;   # auto-mounts /locales/<lang>.json
}
```

```ts
import { __ } from "@koha/plugin-i18n/runtime";
__("Save configuration");
```

`@koha/plugin-i18n/runtime` is a small shared package emitted alongside the plugin scaffolding tool that fetches `/api/v1/contrib/<namespace>/static/locales/<lang>.json` once at boot.

## Implementation sketch

```perl
# Koha/Plugins/Base.pm
sub translator {
    my ( $self, $lang ) = @_;
    require Koha::Plugins::I18N;
    return Koha::Plugins::I18N->for_plugin({
        plugin => $self,
        lang   => $lang // C4::Languages::getlanguage(),
    });
}

# Koha/Plugins/I18N.pm
sub for_plugin {
    my ( $class, $params ) = @_;
    my $plugin = $params->{plugin};
    my $lang   = $params->{lang};
    my $domain = $plugin->get_metadata->{release_filename} // ref $plugin;
    $domain =~ s/[^A-Za-z0-9]+/_/g;

    my $dir = $plugin->bundle_path . '/locales';
    return sub { $_[0] } if !-d $dir;

    require Locale::Messages;
    Locale::Messages::bindtextdomain( $domain, $dir );
    Locale::Messages::bind_textdomain_codeset( $domain, 'UTF-8' );

    return sub {
        my ( $key, @args ) = @_;
        return $key if !defined $key;
        my $val = Locale::Messages::dgettext( $domain, $key );
        return @args ? sprintf( $val, @args ) : $val;
    };
}
```

The extractor walks `*.pm`, `*.tt`, and `*.ts` files in the plugin, recognises `tr('...')`, `__('...')`, and `[% tr('...') %]` calls, and emits a `.pot`. Translators run the standard `msgmerge` / `msgfmt` flow against it; `.mo` files land under `<plugin>/locales/<lang>/LC_MESSAGES/<slug>.mo`.

## Test plan

1. Apply the patch.
2. Build a plugin with `tr('Hello world')` in a template and `tr('Save')` in a `.pm`.
3. Run `bin/koha-plugin.pl extract-pot`. Confirm `locales/<slug>.pot` is generated with both strings.
4. `msginit -l de -o locales/de/LC_MESSAGES/<slug>.po locales/<slug>.pot`. Translate. `msgfmt`.
5. Install the plugin in a Koha instance with German selected. Confirm the template renders the German translation.
6. Confirm a missing string falls through to the English source.
7. Confirm plural forms work via `ngettext` (extend the helper accordingly).
8. Confirm the bundled JS shim picks up `/api/v1/contrib/<namespace>/static/locales/de.json` and renders the same translation in Lit components.
9. Test fallback: plugin with no `locales/` directory returns English untouched.

## Plugin-side example

```perl
package Koha::Plugin::Com::Example::MyPlugin;
use base qw(Koha::Plugins::Base);

sub configure {
    my ($self, $args) = @_;
    my $tr       = $self->translator;
    my $template = $self->get_template({ file => 'configure.tt' });
    $template->param( tr => $tr, page_title => $tr->('Configuration') );
    return $self->output_html($template->output);
}
```

## Cross-references

- Workaround: `docs/plugin-i18n.md` — the JSON-dictionary helper currently shipped per plugin.
- Related: `koha-plugin-staff-roster` commits `480dd0e`, `89a3b68`, `857728b`, `10c789b` — German translation rolled out via the per-plugin JSON pattern.
- Pairs with Bug TBD-0008 (plugin OPAC pages) — page handlers receive `tr` automatically once translators are first-class.

## Signed-off-by

(to be filled in during review)
