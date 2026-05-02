# Bug TBD-0010: Generalize `Koha::Plugins::Tab` to staff patron + admin home

## Subject

`Bug TBD: Generalize Koha::Plugins::Tab to additional tabbed UI surfaces`

## Summary

`Koha::Plugins::Tab` (`Koha/Plugins/Tab.pm`) is currently used only for `intranet_catalog_biblio_tab`. Several other tabbed UIs in core have the same shape and would benefit from the same hook treatment without changing the `Tab` object:

- Staff patron details page (`members/moremember.pl`).
- Admin home page (`/cgi-bin/koha/admin/admin-home.pl`).
- OPAC main page tiles (`opac-main.pl`).
- Acquisition vendor detail tabs.

Each new surface follows the same pattern as Bug 27114: a small `KohaPlugins.get_plugins_<area>_tabs` template helper on `Koha::Template::Plugin::KohaPlugins` and a `[% FOREACH tab IN ... %]` block in the relevant template.

## Coding guideline compliance

- **PERL15** — every helper added to `Koha::Template::Plugin::KohaPlugins`.
- **PERL30** — each `Koha::Plugins->call` invocation passes the context as a hashref reference.
- Same `enable_plugins` short-circuit + try/catch wrapping as the existing helpers.

## Rationale

`Koha::Plugins::Tab` today carries `id`, `title`, `content` only — no `url`, no `view` — and `new()` enforces both `title` and `content` as mandatory. Extending it to other tab surfaces requires a small object-model change first (see Bug TBD-0006: add `url` + `view` to `mk_accessors` and relax the `content` mandatory check to "`content` or `url` required"). Once that lands, all four surfaces here are purely template + dispatcher work — no further changes to `Koha::Plugins::Tab`.

This is one bug rather than four because the shape is identical and the patches are tiny. Reviewers can sign off on each surface independently as follow-ups.

## Files touched

Prerequisite (depends on Bug TBD-0006 or done first here):

- `Koha/Plugins/Tab.pm` — add `url` and `view` to `mk_accessors`; relax `content` mandatory check to "`content` or `url` required".

Per surface (replicate four times):

- `Koha/Template/Plugin/KohaPlugins.pm` — add `get_plugins_<area>_tabs(\%params)`.
- The relevant `.tt` template — `[% FOREACH tab IN KohaPlugins.get_plugins_<area>_tabs(...) %]`.
- A passthrough on the `.pl` script when context (e.g. `{ patron => $patron }`) needs to flow into the hook.
- Test in `t/db_dependent/Koha/Template/Plugin/KohaPlugins.t`.

## Hooks added

| Hook | Surface | Receives | Returns |
|------|---------|----------|---------|
| `staff_patron_tab` | `members/moremember.pl` | `{ patron, active }` | One or more `Koha::Plugins::Tab` |
| `admin_home_tile` | `admin/admin-home.pl` | `{ active }` | Tile entries (`title`, `url`, `description`, `permission`) |
| `opac_main_tile` | `opac-main.pl` | `{ logged_in_user, branchcode }` | Tile entries |
| `acquisitions_vendor_tab` | `acqui/supplier.pl` | `{ vendor, active }` | One or more `Koha::Plugins::Tab` |

## Implementation sketch

```perl
# Koha/Template/Plugin/KohaPlugins.pm — generic helper used by each accessor.
sub _collect_tabs {
    my ( $self, $hook, $params ) = @_;
    my $tabs = [];
    return $tabs unless C4::Context->config('enable_plugins');
    my $p = Koha::Plugins->new or return $tabs;
    for my $plugin ( $p->GetPlugins({ method => $hook }) ) {
        try {
            my @new = $plugin->$hook($params);
            for my $tab (@new) {
                next if !$tab;
                my $id = 'tab-' . $plugin->{class} . '-' . ( $tab->title // q{} );
                $id =~ s/[^0-9A-Za-z]+/-/g;
                $tab->id($id);
            }
            push @{$tabs}, grep { $_ } @new;
        }
        catch { warn "Error calling '$hook' on " . $plugin->{class} . " ($_)"; };
    }
    return $tabs;
}

sub get_plugins_staff_patron_tabs    { my ( $s, $p ) = @_; return $s->_collect_tabs( 'staff_patron_tab',    $p ); }
sub get_plugins_admin_home_tiles     { my ( $s, $p ) = @_; return $s->_collect_tabs( 'admin_home_tile',     $p ); }
sub get_plugins_opac_main_tiles      { my ( $s, $p ) = @_; return $s->_collect_tabs( 'opac_main_tile',      $p ); }
sub get_plugins_acquisitions_vendor_tabs { my ( $s, $p ) = @_; return $s->_collect_tabs( 'acquisitions_vendor_tab', $p ); }
```

Template insertion is one block per surface, e.g. `members/moremember.tt`:

```html
[% FOREACH tab IN KohaPlugins.get_plugins_staff_patron_tabs({ patron => patron, active => active }) %]
    <li role="presentation"[% IF tab.view == active %] class="active"[% END %]>
        <a href="[% tab.url | url %]">[% tab.title | html %]</a>
    </li>
[% END %]
```

## Test plan

For each of the four surfaces:

1. Apply the patch.
2. Enable plugins; install a plugin that implements the relevant hook.
3. Visit the surface and confirm the new tab / tile renders after the core entries.
4. Click the tab; confirm `view` matches the page state and `class="active"` is applied.
5. Trigger an exception from inside the plugin's hook. Confirm the page still renders, the bad plugin is `warn`-logged, and other plugins' tabs still appear.
6. Disable the plugin. Tab disappears.
7. For permission-gated tiles (`admin_home_tile` carries a `permission` field), confirm the tile is hidden when the staff member lacks the permission and visible when granted.

## Plugin-side example

```perl
package Koha::Plugin::Com::Example::MyPlugin;
use base qw(Koha::Plugins::Base);
use Koha::Plugins::Tab;

sub staff_patron_tab {
    my ( $self, $params ) = @_;
    my $patron = $params->{patron} or return;
    return Koha::Plugins::Tab->new({
        title => 'Roster',
        url   => '/cgi-bin/koha/plugins/run.pl?class=' . $self->{class}
                 . '&method=tool&op=patron_view&borrowernumber=' . $patron->borrowernumber,
        view  => 'plugin_roster',
    });
}

sub admin_home_tile {
    my ($self) = @_;
    return ({
        title       => 'Staff Roster',
        url         => '/cgi-bin/koha/plugins/run.pl?class=' . $self->{class} . '&method=tool',
        description => 'Manage roster types and schedules',
        permission  => { plugins => 'staffroster_manage_rosters' },
    });
}
```

## Cross-references

- Survey: `docs/koha-extension-gaps.md` § 5.
- Sibling shape: Bug 27114 (`intranet_catalog_biblio_tab`).
- Pairs with Bug TBD-0001 (permissions hook) for `permission` gating on tiles.
- Pairs with Bug TBD-0006 (OPAC user menu tab) — same `_collect_tabs` mechanism, different surface.

## Signed-off-by

(to be filled in during review)
