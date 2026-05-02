## Module organization for non-trivial plugins

Plugins start as a single `.pm` with the lifecycle hooks inline. By the time the plugin handles half a dozen entrypoints, a REST API, scheduled cron, and an audit trail, the file is 2000+ lines and impossible to navigate. The pattern below — a `Lib::*` namespace for cross-cutting helpers and a `Controllers/<Surface>/<Op>.pm` namespace for per-op handlers — keeps the main module thin and the test surface narrow.

`koha-plugin-staff-roster` shipped this restructure across commits `7021e3f`..`8cdb8a0`. Main module shrank 2241 → 1122 lines.

### Layout

```
Koha/Plugin/<TLD>/<Org>/<Project>.pm                 # thin entrypoint: hook stubs + dispatcher maps
Koha/Plugin/<TLD>/<Org>/<Project>/
    Lib/
        Audit.pm                # audit + transaction helpers
        DateUtils.pm            # week-start, DST-safe date arithmetic
        I18N.pm                 # translator, JSON dictionary loader
        Permissions.pm          # sub-perm registry + has_perm/gate helpers
        Rrule.pm                # RRULE parse + apply checks
        Schema.pm               # install/upgrade/uninstall + migration registry
        Visibility.pm           # group walk + calendar closure helpers
        AdditionalFields.pm     # additional_fields load/save/delete/bulk
    Controllers/
        Tool/
            List.pm             # op=list
            Form.pm             # op=add_roster | edit_roster | delete_confirm
            Slots.pm            # op=manage_slots | view_assignments
            Exceptions.pm       # op=manage_exceptions
            Swaps.pm            # op=manage_swaps
            SelfService.pm      # op=my_shifts | open_shifts
    AssignmentController.pm     # REST controllers stay one-per-resource
    RosterController.pm
    StaffController.pm
```

Two namespaces, two responsibilities:

- **`Lib::*`** — cross-cutting helpers. No CGI, no template, no `op` knowledge. Pure helpers callable from any controller, any cron, any test.
- **`Controllers/<Surface>/<Op>.pm`** — per-op handler + view body. Knows about the dispatcher entry it serves; receives `$self, $dbh, $cgi, $template, $messages` and orchestrates the `Lib::*` helpers.

### What goes in `Lib::*`

A helper graduates to `Lib::*` when:

- It's called from more than one place (controllers, cron, tests, REST).
- It owns a single concept (audit, transactions, additional fields, RRULE parsing).
- It can be unit-tested without standing up a full template render.

Anti-patterns that should stay out of `Lib::*`:

- CGI or template handling — those live in controllers.
- Per-op business rules — those live in the controller for that op.
- Multi-concept catch-all modules (`Lib::Util.pm` is a smell).

### Lifecycle: `Lib::Schema` with a numbered migration registry

The lifecycle hooks (`install`, `upgrade`, `uninstall`) usually accumulate version chains:

```perl
sub upgrade {
    my ($self) = @_;
    my $v = $self->retrieve_data('__INSTALLED_VERSION__') // '0.0.0';
    if (_version_lt($v, '0.0.2')) { $dbh->do(q{ALTER TABLE ... }); }
    if (_version_lt($v, '0.0.3')) { $dbh->do(q{ALTER TABLE ... }); }
    # ... grows forever, each branch easy to forget
}
```

Replace with an ordered registry that `install` and `upgrade` both walk:

```perl
package Koha::Plugin::Xyz::Paulderscheid::StaffRoster::Lib::Schema;

my @MIGRATIONS = (
    { version => '0.0.1', up => \&_migrate_initial_schema },
    { version => '0.1.0', up => \&_migrate_swap_request_actor },
    # Append at the bottom; never reorder, never edit a shipped one.
);

sub _version_lt {
    my ( $a, $b ) = @_;
    my @a = split /\./smx, $a;
    my @b = split /\./smx, $b;
    for my $i ( 0 .. ( $#a > $#b ? $#a : $#b ) ) {
        my $av = $a[$i] // 0;
        my $bv = $b[$i] // 0;
        return 1 if $av < $bv;
        return 0 if $av > $bv;
    }
    return 0;
}

sub _apply_migrations {
    my ( $plugin, $dbh ) = @_;
    my $current = $plugin->retrieve_data('__SCHEMA_VERSION__') // '0.0.0';
    for my $m (@MIGRATIONS) {
        next if !_version_lt( $current, $m->{version} );
        $m->{up}->($dbh);
        $plugin->store_data({ __SCHEMA_VERSION__ => $m->{version} });
        $current = $m->{version};
    }
    return;
}

sub install {
    my ($plugin) = @_;
    my $dbh = C4::Context->dbh;
    _apply_migrations($plugin, $dbh);
    Koha::Plugin::...::Lib::Permissions::register($dbh);
    _register_notice_templates($dbh);
    $plugin->store_data({ __INSTALLED_VERSION__ => $plugin->get_metadata->{version} });
    return 1;
}

sub upgrade {
    my ($plugin) = @_;
    my $dbh = C4::Context->dbh;
    _apply_migrations($plugin, $dbh);                                  # same call
    Koha::Plugin::...::Lib::Permissions::register($dbh);               # idempotent re-register
    _register_notice_templates($dbh);
    $plugin->store_data({ __INSTALLED_VERSION__ => $plugin->get_metadata->{version} });
    return 1;
}
```

Three rules:

- **Append-only** — never reorder, never edit a migration that shipped. Every migration has run on real installs already; editing it changes history those installs can't replay.
- **Idempotent migrations** — write each `up` so a re-run is a no-op (use `IF NOT EXISTS`, `ON DUPLICATE KEY UPDATE`, etc.). The `_version_lt` gate is strict-greater-than, but defensive idempotency leaves the door open for repair runs.
- **Two version stamps, one schema version** — `__SCHEMA_VERSION__` (the latest applied migration) and `__INSTALLED_VERSION__` (the plugin release the schema corresponds to). They diverge intentionally when a release ships no schema change. The migration loop reads `__SCHEMA_VERSION__`; the rest of the plugin reads `__INSTALLED_VERSION__` for feature gates.

The main module's lifecycle hooks become one-line wrappers:

```perl
# main module — Koha::Plugin::Xyz::Paulderscheid::StaffRoster
use Koha::Plugin::Xyz::Paulderscheid::StaffRoster::Lib::Schema;

sub install   { return Koha::Plugin::Xyz::Paulderscheid::StaffRoster::Lib::Schema::install($_[0]); }
sub upgrade   { return Koha::Plugin::Xyz::Paulderscheid::StaffRoster::Lib::Schema::upgrade($_[0]); }
sub uninstall { return Koha::Plugin::Xyz::Paulderscheid::StaffRoster::Lib::Schema::uninstall($_[0]); }
```

### Controllers: per-op packages with shared dispatch maps

The single `tool` hook handles many ops via a dispatcher. Hold the maps in the main module so the gate logic and post-dispatch cleanup stay in one place; let each map entry point at a `Controllers/Tool/<Op>` package:

```perl
# main module
use Koha::Plugin::Xyz::Paulderscheid::StaffRoster::Controllers::Tool::List;
use Koha::Plugin::Xyz::Paulderscheid::StaffRoster::Controllers::Tool::Form;
use Koha::Plugin::Xyz::Paulderscheid::StaffRoster::Controllers::Tool::Slots;
# ... etc

my %TOOL_VIEWS = (
    list              => \&Koha::Plugin::...::Controllers::Tool::List::view_list,
    add_roster        => \&Koha::Plugin::...::Controllers::Tool::Form::view_roster_form,
    edit_roster       => \&Koha::Plugin::...::Controllers::Tool::Form::view_roster_form,
    delete_confirm    => \&Koha::Plugin::...::Controllers::Tool::Form::view_delete_confirm,
    manage_slots      => \&Koha::Plugin::...::Controllers::Tool::Slots::view_manage_slots,
    view_assignments  => \&Koha::Plugin::...::Controllers::Tool::Slots::view_assignments,
    manage_exceptions => \&Koha::Plugin::...::Controllers::Tool::Exceptions::view_manage_exceptions,
    manage_swaps      => \&Koha::Plugin::...::Controllers::Tool::Swaps::view_manage_swaps,
);

my %TOOL_ACTIONS = (
    'cud-save_roster'    => { handler => \&Koha::Plugin::...::Controllers::Tool::Form::save_roster,    next => 'list' },
    'cud-delete_roster'  => { handler => \&Koha::Plugin::...::Controllers::Tool::Form::delete_roster,  next => 'list' },
    'cud-save_slot'      => { handler => \&Koha::Plugin::...::Controllers::Tool::Slots::save_slot,     next => 'manage_slots' },
    # ... etc
);
```

Each `Controllers/Tool/<Op>.pm`:

```perl
package Koha::Plugin::Xyz::Paulderscheid::StaffRoster::Controllers::Tool::Slots;

use Modern::Perl;
use C4::Context;

use Koha::Plugin::Xyz::Paulderscheid::StaffRoster::Lib::Audit;
use Koha::Plugin::Xyz::Paulderscheid::StaffRoster::Lib::Permissions;
use Koha::Plugin::Xyz::Paulderscheid::StaffRoster::Lib::Rrule;

sub view_manage_slots {
    my ( $self, $dbh, $cgi, $template ) = @_;
    # ... pull data, set template params ...
}

sub save_slot {
    my ( $self, $dbh, $cgi, $messages ) = @_;
    return if !Koha::Plugin::...::Lib::Permissions::gate( 'staffroster_manage_rosters', $messages );
    # ... save logic, _audit, etc ...
}

1;
```

Convention: each subcontroller exports nothing. Callers reference functions by fully-qualified name. The main module's dispatcher map is the entire public API of the package.

### Wiring tests

The split affects how tests bind helpers. Two patterns work:

```perl
# Test-side: bind by package-qualified name via require
require Koha::Plugin::Xyz::Paulderscheid::StaffRoster::Lib::Permissions;
my $register = \&Koha::Plugin::...::Lib::Permissions::register;
$register->($dbh);

# Test-side: bind a coderef once at the top, reuse
use Koha::Plugin::Xyz::Paulderscheid::StaffRoster::Lib::Audit qw( txn );
txn(sub { ... });
```

`t/00-load.t` should pick up every `.pm` so a missing `use` line in a fresh module fails fast:

```perl
use_ok( 'Koha::Plugin::Xyz::Paulderscheid::StaffRoster::Lib::Audit' );
use_ok( 'Koha::Plugin::Xyz::Paulderscheid::StaffRoster::Lib::Permissions' );
# ... etc, one per .pm in the tree
```

### Backwards-compat shims during the migration

Mid-restructure, the old call shape (`_audit('CREATE', $id, $info, $original)` in the main module) is still in flight while the controllers move out. Keep a thin shim until every caller is migrated, then drop it:

```perl
# main module — TEMPORARY shim during the Lib/* migration
sub _audit {
    return Koha::Plugin::Xyz::Paulderscheid::StaffRoster::Lib::Audit::log_action(@_);
}
```

Mark the shim with a comment dating it; remove once `git grep '_audit\b' Koha/` is silent. The staff-roster final commit (`8cdb8a0`) lists every shim it dropped; a clean ledger like that is the marker for "restructure complete."

### When to reach for this

Three signals:

- The main module crosses 1500 lines.
- A single hook (`tool`, `report`, `api_routes`) dispatches to more than three op handlers.
- Test files duplicate `_audit` / `_txn` / permission-helper imports across files.

For plugins with one `tool` op and a single REST endpoint, this is overkill. For plugins growing past their initial scope, the restructure pays off the first time you need to run `prove t/some_module.t` without booting the whole plugin's dependency graph.

### Where native integration would help

- A plugin scaffold (`koha-plugin add lib`, `koha-plugin add controller`) that lays out the convention from day one.
- A `Koha::Plugins::Base::Schema` mixin with the migration-registry walker so plugins stop reimplementing `_apply_migrations`.
- A documented dispatcher contract so the per-op map can be declared in YAML alongside permissions, and core wires the gate + view + visibility checks.
