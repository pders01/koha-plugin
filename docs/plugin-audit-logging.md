## Plugin audit logging via `action_logs`

Koha exposes no first-class audit hook for plugins. The pattern below routes plugin mutations into `action_logs` so admins see them in `tools/viewlog.pl` next to circulation, cataloguing, and acquisitions activity. A native plugin-action hook would replace it.

This pattern ships in [`koha-plugin-staff-roster`](../../koha-plugin-staff-roster/Koha/Plugin/Xyz/Paulderscheid/StaffRoster.pm) — search for `_audit`.

### Background

`action_logs` is the table behind `tools/viewlog.pl`. The columns plugin code interacts with:

| Column | Use |
|--------|-----|
| `module` | Which subsystem produced the entry. Core uses `CIRCULATION`, `CATALOGUING`, `MEMBERS`, etc. |
| `action` | Verb. Usually `CREATE`/`MODIFY`/`DELETE`; you can add `NOTICE`, `NOTICE_FAILED`, anything. |
| `object` | Numeric id of the touched record. |
| `info`   | Free-form payload. `C4::Log::logaction` JSON-encodes the 4th positional arg (`$infos`) into this column. |
| `diff`   | Structured JSON Diff, computed by `logaction` from `$original` vs `$updated` via `Struct::Diff` and stored separately from `info`. This is what `viewlog.pl` renders as the per-row diff view (ACTN1 / Bug 25159). |
| `interface` | `'opac'` / `'intranet'` / `'commandline'`, derived by `logaction` from `C4::Context->interface`. |
| `script`, `trace`, `user`, `timestamp` | Set automatically; not addressed by plugin code. |

A row produced by `logaction('STAFFROSTER', 'MODIFY', $id, $infos, undef, $original)` therefore lands `JSON($infos)` in `info` **and** `JSON(diff($original, $updated))` in `diff` — querying for a structured diff means reading `diff`, not `info`.

`viewlog.pl` filters by module, so picking a unique value (`STAFFROSTER`, `MYPLUGIN`, etc.) keeps your entries findable without colliding with core.

### Pattern

Per ACTN1 (Bug 25159), action_logs entries should carry both `$infos` (post-mutation) and `$original` (pre-mutation) so `viewlog.pl` can render a structured JSON Diff. The helper takes both and forwards them as the 4th and 6th positional arguments to `C4::Log::logaction`:

```perl
# Flow plugin mutations into Koha's action_logs so admins can audit changes
# from tools/viewlog.pl alongside borrower / catalogue / acquisitions activity.
# All entries land under module 'STAFFROSTER'; the entity (roster, slot,
# assignment, exception, type) and any extra context goes into $infos. The
# pre-mutation snapshot in $original lets viewlog.pl render the standard
# JSON Diff. C4::Log is loaded lazily inside the eval so the plugin still
# works on installs where the module path isn't ready (early boot, partial
# upgrades, tests without C4).
sub _audit {
    my ( $action, $object_id, $infos, $original ) = @_;
    return if !defined $action;
    eval {
        require C4::Log;
        $infos //= {};
        # ACTN1 / Bug 25159: pass $original (pre-state) so logaction can
        # produce a structured JSON diff in action_logs.diff. CREATE / DELETE
        # branches in C4::Log diff against {} when $original is undef, so
        # for those we still pass a hashref representing the full row.
        C4::Log::logaction( 'STAFFROSTER', $action, $object_id, $infos, undef, $original );
        1;
    };
    return;
}
```

Four deliberate choices:

- **Lazy `require C4::Log`** — keeps the plugin loadable on installs where the module path isn't ready. The rest of the plugin's Koha imports go at the top per PERL31; `C4::Log` stays inside the `eval` so a missing module never breaks audit-emitting handlers.
- **`eval` swallowing failure** — audit must never break the user-facing action. If the log write blows up, the request still succeeds.
- **Hashref `$infos`** — `logaction` JSON-encodes it, so structured context (entity, decision, actor, ids) survives intact and stays greppable.
- **Hashref `$original`** — pre-mutation snapshot. For MODIFY: `selectrow_hashref` of the row before `UPDATE`. For CREATE: pass the same `$infos` (or post-load row) so the diff renders the new row's full body. For DELETE: fetch-then-delete, pass the fetched row as `$original`.

### Call sites

Place an `_audit` call after every successful mutation. CREATE passes the after-row as `$original` so the diff is non-empty. MODIFY passes the pre-state captured before the `UPDATE`. DELETE passes the row fetched immediately before the `DELETE`:

```perl
# CREATE — capture the post-write row so the diff renders the full body.
my $new_id = $dbh->last_insert_id(undef, undef, 'staff_roster_slots', undef);
my $after  = $dbh->selectrow_hashref(q{SELECT * FROM staff_roster_slots WHERE id = ?}, undef, $new_id);
_audit('CREATE', $new_id, { entity => 'slot', roster_id => $rid }, $after);

# MODIFY — snapshot before the UPDATE.
my $original = $dbh->selectrow_hashref(q{SELECT * FROM staff_roster_slots WHERE id = ?}, undef, $slot_id);
$dbh->do(q{UPDATE staff_roster_slots SET ... WHERE id = ?}, undef, ..., $slot_id);
_audit('MODIFY', $slot_id, { entity => 'slot', roster_id => $rid }, $original);

# DELETE — fetch first, then delete, so the row is captured.
my $original = $dbh->selectrow_hashref(q{SELECT * FROM staff_roster_slots WHERE id = ?}, undef, $slot_id);
$dbh->do(q{DELETE FROM staff_roster_slots WHERE id = ?}, undef, $slot_id);
_audit('DELETE', $slot_id, { entity => 'slot' }, $original);
```

Two cases are exempt from the diff requirement:

- **NOTICE / NOTICE_FAILED** for cron: there is no mutated row, just a log entry. Pass `undef` for `$original` and a flat `$infos` hashref describing the event.
- **Bulk meta-actions** (move/clear over many rows): a per-object diff doesn't tell the operator anything meaningful. Pass `undef` for `$original` and let the meta-row stand alone; emit a separate per-row diff entry from inside the loop if granular history matters.

Conventions worth following:

- Always include `entity` in `$infos`. Without it, every plugin row reads as opaque — you can filter by module but not by record kind.
- For state-machine transitions, log the destination state: `{ entity => 'swap_request', decision => 'approved', actor => $borrowernumber }`. The pre-state captured under `FOR UPDATE` for the lock doubles as `$original`.
- For multi-step operations, log once per outcome (success vs failure with the captured error). The cron pattern logs both `NOTICE` and `NOTICE_FAILED` rows so partial runs are diagnosable.

### Audit rejected actions, not just successful ones

Successful mutations are easy to log. Rejections are easier to forget — and they're often what admins actually want to investigate ("why couldn't this user claim the shift?"). Emit a distinct verb for capacity / overlap / closure rejections so they're filterable separately from the audit trail of accepted actions:

```perl
# Lib::Audit (or wherever your conflict helper lives)
sub log_conflict {
    my ( $action, $slot_id, $borrowernumber, $assignment_date, $reason ) = @_;
    return _audit(
        'CONFLICT_REJECTED',
        undef,                    # object_id is undef — the rejected row never gets created
        {   action          => $action,         # 'create' / 'update' / 'bulk_move' / 'self_claim'
            slot_id         => $slot_id,
            borrowernumber  => $borrowernumber,
            assignment_date => $assignment_date,
            reason          => $reason,
        },
    );
}

# Inside the controller, before the 409 render:
sub create {
    # ... validation ...
    if ( my $conflict = _conflict_check(\%row) ) {
        Koha::Plugin::...::Lib::Audit::log_conflict(
            'create', $slot_id, $borrowernumber, $date, $conflict->{error}
        );
        return $c->render(status => 409, openapi => $conflict);
    }
    # ... happy path ...
}
```

Conventions:

- **`object_id` is undef** when the rejected row never made it to the database. The `infos` blob carries the structured context.
- **Distinct verb** (`CONFLICT_REJECTED`, not `CREATE`) so admins can filter the rejected stream separately from the success stream in `viewlog.pl`.
- **Log every rejection path** — capacity, overlap, calendar closure, self-unclaim lockout, swap-not-pending. Each gets a row with the same shape but different `reason`.
- **Same idempotency rules apply** — if a rejection is the canonical signal that "this user attempted X today and was blocked," the row also doubles as a sentinel for [cron rate limits](plugin-cron-idempotency.md).

### Idempotency hook

`action_logs` doubles as an idempotency ledger because it is durable and queryable. The cron pattern in [`plugin-cron-idempotency.md`](plugin-cron-idempotency.md) uses `NOT EXISTS (SELECT 1 FROM action_logs WHERE module='STAFFROSTER' AND action='NOTICE' AND object=a.id AND DATE(timestamp)=CURRENT_DATE())` to skip work already done today. Worth knowing when designing your action verbs — keep them stable so future code can use them as sentinels.

### Where native integration would help

- A `before_plugin_action` / `after_plugin_action` hook so plugins emit a hashref and Koha handles `action_logs` insertion, module naming, and JSON encoding consistently.
- A registry of plugin-defined modules so `viewlog.pl` could surface a friendly label and grouping per plugin instead of a raw module string.
- Standard verbs (`CREATE`/`MODIFY`/`DELETE`/`NOTICE`) shared with core so filters work identically across plugin and core entries.
