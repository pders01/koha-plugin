# Bug TBD-0001: Add `permissions` plugin hook to register staff sub-permissions

## Subject

`Bug TBD: Add 'permissions' plugin hook to register staff sub-permissions`

## Summary

Plugins currently register their staff sub-permissions by writing rows to `permissions` directly under `module_bit = 19` (the `plugins` module) and re-render labels with an `intranet_js` injector because `permissions.inc` has a hardcoded `[% SWITCH code %]` block. This patch adds a `permissions` plugin hook that:

1. Returns a hashref of plugin codes and labels.
2. Is consulted on plugin install / upgrade / uninstall to maintain the catalogue rows automatically.
3. Is consulted by `permissions.inc` to render the description for a plugin code natively.

Plugins stop touching SQL directly, the `intranet_js` workaround disappears, and grants in `user_permissions` survive plugin upgrades without per-plugin `INSERT ... ON DUPLICATE KEY UPDATE` boilerplate.

## Rationale

Today every plugin that wants permission gating ships an `INSERT ... ON DUPLICATE KEY UPDATE` loop on install, the same loop on upgrade, a paired `DELETE` on uninstall, and an `intranet_js` label injector — all duplicated across plugins. See `koha-plugin-staff-roster` for a worked example. A native hook collapses these into a single declarative method.

A `REPLACE INTO permissions` is unsafe (cascades a DELETE that removes `user_permissions` grants), so the workaround must use `INSERT ... ON DUPLICATE KEY UPDATE` — easy to get wrong. Centralising the lifecycle in core eliminates the trap.

## Files touched

- `Koha/Plugins/Base.pm` — call `permissions` hook from `install` / `upgrade` / `uninstall` lifecycle helpers.
- `Koha/Template/Plugin/KohaPlugins.pm` — add `get_plugin_permission_label($code)`.
- `koha-tmpl/intranet-tmpl/prog/en/includes/permissions.inc` — fall through to the new helper for codes the SWITCH/CASE doesn't know.
- `members/member-flags.pl` — pass plugin codes through alongside core ones.

## Hook signature

Mirrors `notices_content` (Bug 39870) — declarative return value, dispatched via `Koha::Plugins->call`.

```perl
# Plugin-side
sub permissions {
    my ($self) = @_;
    return {
        myplugin_view   => 'My Plugin: read access',
        myplugin_manage => 'My Plugin: configure rosters',
    };
}
```

## Implementation sketch

### Lifecycle dispatch in `Koha::Plugins::Base`

```perl
# In Koha/Plugins/Base.pm — called by Plugins::Handler after install / upgrade.
sub _sync_plugin_permissions {
    my ($self) = @_;
    return if !$self->can('permissions');
    my $codes = $self->permissions;
    return if ref $codes ne 'HASH';
    my $dbh = C4::Context->dbh;
    for my $code ( sort keys %{$codes} ) {
        $dbh->do(
            q{INSERT INTO permissions (module_bit, code, description)
              VALUES (19, ?, ?)
              ON DUPLICATE KEY UPDATE description = VALUES(description)},
            undef, $code, $codes->{$code}
        );
    }
    return;
}

# In uninstall lifecycle:
sub _drop_plugin_permissions {
    my ($self) = @_;
    return if !$self->can('permissions');
    my @codes = keys %{ $self->permissions || {} };
    return if !@codes;
    my $dbh = C4::Context->dbh;
    my $ph  = join q{,}, ('?') x @codes;
    $dbh->do(qq{DELETE FROM permissions WHERE module_bit = 19 AND code IN ($ph)},
             undef, @codes);
    $dbh->do(qq{DELETE FROM user_permissions WHERE module_bit = 19 AND code IN ($ph)},
             undef, @codes);
    return;
}
```

### Label rendering in `permissions.inc`

```html
[% USE KohaPlugins %]
...
[% CASE %]
    [% plugin_label = KohaPlugins.get_plugin_permission_label(sub_perm.code) %]
    [% IF plugin_label %]
        <span class="sub_permission">[% plugin_label | html %]</span>
        <span class="permissioncode">([% sub_perm.code | html %])</span>
    [% END %]
```

```perl
# Koha/Template/Plugin/KohaPlugins.pm
sub get_plugin_permission_label {
    my ( $self, $code ) = @_;
    return q{} unless C4::Context->config('enable_plugins');
    for my $p ( Koha::Plugins->new->GetPlugins({ method => 'permissions' }) ) {
        try {
            my $codes = $p->permissions;
            return $codes->{$code} if ref $codes eq 'HASH' && $codes->{$code};
        } catch { warn "Error calling 'permissions' on " . $p->{class} . " ($_)"; };
    }
    return q{};
}
```

## Test plan

1. Apply the patch.
2. Enable plugins in `koha-conf.xml`.
3. Install a plugin that defines `sub permissions { return { myplugin_view => 'Test view', myplugin_manage => 'Test manage' }; }`. The kitchen-sink plugin can grow such a method, or use the staff-roster plugin's existing codes.
4. Verify `SELECT * FROM permissions WHERE module_bit = 19 AND code LIKE 'myplugin%'` returns both rows with the expected descriptions.
5. Open `members/member-flags.pl` for a non-superlibrarian patron in limited-plugins mode. Confirm both checkboxes render with their human descriptions, not empty `<label>`s.
6. Grant `myplugin_view` only. Confirm `C4::Auth::haspermission( $borrowernumber, { plugins => 'myplugin_view' } )` returns 1 and the `myplugin_manage` check returns 0.
7. Edit the plugin's `permissions` method to change the description for `myplugin_view`. Re-trigger the plugin's `upgrade` (bump version, re-install). Verify the description in `permissions` updated *and* the existing `user_permissions` grant for `myplugin_view` is still present.
8. Uninstall the plugin. Verify both rows in `permissions` are gone and the dangling grant in `user_permissions` is gone too.

## Plugin-side example

```perl
package Koha::Plugin::Com::Example::MyPlugin;
use base qw(Koha::Plugins::Base);

sub permissions {
    my ($self) = @_;
    return {
        myplugin_view   => 'My Plugin: read access',
        myplugin_manage => 'My Plugin: configure',
    };
}

# Lifecycle no longer needs custom INSERT/DELETE — handled by core.
sub install   { return 1; }
sub upgrade   { return 1; }
sub uninstall { return 1; }
```

## Cross-references

- Workaround currently documented in `docs/plugin-permissions.md`.
- Closely related to Bug TBD-0009 (AdditionalContents merge): both replace SWITCH/CASE rendering with a plugin lookup.
- Similar lifecycle injection pattern as Bug 39522 (Valuebuilders as plugins).

## Signed-off-by

(to be filled in during review)
