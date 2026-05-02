# Bug TBD-0002: Add `plugin_module` registration + `log_action` helper for action_logs

## Subject

`Bug TBD: Add plugin_module hook + log_action helper using ACTN1 JSON Diff`

## Summary

Plugins audit their mutations by writing to `action_logs` directly under a module name they pick (`STAFFROSTER`, `MYPLUGIN`, …). This patch:

1. Adds a `plugin_module` hook so a plugin declares its action_logs module code, friendly label, and supported verbs.
2. Adds a `Koha::Plugins::Base->log_action(\%params)` helper that writes through `C4::Log::logaction` using ACTN1's JSON Diff format (`$infos` + `$original`).
3. Teaches `tools/viewlog.pl` to render the friendly label and group plugin entries together in the module filter.

The result: a plugin emits a structured payload, Koha handles `action_logs` insertion, JSON encoding, and `viewlog.pl` rendering. No more `eval { require C4::Log; ... }` boilerplate per plugin.

## Coding guideline compliance

- **ACTN1** — `log_action` calls `logaction($module, $action, $object, $infos, $interface, $original)` so `viewlog.pl` can render the JSON Diff.
- **PERL10** — helper takes no `$dbh`; reaches for `C4::Context->dbh` only when needed (lookup of `plugin_module` cache).
- **PERL16** — multi-arg helper accepts a hashref.
- **PERL30** — `Koha::Plugins->call('plugin_module', \%params)` passes a reference so the chain composes.

## Rationale

Every plugin doing audit today re-implements the same `_audit` helper (lazy `require C4::Log`, eval-swallow, hashref into the JSON `info` blob). The shape is identical across plugins; only the module name differs. ACTN1 (Bug 25159) requires JSON Diff format with `$original` for new core code — `koha-plugin-staff-roster` already follows ACTN1 in commits `1540283` and `65c03a2` (snapshot pre-state, fetch-then-delete, pass `$original` to `logaction` as the 6th argument), so the plugin-side contract is established.

What's still missing in core:

1. The `plugin_module` registration so `tools/viewlog.pl` shows a friendly label and groups plugin modules together in the filter dropdown.
2. A blessed `log_action` helper so plugins stop hand-rolling the lazy-require + eval-swallow.
3. A documented contract for the `$infos` / `$original` shape so reviewers don't have to read each plugin's `_audit` to understand its diffs.

## Files touched

- `Koha/Plugins/Base.pm` — add `log_action` method.
- `Koha/Plugins.pm` — read registered modules via `plugin_module` hook for `viewlog.pl`.
- `tools/viewlog.pl` + `koha-tmpl/intranet-tmpl/prog/en/modules/tools/viewlog.tt` — render the friendly label from registered plugin modules.
- `t/db_dependent/Koha/Plugins/log_action.t` — coverage.

## Hook signature

```perl
# Plugin-side: declare the module once.
sub plugin_module {
    my ($self) = @_;
    return {
        code  => 'STAFFROSTER',                                   # action_logs.module
        label => 'Staff Roster',                                  # viewlog UI label
        verbs => [qw( CREATE MODIFY DELETE NOTICE NOTICE_FAILED )],
    };
}

# Plugin-side contract: always pass `before` (pre-mutation) and `after`
# (post-mutation) hashrefs / Koha::Objects. The helper normalises them
# into the positional shape `C4::Log::logaction` expects, which differs
# per verb (see "Diff contract" below).
$self->log_action({
    action    => 'MODIFY',
    object    => $roster_id,
    before    => $roster_before,         # pre-mutation snapshot
    after     => $roster_after,          # post-mutation snapshot
    interface => 'intranet',             # optional; defaults to C4::Context->interface
    extra     => { actor => $borrower }, # optional; merged into action_logs.info as JSON
});
```

## Diff contract

`C4::Log::logaction` reads its 4th positional arg (`$infos`) and 6th positional arg (`$original`) differently depending on the action verb (see `C4/Log.pm` lines 85–156). The `log_action` helper hides this so plugin authors always pass `before` / `after` and never have to remember which slot a verb expects:

| Verb            | What core's `logaction` does              | What `log_action` forwards as 4th arg | What it forwards as 6th arg |
|-----------------|-------------------------------------------|---------------------------------------|-----------------------------|
| `CREATE`/`ADD`  | Forces `$original = {}`; uses 6th arg as the new row | `extra` (or `after` if no `extra`)    | `after`                     |
| `MODIFY`        | Diffs 6th arg vs 4th arg                  | `after`                               | `before`                    |
| `DELETE`        | Forces `$updated = {}`; uses 6th arg as the deleted row | `extra` (or `before` if no `extra`) | `before` |
| `NOTICE` etc.   | No diff computed (`$original` undef ⇒ skip) | `extra` (or `after`)                | `undef`                     |

The result lands in `action_logs.diff` for `CREATE`/`MODIFY`/`DELETE` (full body for create/delete, change-only for modify) and in `action_logs.info` for the JSON-encoded `extra`. Plugin authors never see the swap.

## Implementation sketch

```perl
# Koha/Plugins/Base.pm
sub log_action {
    my ( $self, $params ) = @_;
    return if !$params || !$params->{action};

    my $meta   = $self->plugin_module;
    my $module = ( ref $meta eq 'HASH' && $meta->{code} ) ? $meta->{code} : $self->{class};

    my $action = $params->{action};
    my $before = $params->{before};
    my $after  = $params->{after};
    my $extra  = $params->{extra};

    # Normalise `before`/`after` into the positional slots logaction expects.
    my ( $infos_pos, $original_pos );
    if ( $action =~ /^(ADD|CREATE)$/ ) {
        $infos_pos    = $extra // $after;
        $original_pos = $after;
    } elsif ( $action eq 'DELETE' ) {
        $infos_pos    = $extra // $before;
        $original_pos = $before;
    } else {
        $infos_pos    = $extra // $after;
        $original_pos = $before;
    }

    require C4::Log;
    eval {
        C4::Log::logaction(
            $module,
            $action,
            $params->{object},
            $infos_pos,
            $params->{interface},
            $original_pos,
        );
        1;
    };
    return;
}
```

`viewlog.pl` consults the `plugin_module` hook to populate the module filter:

```perl
# tools/viewlog.pl
my @plugin_modules;
if ( C4::Context->config('enable_plugins') ) {
    for my $plugin ( Koha::Plugins->new->GetPlugins({ method => 'plugin_module' }) ) {
        try {
            my $m = $plugin->plugin_module or next;
            push @plugin_modules, { code => $m->{code}, label => $m->{label}, verbs => $m->{verbs} };
        }
        catch { warn "Error calling 'plugin_module' on " . $plugin->{class} . " ($_)"; };
    }
}
$template->param( plugin_modules => \@plugin_modules );
```

## Test plan

1. Apply the patch.
2. Enable plugins in `koha-conf.xml`.
3. Install a plugin that implements `plugin_module` and triggers `$self->log_action({ action => 'CREATE', object => $id, before => undef, after => $obj_after })` on a save.
4. Trigger a CREATE / MODIFY / DELETE in the plugin UI.
5. Open `tools/viewlog.pl`. Confirm:
   - Module filter shows the friendly label ("Staff Roster"), not the raw code.
   - Filter selection works and only the plugin's rows surface.
   - The diff column renders the JSON Diff between `before` and `after` in ACTN1's standard shape (full new body for `CREATE`, change-only for `MODIFY`, full deleted body for `DELETE`).
6. Pass an `interface` value (`'opac'`, `'intranet'`, `'cron'`). Confirm it lands in `action_logs.interface`.
7. Uninstall the plugin. Existing rows remain (history); the module disappears from the filter dropdown.
8. Reinstall the plugin. Module entry returns; historical rows surface again under the same filter.

## Plugin-side example

```perl
sub plugin_module {
    return {
        code  => 'STAFFROSTER',
        label => 'Staff Roster',
        verbs => [qw( CREATE MODIFY DELETE NOTICE NOTICE_FAILED )],
    };
}

sub _save_assignment {
    my ( $self, $params ) = @_;
    my $before = $params->{original_assignment};   # cloned before mutation
    # ... save ...
    $self->log_action({
        action    => $before ? 'MODIFY' : 'CREATE',
        object    => $assignment_id,
        before    => $before,
        after     => $assignment_after,
        interface => 'intranet',
    });
}
```

## Cross-references

- Workaround currently documented in `docs/plugin-audit-logging.md`.
- ACTN1 already followed plugin-side (staff-roster `1540283`, `65c03a2`); this bug closes the gap on the core / `viewlog.pl` side.
- ACTN1 (Bug 25159): `https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=25159`.
- Composes with Bug TBD-0004 (cron idempotency) — `log_action` becomes the canonical sentinel writer.
- Same dispatcher shape as Bug 39870 (`notices_content`) and Bug 40972 (`xslt_record_processor_filters`).

## Signed-off-by

(to be filled in during review)
