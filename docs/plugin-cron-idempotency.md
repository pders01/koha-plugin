## Idempotent `cronjob_nightly`

`cronjob_nightly` is invoked from `plugins_nightly.pl`. In real deployments that script gets re-run: a partial failure leaves the operator wanting to retry, the scheduler restarts mid-run, an admin runs it manually after a config change. A naive cron will re-send every reminder each time.

Make plugin cron jobs idempotent on day-of-execution boundaries. Use `action_logs` as the durable ledger — it's already there for [audit purposes](plugin-audit-logging.md), and it survives plugin upgrades.

### Pattern

The reminder body lives in a Koha letter template seeded on install (HTML2: no inline prose in Perl). `cronjob_nightly` fetches the prepared letter via `C4::Letters::GetPreparedLetter`, substitutes per-assignment placeholders, and enqueues. A missing template logs `NOTICE_FAILED` rather than sending an empty body.

```perl
# On install + upgrade — INSERT IGNORE preserves admin-edited copy.
my %NOTICE_TEMPLATES = (
    REMINDER => {
        title   => 'Reminder: roster shift on <<assignment_date>>',
        content => <<'HTML',
Hi <<patron_firstname>>,

Reminder of your upcoming roster shift:

  Roster:   <<roster_name>>
  Date:     <<assignment_date>>
  Time:     <<start_time>> - <<end_time>>
  Location: <<location>>

Thanks.
HTML
    },
);

sub _register_notice_templates {
    my $dbh = C4::Context->dbh;
    for my $code ( sort keys %NOTICE_TEMPLATES ) {
        my $tpl = $NOTICE_TEMPLATES{$code};
        $dbh->do(
            q{INSERT IGNORE INTO letter
                (module, code, branchcode, name, is_html, title, content,
                 message_transport_type, lang)
              VALUES ('STAFFROSTER', ?, '', ?, 0, ?, ?, 'email', 'default')},
            undef, $code, "Staff Roster: $code", $tpl->{title}, $tpl->{content},
        );
    }
    return;
}

# On uninstall — drop the seeded letter rows alongside permissions cleanup.
# DELETE matches module = 'STAFFROSTER'; admin-edited rows are also removed.

sub cronjob_nightly {
    my ($self) = @_;
    return 0 if !$self->retrieve_data('enable_email_reminders');
    my $days = $self->retrieve_data('reminder_days_before') // 1;
    $days = ( $days =~ /^\d+$/sm ) ? int $days : 1;

    my $dbh = C4::Context->dbh;
    # Idempotency: skip assignments where we already have a reminder row in
    # action_logs for STAFFROSTER NOTICE today. Re-running the cron same day
    # (scheduler restart, manual invocation, partial failure) no longer
    # enqueues duplicates.
    my $rows = $dbh->selectall_arrayref(
        q{SELECT a.id, a.borrowernumber, a.assignment_date,
                 s.start_time, s.end_time, s.location,
                 r.name AS roster_name,
                 b.firstname, b.email
            FROM staff_roster_assignments a
            JOIN staff_roster_slots s ON a.slot_id = s.id
            JOIN staff_roster        r ON s.roster_id = r.id
            JOIN borrowers           b ON a.borrowernumber = b.borrowernumber
           WHERE a.assignment_date = DATE_ADD(CURRENT_DATE(), INTERVAL ? DAY)
             AND a.status IN ('scheduled', 'confirmed')
             AND NOT EXISTS (
                 SELECT 1 FROM action_logs al
                  WHERE al.module = 'STAFFROSTER'
                    AND al.action = 'NOTICE'
                    AND al.object = a.id
                    AND DATE(al.timestamp) = CURRENT_DATE()
             )},
        { Slice => {} }, $days
    ) || [];

    my ( $sent, $failed ) = ( 0, 0 );
    for my $a ( @{$rows} ) {
        next if !$a->{email};   # operator-visible warn, then skip
        my $letter = C4::Letters::GetPreparedLetter(
            module                 => 'STAFFROSTER',
            letter_code            => 'REMINDER',
            message_transport_type => 'email',
            substitute             => {
                patron_firstname => $a->{firstname} // q{},
                roster_name      => $a->{roster_name},
                assignment_date  => $a->{assignment_date},
                start_time       => substr( $a->{start_time}, 0, 5 ),
                end_time         => substr( $a->{end_time},   0, 5 ),
                location         => $a->{location} // '(unspecified)',
            },
        );
        if ( !$letter ) {
            $failed++;
            _audit( 'NOTICE_FAILED', $a->{id},
                { entity => 'reminder', borrowernumber => $a->{borrowernumber},
                  error  => 'letter template missing' } );
            next;
        }
        my $message_id = eval {
            C4::Letters::EnqueueLetter({
                letter                 => $letter,
                borrowernumber         => $a->{borrowernumber},
                message_transport_type => 'email',
            });
        };
        if ($message_id) {
            $sent++;
            _audit( 'NOTICE', $a->{id},
                { entity => 'reminder', borrowernumber => $a->{borrowernumber},
                  message_id => $message_id, days_ahead => $days } );
        }
        else {
            $failed++;
            _audit( 'NOTICE_FAILED', $a->{id},
                { entity => 'reminder', borrowernumber => $a->{borrowernumber},
                  error  => "$@" } );
        }
    }
    return wantarray ? ( $sent, $failed ) : $sent;
}
```

Why the letter table:

- **HTML2 / wording-not-in-Perl** — Koha's coding guideline keeps prose out of `.pl` and `.pm`. Site admins edit notices via `tools/letter.pl` without touching the plugin.
- **Branding flows through the same pipeline** — header / footer / branch-specific overrides apply to plugin reminders identically to core notices.
- **Translation flows through `lang`** — sites running `TranslateNotices` get the localised body for free.
- **Substitute tokens** (`<<patron_firstname>>` etc.) survive admin edits — the dispatcher just supplies the same `substitute` hash.

Lifecycle is the same `INSERT IGNORE` upsert pattern used for permissions and message attributes — admin tweaks survive plugin upgrades; uninstall drops the seeded module rows.

### What makes this idempotent

- **Sentinel via `NOT EXISTS`** — the work-list query itself filters out anything already logged today. Re-running the cron picks up only the leftover work.
- **Sentinel granularity matches re-run granularity** — `DATE(al.timestamp) = CURRENT_DATE()` makes "same day" the de-dup window. If your action runs hourly, key on `HOUR(al.timestamp)`. If once-per-event-ever, drop the date predicate entirely.
- **Sentinel write happens only on success** — `_audit('NOTICE', ...)` runs after `EnqueueLetter` returns a non-undef id. A failure writes `NOTICE_FAILED` instead, which doesn't satisfy the `action='NOTICE'` predicate, so the next run retries it.
- **No mutation pre-flight** — checking the ledger before enqueue is enough because enqueue + log are sequential; if the process dies between them, the next run re-enqueues. That is fine for emails (operator-visible duplicate beats silent miss), but for non-idempotent downstream actions (charging cards, calling external APIs) wrap enqueue + log in [`_txn`](plugin-transactions.md) and write the sentinel first inside the txn so a crash leaves the work undone, not double-done.

### Day-boundary considerations

`CURRENT_DATE()` and `DATE(al.timestamp)` both run in the database's session timezone. `plugins_nightly.pl` runs in the cron user's timezone. They are usually aligned in single-region deployments, but in multi-tenant or multi-region installs a UTC-only sentinel is safer:

```sql
AND UTC_DATE() = DATE(CONVERT_TZ(al.timestamp, @@session.time_zone, '+00:00'))
```

For most plugins the simple `DATE(al.timestamp) = CURRENT_DATE()` form is fine — flag it in your README so operators know the assumption.

### Failure visibility

A silent cron is the worst failure mode: nobody knows whether reminders went out. Two cheap mitigations:

- `warn` to STDERR for skip conditions an operator should see (no email on file, malformed config). `plugins_nightly.pl` redirects those to the cron log.
- Log every failure to `action_logs` with a distinct verb (`NOTICE_FAILED`). The error string lives in the JSON `info` blob so admins can grep for patterns without parsing log files.

### Where native integration would help

- A `Koha::Plugin::Cron` base that exposes `mark_done($key)` / `already_done($key)` so plugins don't reinvent the ledger.
- A standardized "since last run" cursor stored against the plugin so jobs key on real intervals, not date arithmetic.
- A failure dashboard that pivots `action_logs` failure verbs into a single view, avoiding plugin-specific naming.
