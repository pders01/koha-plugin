# Bug TBD-0004: Add `Koha::Plugin::Cron` base for idempotent cron jobs

## Subject

`Bug TBD: Add Koha::Plugin::Cron base with mark_done / already_done helpers`

## Summary

`cronjob_nightly` is invoked from `plugins_nightly.pl` and frequently re-run (scheduler restart, manual invocation, partial failure). Plugins implement idempotency by hand using `action_logs` as a sentinel ledger. This patch adds a `Koha::Plugin::Cron` base class with `mark_done($key)` / `already_done($key)` helpers backed by `action_logs`, so plugins stop reinventing the ledger.

## Rationale

Today's pattern:

```sql
AND NOT EXISTS (
    SELECT 1 FROM action_logs al
    WHERE al.module = 'STAFFROSTER'
      AND al.action = 'NOTICE'
      AND al.object = a.id
      AND DATE(al.timestamp) = CURRENT_DATE()
)
```

Every plugin doing reminders / nightly notifications copies this. Same module string, same verb convention, same date-key trick. A small base class makes it declarative.

## Files touched

- `Koha/Plugin/Cron.pm` — new base class.
- `Koha/Plugins.pm` — recognize `Koha::Plugin::Cron` instances in `plugins_nightly.pl` orchestration.
- Optional: `misc/plugins_nightly.pl` reports per-plugin success / failure counts using the new helper.

## Implementation sketch

```perl
package Koha::Plugin::Cron;
use Modern::Perl;
use parent 'Koha::Plugins::Base';
use C4::Context;

# Has this (module, key) already been logged within the same idempotency window?
# Defaults to a calendar-day window via DATE(); pass a different window key
# if your cron runs more or less than daily.
sub already_done {
    my ( $self, $key, %opts ) = @_;
    my $module = $self->plugin_module->{code};   # see Bug TBD-0002
    my $window = $opts{window} // 'day';         # 'day', 'hour', 'forever'
    my $dbh    = C4::Context->dbh;
    my $sql    = q{SELECT 1 FROM action_logs WHERE module = ? AND action = ? AND object = ?};
    if ( $window eq 'day' )   { $sql .= q{ AND DATE(timestamp) = CURRENT_DATE()}; }
    if ( $window eq 'hour' )  { $sql .= q{ AND timestamp >= DATE_SUB(NOW(), INTERVAL 1 HOUR)}; }
    return $dbh->selectrow_array($sql, undef, $module, 'CRON_DONE', $key) ? 1 : 0;
}

sub mark_done {
    my ( $self, $key, $info ) = @_;
    # log_action takes a hashref per Bug TBD-0002 (PERL16). For cron sentinels
    # there is no pre/post state — we only need the verb + key + payload, so
    # `extra` carries the structured payload and `before` / `after` stay undef.
    $self->log_action({
        action => 'CRON_DONE',
        object => $key,
        extra  => $info // {},
    });
    return;
}

sub mark_failed {
    my ( $self, $key, $err ) = @_;
    $self->log_action({
        action => 'CRON_FAILED',
        object => $key,
        extra  => { error => "$err" },
    });
    return;
}
```

## Test plan

1. Apply the patch.
2. Install a plugin that extends `Koha::Plugin::Cron` and implements `cronjob_nightly`:
   ```perl
   sub cronjob_nightly {
       my ($self) = @_;
       for my $row ( @{ $self->_pending_rows } ) {
           next if $self->already_done( $row->{id} );
           eval { $self->_send_email($row); $self->mark_done($row->{id}); 1 }
               or $self->mark_failed( $row->{id}, $@ );
       }
   }
   ```
3. Run `misc/plugins_nightly.pl` once. Confirm each row triggers a `CRON_DONE` row in `action_logs`.
4. Run `misc/plugins_nightly.pl` a second time on the same calendar day. Confirm zero new sends.
5. Force a row to fail (e.g. invalid email). Confirm a `CRON_FAILED` row is written and re-running the cron retries the row (because `CRON_FAILED` doesn't satisfy `already_done`).
6. Wait until the next calendar day (or fake `CURRENT_DATE`). Confirm the row sends again.
7. Override `window => 'hour'` in `already_done`. Confirm the helper now de-dupes per hour rather than per day.

## Plugin-side example

```perl
package Koha::Plugin::Com::Example::ReminderPlugin;
use parent 'Koha::Plugin::Cron';

sub cronjob_nightly {
    my ($self) = @_;
    my ( $sent, $failed ) = ( 0, 0 );
    for my $reminder ( @{ $self->_pending_reminders } ) {
        next if $self->already_done( $reminder->{id} );
        my $ok = eval { $self->_enqueue_letter($reminder); 1 };
        if ($ok) { $self->mark_done( $reminder->{id} ); $sent++; }
        else     { $self->mark_failed( $reminder->{id}, $@ ); $failed++; }
    }
    return wantarray ? ( $sent, $failed ) : $sent;
}
```

## Cross-references

- Workaround documented in `docs/plugin-cron-idempotency.md`.
- Depends on Bug TBD-0002 for `log_action` and `plugin_module->{code}`.
- Same lifecycle as Bug 41684 (notices_content + `get_enabled_plugins`).

## Signed-off-by

(to be filled in during review)
