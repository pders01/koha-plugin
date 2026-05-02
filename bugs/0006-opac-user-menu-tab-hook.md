# Bug TBD-0006: Add `opac_user_menu_tab` plugin hook

## Subject

`Bug TBD: Add opac_user_menu_tab plugin hook for Your account sidebar`

## Summary

`koha-tmpl/opac-tmpl/bootstrap/en/includes/usermenu.inc` is a hardcoded `<ul>` of `<li>` items gated on system preferences. Plugins that own a patron-facing page have no way to add an entry to the OPAC "Your account" sidebar without DOM-patching the rendered HTML via `opac_js`.

This patch adds an `opac_user_menu_tab` plugin hook that mirrors `intranet_catalog_biblio_tab` (Bug 27114): plugins return one or more `Koha::Plugins::Tab` instances; the OPAC user menu renders them after the core entries.

## Coding guideline compliance

- **PERL15** — TT helper lives in `Koha::Template::Plugin::KohaPlugins`, no `C4::` calls beyond `C4::Context`.
- **PERL30** — params passed to the hook are a hashref (`{ active, logged_in_user }`).
- **JS / accessibility** — generated `<li>` matches the ARIA + class conventions on the existing entries.

## Rationale

`usermenu.inc` already calls `[% USE KohaPlugins %]` and `KohaPlugins.feature_enabled('patron_consent_type')` for the Consents link (Bug 31503). The plumbing exists; the surface for plugin tabs does not.

Real plugins that want a tab today do one of:

1. Inject a `<li>` via `opac_js` DOM patching after page load (no `class="active"` state).
2. Ship a `Koha::AdditionalContents` fragment for `OpacNavRight` that admins must paste in by hand.
3. Skip the OPAC and ship intranet-only.

## Files touched

- `Koha/Template/Plugin/KohaPlugins.pm` — add `get_plugins_opac_user_menu_tabs`.
- `koha-tmpl/opac-tmpl/bootstrap/en/includes/usermenu.inc` — render plugin tabs after core entries.
- `Koha/Plugins/Tab.pm` — extend the class:
  - Add `url` and `view` to `mk_accessors` (current accessors are `title`, `content`, `id` only).
  - Make `content` optional in `new()` — sidebar / menu tabs render as anchors, not as `[% content %]` blocks, so the existing `Koha::Exceptions::MissingParameter->throw("Mandatory parameter 'content' missing")` guard would fire on every `Tab->new({ title, url, view })` constructed by this hook. The new contract: at least one of `content` (for in-page tab content, the existing biblio-detail use case) or `url` (for sidebar/menu links, the new use case) must be present.
- `t/db_dependent/Koha/Template/Plugin/KohaPlugins.t` — coverage.
- `t/Koha/Plugins/Tab.t` — coverage for the new accessors and the relaxed `content`-or-`url` mandatory check.

## Hook signature

```perl
sub opac_user_menu_tab {
    my ( $self, $params ) = @_;       # { logged_in_user => $patron, active => $view_string }
    return ( Koha::Plugins::Tab->new({
        title => 'My Roster',
        url   => '/cgi-bin/koha/plugins/run.pl?class=' . $self->{class} . '&method=opac',
        view  => 'rosterview',         # used to compute class="active"
    }) );
}
```

## Implementation sketch

```perl
# Koha/Template/Plugin/KohaPlugins.pm
sub get_plugins_opac_user_menu_tabs {
    my ( $self, $params ) = @_;
    my $tabs = [];
    return $tabs unless C4::Context->config('enable_plugins');
    my $p = Koha::Plugins->new or return $tabs;
    for my $plugin ( $p->GetPlugins({ method => 'opac_user_menu_tab' }) ) {
        try {
            my @new = $plugin->opac_user_menu_tab($params);
            for my $tab (@new) {
                my $id = 'tab-' . $plugin->{class} . '-' . ( $tab->title // q{} );
                $id =~ s/[^0-9A-Za-z]+/-/g;
                $tab->id($id);
            }
            push @{$tabs}, @new;
        }
        catch { warn "Error calling 'opac_user_menu_tab' on " . $plugin->{class} . " ($_)"; };
    }
    return $tabs;
}
```

```html
<!-- usermenu.inc, after core <li> entries -->
[% FOREACH tab IN KohaPlugins.get_plugins_opac_user_menu_tabs({ active => active_view, logged_in_user => logged_in_user }) %]
    <li[% IF tab.view && tab.view == active_view %] class="active"[% END %]>
        <a href="[% tab.url | url %]">[% tab.title | html %]</a>
    </li>
[% END %]
```

## Test plan

1. Apply the patch.
2. Enable plugins in `koha-conf.xml`.
3. Install a plugin that implements `opac_user_menu_tab` and returns a `Koha::Plugins::Tab` with title/url/view.
4. Log in to the OPAC. Confirm the new entry appears in the sidebar after the core entries.
5. Navigate to the plugin's page and ensure the `active` parameter matches the tab's `view` string. Confirm `class="active"` on the right `<li>`.
6. Disable the plugin. Confirm the entry disappears.
7. Install a second plugin that throws inside `opac_user_menu_tab`. Confirm the OPAC still renders, the bad plugin is logged via `warn`, and the first plugin's tab still appears.
8. Confirm the kitchen-sink plugin grows an `opac_user_menu_tab` example as part of this bug's follow-up.

## Plugin-side example

```perl
package Koha::Plugin::Com::Example::MyPlugin;
use base qw(Koha::Plugins::Base);

use Koha::Plugins::Tab;

sub opac_user_menu_tab {
    my ( $self, $params ) = @_;
    my $patron = $params->{logged_in_user} or return;
    return if !$patron->has_permission({ plugins => 'myplugin_view' });
    return Koha::Plugins::Tab->new({
        title => 'My Roster',
        url   => '/cgi-bin/koha/plugins/run.pl?class=' . $self->{class} . '&method=opac',
        view  => 'rosterview',
    });
}
```

## Cross-references

- Survey: `docs/koha-extension-gaps.md` § 1.
- Sibling shape: Bug 27114 (`intranet_catalog_biblio_tab`).
- Predicate sibling: Bug 31503 (`patron_consent_type` + `feature_enabled`).
- Pairs naturally with Bug TBD-0008 (plugin OPAC pages) — the tab's `url` points at the plugin-rendered page.

## Signed-off-by

(to be filled in during review)
