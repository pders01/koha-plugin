## Atomic multi-statement work in plugins

Plack's `$dbh` runs with `AutoCommit=1`. Every `$dbh->do` commits on its own. A handler that does several related writes will commit them one at a time, so a failure midway through leaves the database in a partial state — a torn write.

A plugin that does any non-trivial mutation (parent + children, ledger + cache, swap of two rows, delete-then-reinsert) must wrap related work in an explicit transaction. Koha core doesn't expose a helper for this; plugins implement their own.

### `_txn` helper

```perl
# Run $code inside a transaction. Plack's $dbh defaults to AutoCommit=1, so
# any handler that does several related $dbh->do calls risks a torn write
# (one row committed, the next throws). Wrap the related work in this and
# the helper rolls everything back on error. Returns whatever $code returns.
#
# Per Koha coding guidelines, helpers reinstantiate $dbh via
# C4::Context->dbh rather than accepting it as a parameter.
sub _txn {
    my ($code) = @_;
    my $dbh = C4::Context->dbh;
    my $autocommit_was = $dbh->{AutoCommit};
    $dbh->begin_work if $autocommit_was;
    my @result;
    my $rv = eval {
        @result = wantarray ? $code->() : ( scalar $code->() );
        $dbh->commit if $autocommit_was;
        1;
    };
    if ( !$rv ) {
        my $err = $@ || 'unknown';
        eval { $dbh->rollback } if $autocommit_was;
        die $err;
    }
    return wantarray ? @result : $result[0];
}
```

Why each part exists:

- **`$autocommit_was` capture** — the helper must be re-entrant. If something further up the stack already opened a transaction, `begin_work` would throw "Already in a transaction". Skipping `begin_work`/`commit`/`rollback` when AutoCommit is already off lets nested calls participate in the outer transaction.
- **`wantarray` plumbing** — preserves list vs scalar context so callers can keep their normal return shape. Without it, every `_txn` callsite forces scalar context.
- **`eval` around `rollback`** — if the connection died, `rollback` will throw too. Swallowing the rollback error keeps the original failure as the surfaced cause.
- **Re-`die` on failure** — propagates the original exception so callers can pattern-match on it (`if ($err =~ /swap_no_longer_pending/)`).

### Locking inside the transaction

Wrapping in `_txn` solves "all-or-nothing". It does not solve TOCTOU. For state-machine transitions, re-read the row under `FOR UPDATE` inside the txn so concurrent approvers serialize:

```perl
_txn(
    sub {
        my $dbh = C4::Context->dbh;
        my ($current_status) = $dbh->selectrow_array(
            q{SELECT status FROM staff_roster_swap_requests WHERE id = ? FOR UPDATE},
            undef, $swap_id
        );
        die "swap_no_longer_pending\n" if !$current_status || $current_status ne 'pending';

        # Capture from_borrower BEFORE mutating the from_assignment so a
        # later mutual update doesn't pick up the just-written value.
        my $from_borrower;
        if ( $swap->{to_assignment_id} ) {
            ($from_borrower) = $dbh->selectrow_array(
                q{SELECT borrowernumber FROM staff_roster_assignments WHERE id = ?},
                undef, $swap->{from_assignment_id}
            );
        }
        $dbh->do(q{UPDATE staff_roster_assignments SET borrowernumber = ?, updated_at = NOW() WHERE id = ?},
                 undef, $swap->{to_borrowernumber}, $swap->{from_assignment_id});
        if ( $swap->{to_assignment_id} && $from_borrower ) {
            $dbh->do(q{UPDATE staff_roster_assignments SET borrowernumber = ?, updated_at = NOW() WHERE id = ?},
                     undef, $from_borrower, $swap->{to_assignment_id});
        }
        $dbh->do(q{UPDATE staff_roster_swap_requests SET status=?, response_message=?, responded_at=NOW(), updated_at=NOW() WHERE id=?},
                 undef, $new_status, $response, $swap_id);
    }
);
```

Two TOCTOU subtleties this captures:

- **Re-read status under the lock.** A check before `_txn` would race with another approver. The `SELECT ... FOR UPDATE` inside the txn closes that window: only one transaction holds the lock at a time, the loser sees `approved` and aborts.
- **Capture sibling state before mutating.** Mutual swaps swap two assignments. If the first `UPDATE` ran before the second `SELECT`, the second swap would copy the freshly-written value back onto itself. Always read every value you need before issuing the writes that overwrite them.

### Where to wrap

Use `_txn` whenever a single user action requires more than one write that must commit together:

- Parent + children: roster save + additional field values, slot save + assignment regeneration.
- Two-sided swaps: two assignments + a swap-request row.
- Delete + reinsert: the `additional_field_values` save path deletes then re-inserts; without a txn a failed insert would leave the entity with no values at all.
- Multi-row ledger writes that must all land or none.

Skip it for single-statement mutations. Wrapping a single `do` adds churn without protection.

### Where native integration would help

- A core `Koha::Database->txn(\&code)` (or equivalent) so plugins, core, and `Koha::Object` callers all serialize through the same helper.
- AutoCommit=0 by default for plugin entrypoints, with explicit checkpoints.
- A documented contract that controllers nest cleanly so plugins don't have to write the `$autocommit_was` dance themselves.
