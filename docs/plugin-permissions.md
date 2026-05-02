## Plugin-provided granular permissions

Koha has no first-class hook for plugins to register their own staff permissions. The pattern below works today by writing directly into Koha's `permissions` table under `module_bit = 19` (the `plugins` module), then checking grants via `C4::Auth::haspermission`. It is a workaround — a native registration hook would remove every caveat in this document.

This pattern is implemented end-to-end in [`koha-plugin-staff-roster`](../../koha-plugin-staff-roster/Koha/Plugin/Xyz/Paulderscheid/StaffRoster.pm).

### Why this is a workaround, not a feature

- No hook to declare permissions. Plugins must `INSERT` into a core table.
- No core machinery to render labels for plugin codes. `koha-tmpl/.../includes/permissions.inc` uses a hardcoded `SWITCH/CASE` over known codes; unknown (plugin) codes render an empty `<label>`. Plugins must inject labels via `intranet_js`.
- No lifecycle integration. Install, upgrade, and uninstall must each manage the rows manually, and `REPLACE INTO` is unsafe because of cascading deletes.
- No UI grouping. Plugin codes appear flat under the "plugins" module alongside every other plugin's codes.

### Background: how Koha stores staff permissions

Two tables, both keyed on `(module_bit, code)`:

| Table | Role |
|-------|------|
| `permissions` | Catalogue of available permissions. One row per `(module_bit, code)` describes what the permission means. |
| `user_permissions` | Grants. One row per `(borrowernumber, module_bit, code)` says "this staff member has this permission". |

`module_bit = 19` is the `plugins` module. Three flag states matter:

- `flags = 1` — superlibrarian, bypasses every check.
- `flags & (1 << 19)` set — wholesale "plugins" permission. Implies every plugin sub-permission.
- `flags & (1 << 19)` unset, `user_permissions` row exists — limited mode. The user has only the listed plugin sub-permissions.

A grant in `user_permissions` only takes effect when the user is in *limited* mode for that module (the module bit in `flags` is **not** set). Wholesale grants short-circuit the sub-permission check.

### 1. Declare your codes

Keep the catalogue in one place so install, upgrade, and uninstall see the same set:

```perl
my %SUBPERMISSIONS = (
    staffroster_view           => 'Staff Roster: view rosters and own schedule',
    staffroster_assign         => 'Staff Roster: drag staff onto slots and edit assignments',
    staffroster_manage_rosters => 'Staff Roster: create or edit rosters, slots, exceptions',
    # ...
);
```

Code conventions:

- Prefix every code with your plugin's slug (`staffroster_*`) — the global namespace under module 19 is shared with every other installed plugin.
- Use snake_case. Koha's UI is built around that style.
- Keep the description short; it appears next to a checkbox on the staff member's "Set permissions" page.

### 2. Register on install (and re-register on upgrade)

Per Koha coding guideline PERL10, helpers reach for `C4::Context->dbh` themselves rather than accepting `$dbh` through the signature.

```perl
sub _register_permissions {
    my $dbh = C4::Context->dbh;
    # Upsert rather than REPLACE: the latter does DELETE + INSERT, which
    # cascade-clobbers any existing user_permissions grants for the same
    # (module_bit, code) every time the plugin upgrades.
    for my $code ( sort keys %SUBPERMISSIONS ) {
        $dbh->do(
            q{INSERT INTO permissions (module_bit, code, description)
              VALUES (19, ?, ?)
              ON DUPLICATE KEY UPDATE description = VALUES(description)},
            undef, $code, $SUBPERMISSIONS{$code}
        );
    }
    return;
}
```

> **Critical:** `REPLACE INTO permissions` is unsafe. The `user_permissions` foreign key cascades on `DELETE`, so a `REPLACE` against the catalogue silently wipes every grant for that code. Use `INSERT ... ON DUPLICATE KEY UPDATE` so only the description changes.

Wire it into both lifecycle hooks so existing installs pick up new codes and description tweaks without manual intervention:

```perl
sub install {
    my ($self) = @_;
    # ... your CREATE TABLEs ...
    _register_permissions();
    return 1;
}

sub upgrade {
    my ($self) = @_;
    # ... version-gated migrations ...
    _register_permissions();
    $self->store_data({ '__INSTALLED_VERSION__' => $self->get_metadata->{version} });
    return 1;
}
```

### 3. Clean up on uninstall

Drop both the catalogue rows and any grants. Without the second statement, removing the plugin and reinstalling can leave dangling `user_permissions` rows pointing at codes whose descriptions have drifted.

```perl
sub _unregister_permissions {
    my @codes = keys %SUBPERMISSIONS;
    return if !@codes;
    my $dbh          = C4::Context->dbh;
    my $placeholders = join q{,}, ('?') x @codes;
    $dbh->do(
        qq{DELETE FROM permissions WHERE module_bit = 19 AND code IN ($placeholders)},
        undef, @codes
    );
    $dbh->do(
        qq{DELETE FROM user_permissions WHERE module_bit = 19 AND code IN ($placeholders)},
        undef, @codes
    );
    return;
}
```

### 4. Check permissions at the gate

Every protected handler should funnel through one helper. Bypass for superlibrarians (`flags == 1` or the lowest bit set) matches Koha's convention everywhere else.

```perl
sub _has_perm {
    my ($code) = @_;
    my $env = C4::Context->userenv;
    return 0 if !$env;
    my $flags = $env->{flags} // 0;
    return 1 if $flags == 1 || ( $flags & 1 );
    require C4::Auth;
    return C4::Auth::haspermission( $env->{id}, { plugins => $code } ) ? 1 : 0;
}

sub _gate {
    my ( $code, $messages ) = @_;
    return 1 if _has_perm($code);
    push @{$messages}, { type => 'danger', code => 'access_denied' };
    return 0;
}
```

`haspermission` accepts `{ plugins => $code }` and returns truthy when the user is either:

- A superlibrarian, or
- Granted `plugins` wholesale (module bit 19 set in `flags`), or
- In limited mode and has a `user_permissions` row for that exact `(19, $code)`.

Use the gate at the top of each action:

```perl
sub _admin_save_type {
    my ( $cgi, $id, $messages ) = @_;
    return if !_gate( 'staffroster_manage_types', $messages );
    my $dbh = C4::Context->dbh;
    # ... privileged work ...
}
```

### Gate the CGI surface, not just the REST API

`x-koha-authorization` in `openapi.json` (see [`plugin-rest-api.md`](plugin-rest-api.md)) gates the JSON endpoints. The rendered HTML shell that wraps them is a separate surface — a user with Koha's generic `tools` flag can reach `plugins/run.pl?...&method=tool&op=manage_swaps` even when the underlying JSON calls would 403. Two surfaces, two gates needed.

Map each tool op to its required sub-permission and gate before the view renderer runs. Visibility checks come second; falling back to `list` on access denied keeps the breadcrumb stable:

```perl
sub tool {
    my ( $self, $args ) = @_;
    my $cgi = $self->{cgi};
    my $op  = $cgi->param('op') // 'list';
    my @messages;

    # Sub-permission gates parallel to the REST layer's checks. The CGI
    # views previously only relied on Koha's generic `tools` flag, which
    # let any tools-flagged user reach the rendered shell even when the
    # JSON endpoints behind it would 403. Gate first, then proceed.
    state $perm_for_view = {
        manage_slots      => 'staffroster_manage_rosters',
        manage_exceptions => 'staffroster_manage_rosters',
        manage_swaps      => 'staffroster_manage_rosters',
        edit_roster       => 'staffroster_manage_rosters',
        add_roster        => 'staffroster_manage_rosters',
        delete_confirm    => 'staffroster_manage_rosters',
        view_assignments  => 'staffroster_view',
        list              => 'staffroster_view',
        my_shifts         => 'staffroster_view',
        open_shifts       => 'staffroster_self_assign',
    };
    if ( my $required = $perm_for_view->{$op} ) {
        if ( !Koha::Plugin::...::Lib::Permissions::has_perm($required) ) {
            push @messages, { type => 'danger', code => 'access_denied' };
            $op = 'list';
        }
    }

    # Visibility gate for ops that scope to a specific roster.
    state $roster_scoped_ops = { map { $_ => 1 }
        qw(edit_roster manage_slots manage_exceptions manage_swaps view_assignments delete_confirm) };
    if ( $roster_scoped_ops->{$op} && ( my $rid = $cgi->param('roster_id') ) ) {
        my $roster = $dbh->selectrow_hashref(
            q{SELECT * FROM staff_roster WHERE id = ?}, undef, $rid);
        if ( !Koha::Plugin::...::Lib::Visibility::can_view_roster( $self, $roster ) ) {
            push @messages, { type => 'danger', code => 'access_denied' };
            $op = 'list';
        }
    }

    # ... renderer dispatch ...
}
```

Audit the surfaces in pairs: every REST route's `x-koha-authorization` should have a corresponding entry in the CGI `$perm_for_view` map for the op that hosts the JS that calls it. Drift between the two is the failure mode this catches.

### 5. Render labels on the "Set permissions" page

Koha's `members/member-flags.pl` page renders sub-permissions through `permissions.inc`, which has a hardcoded `[% SWITCH name %]` block over the codes it knows about. A plugin code lands in the `[% CASE %]` (default) branch, which emits an empty `<label>`. The checkbox renders, the user can toggle it, but there is no description text next to it.

Inject labels client-side via `intranet_js`. The page id on current Koha main is `pat_member-flags` (newer staff theme work has used `patrons_member-flags` in places — the JS below matches both for safety).

```perl
sub intranet_js {
    my $self = shift;
    return <<~'JS';
    <script>
    (function () {
      var page = document.body && document.body.id;
      if (page !== 'patrons_member-flags' && page !== 'pat_member-flags') return;
      var labels = {
        staffroster_view:           'Staff Roster: view rosters and own schedule',
        staffroster_assign:         'Staff Roster: drag staff onto slots and edit assignments',
        staffroster_manage_rosters: 'Staff Roster: create or edit rosters, slots, exceptions'
        // ...keep in sync with %SUBPERMISSIONS
      };
      // Sub-permission checkboxes carry value="<flag>:<code>"
      // (e.g. "plugins:staffroster_view") and id "<flag>_<code>".
      // Strip the prefix before looking up the label map.
      document.querySelectorAll('input.flag[type="checkbox"][name="flag"]').forEach(function (cb) {
        var raw  = cb.value || '';
        var code = raw.indexOf(':') >= 0 ? raw.split(':')[1] : raw;
        if (!Object.prototype.hasOwnProperty.call(labels, code)) return;
        var label = document.querySelector('label[for="' + cb.id + '"]')
                 || (cb.closest('li, tr, div') || document).querySelector('label.permissiondesc');
        if (label && !label.textContent.trim()) {
          label.innerHTML = '<span class="sub_permission">' + labels[code] +
            '</span> <span class="permissioncode">(' + code + ')</span>';
        }
      });
    })();
    </script>
    JS
}
```

Notes:

- The checkbox `value` is `"plugins:<code>"` — strip the `plugins:` prefix before lookup. A previous iteration of this pattern matched on the raw value and silently failed.
- Only overwrite labels that are blank (`!label.textContent.trim()`). Future Koha releases may learn to render plugin codes natively; bailing on populated labels avoids fighting them.
- Inject only on the flags page. `intranet_js` runs on every staff page, so always gate by `document.body.id`.

### 6. Wholesale vs limited mode in practice

Sites tend to fall into two camps:

- **Wholesale**: staff who can use plugins get the `plugins` module bit and inherit every sub-permission your plugin defines, including any new ones added in later versions. Good default for trusted teams.
- **Limited**: each staff tier gets exactly the codes they need (`staffroster_view` for everyone, `staffroster_swap_approve` only for managers, etc.). Choose code names so the rollup makes sense — e.g. split read/write/manage rather than per-button.

Document which is intended in your plugin's README; otherwise sites will pick the wrong mode and either over-grant or break workflows.

### Common pitfalls

| Pitfall | Symptom | Fix |
|---------|---------|-----|
| Using `REPLACE INTO permissions` | Grants silently disappear after upgrade | Use `INSERT ... ON DUPLICATE KEY UPDATE` |
| Not re-running registration in `upgrade` | New codes from a later release never appear | Always call your `_register_permissions` from both `install` and `upgrade` |
| Matching JS labels against raw checkbox value | Labels never appear | Strip the `plugins:` prefix before lookup |
| Forgetting superlibrarian bypass in `_has_perm` | Admins get "access denied" on their own plugin | Short-circuit `flags == 1` or `flags & 1` |
| Skipping `_gate` on a single CRUD action | A non-privileged user can hit the action via direct URL | Gate every action handler, not just the rendering layer |
| Leaving `user_permissions` rows on uninstall | Reinstall surfaces stale grants tied to old descriptions | Delete from both `permissions` and `user_permissions` in `uninstall` |

### Where native integration would help

If Koha grew first-class plugin permission support, these would all collapse into hook output:

- A `permissions` hook returning `{ code => description }` so plugins never touch SQL.
- Automatic registration on install/upgrade and cleanup on uninstall.
- Label rendering in `permissions.inc` via the same hook output, removing the `intranet_js` workaround entirely.
- Per-plugin grouping headers on the flags page.
- Optional `module_bit` namespacing per plugin to avoid the shared global namespace.

The implementation above is forward-compatible: when a native hook lands, dropping the SQL helpers and the JS injector while keeping the `_has_perm` / `_gate` gates leaves all callers untouched.

### References

- `members/member-flags.pl` and `koha-tmpl/intranet-tmpl/prog/en/includes/permissions.inc` — where label rendering lives in core.
- `C4::Auth::haspermission` — runtime check used by every staff page.
- [`koha-plugin-staff-roster` `StaffRoster.pm`](../../koha-plugin-staff-roster/Koha/Plugin/Xyz/Paulderscheid/StaffRoster.pm) — full working implementation (search for `_register_permissions`, `_has_perm`, `intranet_js`).
