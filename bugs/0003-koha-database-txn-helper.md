# Bug TBD-0003: Add `Koha::Database->txn(\&code)` re-entrant transaction helper

## Subject

`Bug TBD: Add Koha::Database->txn helper for re-entrant transactions`

## Summary

Plack's `$dbh` runs with `AutoCommit=1` so any `$dbh->do` commits immediately. Multi-statement work currently has to be wrapped by hand in `begin_work` / `commit` / `rollback` with a captured `$autocommit_was` flag to support nesting. Plugins re-implement this dance per-codebase. This patch adds `Koha::Database->txn(\&code)` so plugins, controllers, and `Koha::Object` callers all share one helper.

## Rationale

Three failure modes in the wild:

1. Bare delete-then-insert under AutoCommit=1 wipes existing rows when the insert fails.
2. Hand-written `begin_work` without the `$autocommit_was` capture throws "Already in a transaction" inside nested calls.
3. Locking primitives like `SELECT ... FOR UPDATE` only work if the caller is in a real transaction; without the wrapper they no-op silently.

The helper should be re-entrant, propagate exceptions, and preserve list/scalar context so it can be dropped in around existing code without changing call shape.

## Files touched

- `Koha/Database.pm` — add `txn` method.
- `t/db_dependent/Koha/Database.t` — unit tests for nested + failed transactions.
- Optional follow-up: replace ad-hoc `_txn` helpers in core (e.g. `C4::Reserves`, `Koha::Acquisition::Order`) with the new helper.

## Hook signature

Not a plugin hook — a shared helper. Plugins call it via `Koha::Database->schema->txn(...)` or a thin wrapper.

## Implementation sketch

```perl
# Koha/Database.pm
#
# Critical: must wrap the same $dbh the closure uses for its work. Plugins,
# controllers, and Koha::Object subclasses all reach for $dbh via
# C4::Context->dbh — the cached per-process handle. Koha::Database::dbh()
# (the class function) opens a *fresh* DBI->connect and would leave the
# wrapper begin_work / commit on a different connection than the work
# inside, silently turning the helper into a no-op.
sub txn {
    my ( $class, $code ) = @_;
    require C4::Context;
    my $dbh            = C4::Context->dbh;
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

Equivalent on `DBIx::Class` schema: re-export `txn_do` so callers using `Koha::Database->schema->txn_do` get the same shape. Callers using raw `$dbh` go through `Koha::Database->txn`. Both ultimately wrap `C4::Context->dbh` because `Koha::Database->schema->storage->dbh` shares the same handle in current Koha.

## Test plan

1. Apply the patch.
2. Run `t/db_dependent/Koha/Database.t`. New cases:
   - Single-level transaction commits on success.
   - Single-level transaction rolls back on `die`.
   - Nested transaction: outer `txn` opens, inner `txn` runs without nesting another `begin_work`, both commit on outer success.
   - Nested transaction inner-die: outer rolls back, original `die` propagates.
   - Scalar vs list context preserved through the helper.
3. In a plugin, replace a hand-rolled `_txn` with `Koha::Database->txn(sub { ... })`. Confirm a swap-respond / approve flow that touches three rows (two assignments + one swap-request row) commits as a unit and a forced exception in the middle leaves all three rows untouched.

## Plugin-side example

```perl
require Koha::Database;

sub _approve_swap {
    my ( $self, $swap_id ) = @_;
    Koha::Database->txn(sub {
        my $dbh = C4::Context->dbh;
        my ($status) = $dbh->selectrow_array(
            q{SELECT status FROM staff_roster_swap_requests WHERE id = ? FOR UPDATE},
            undef, $swap_id);
        die "swap_no_longer_pending\n" if $status ne 'pending';
        # ... mutate three rows ...
    });
}
```

## Cross-references

- Workaround documented in `docs/plugin-transactions.md`.
- Required by Bug TBD-0007 (messaging preferences) for delete-then-reinsert of `borrower_message_preferences`.
- Required by Bug TBD-0009 (AdditionalContents merge) for safe content updates.

## Signed-off-by

(to be filled in during review)
