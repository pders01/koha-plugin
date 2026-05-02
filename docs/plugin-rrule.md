## RRule recurrence in plugins

Koha has no shared recurrence engine. Plugins that need "every Monday", "every other week", "first Tuesday of month", "until 2026-12-31" implement their own. Hand-rolling weekday bitmasks is the path of least resistance — and the path most likely to break the moment a customer asks for "every other Monday."

The pattern below stores recurrence as RFC 5545 `RRULE` strings, so the data is portable, parseable by any iCalendar tool, and amenable to upgrades without schema changes. It ships in `koha-plugin-staff-roster`.

### What's supported

A subset of RFC 5545 that covers the common library scheduling cases:

| Component | Values | Example |
|-----------|--------|---------|
| `FREQ` | `WEEKLY` (default), `MONTHLY` | `FREQ=WEEKLY` |
| `BYDAY` | Comma-separated day codes; ordinal prefix on monthly | `BYDAY=MO,WE,FR` or `BYDAY=1MO,3MO` |
| `INTERVAL` | Positive int; omitted unless > 1 | `INTERVAL=2` |
| `UNTIL` | UTC end-of-day timestamp | `UNTIL=20261231T235959Z` |

Day codes: `SU MO TU WE TH FR SA` (iCal convention). Mapped 0..6 with Sunday = 0 (Perl/JS `localtime` convention) when the rest of the plugin uses ints.

Examples:

- `FREQ=WEEKLY;BYDAY=MO,WE` — Mon and Wed every week.
- `FREQ=WEEKLY;INTERVAL=2;BYDAY=TU` — every other Tuesday.
- `FREQ=MONTHLY;BYDAY=1MO,3MO` — first and third Monday of each month.
- `FREQ=MONTHLY;BYDAY=-1FR;UNTIL=20260831T235959Z` — last Friday of the month, until end of August 2026.

### Build from form input

UI forms send a structured shape (frequency, weekday checkboxes, ordinal, interval, until). Convert to RRULE on save:

```perl
my %ICAL_TO_DOW = ( SU => 0, MO => 1, TU => 2, WE => 3, TH => 4, FR => 5, SA => 6 );
my %DOW_TO_ICAL = reverse %ICAL_TO_DOW;

sub _rrule_from_params {
    my (%p)  = @_;
    my $freq = $p{freq} || 'WEEKLY';
    my @dows = @{ $p{dows} || [] };
    return q{} if !@dows;
    my @codes = grep { defined } map { $DOW_TO_ICAL{$_} } @dows;
    return q{} if !@codes;
    if ( $freq eq 'MONTHLY' && defined $p{ordinal} && $p{ordinal} != 0 ) {
        my $ord = int $p{ordinal};
        @codes = map { "$ord$_" } @codes;
    }
    my @parts = ("FREQ=$freq");
    push @parts, "INTERVAL=$p{interval}" if $p{interval} && $p{interval} > 1;
    push @parts, 'BYDAY=' . join q{,}, @codes;
    if ( $p{until_date} && $p{until_date} =~ /^(\d{4})-(\d{2})-(\d{2})$/ ) {
        push @parts, "UNTIL=$1$2${3}T235959Z";
    }
    return join q{;}, @parts;
}
```

Two design decisions worth keeping:

- **Empty `dows` returns empty string.** Save handlers treat empty as a validation error; storing `FREQ=WEEKLY` with no `BYDAY` yields a rule that never applies.
- **`INTERVAL=1` is omitted.** Every iCal serializer canonicalises this way; persisting `INTERVAL=1` causes diff churn between save / re-render cycles.

### Parse for UI prefill and validation

Always return the same shape, with sane defaults, so the caller can treat parse failures as "weekly with no days" instead of branching on undef:

```perl
sub _parsed_rrule {
    my ($rrule) = @_;
    my %out = (
        freq        => 'WEEKLY',
        interval    => 1,
        dows        => [],
        byday_codes => [],
        ordinal     => undef,
        until_date  => undef,
    );
    return \%out if !$rrule;
    if ( $rrule =~ /FREQ=([A-Z]+)/sm )                { $out{freq}     = $1; }
    if ( $rrule =~ /INTERVAL=(\d+)/sm )               { $out{interval} = $1 + 0; }
    if ( $rrule =~ /UNTIL=(\d{4})(\d{2})(\d{2})/sm )  { $out{until_date} = "$1-$2-$3"; }
    if ( $rrule =~ /BYDAY=([^;]+)/sm ) {
        my (@dows, @byday_codes, %ord_seen);
        for my $tok ( split /,/sm, $1 ) {
            next if $tok !~ /^(-?\d+)?([A-Z]{2})$/sm;
            my ( $ord, $code ) = ( $1, $2 );
            next if !defined $ICAL_TO_DOW{$code};
            push @dows,        $ICAL_TO_DOW{$code};
            push @byday_codes, $code;
            $ord_seen{$ord} = 1 if defined $ord;
        }
        $out{dows}        = \@dows;
        $out{byday_codes} = \@byday_codes;
        my @ord_list = keys %ord_seen;
        $out{ordinal} = $ord_list[0] + 0 if @ord_list == 1;
    }
    return \%out;
}
```

### Apply-check with a fast path

The hot path for "does this slot apply on this date?" is weekly + INTERVAL=1 + no UNTIL — by far the most common stored rule. The full RFC 5545 evaluator (`DateTime::Event::ICal`) is heavy; load it lazily and skip it for the common case:

```perl
sub _slot_applies_on {
    my ( $rrule, $date, $anchor_iso ) = @_;
    return 0 if !$rrule || !$date;
    require Koha::DateUtils;
    my $dt = eval { Koha::DateUtils::dt_from_string( $date, 'iso' ) };
    return 0 if !$dt;

    my $p = _parsed_rrule($rrule);
    return 0 if !@{ $p->{dows} };

    # Fast path: weekly + INTERVAL=1 + no UNTIL collapses to a weekday match.
    if ( $p->{freq} eq 'WEEKLY' && $p->{interval} == 1 && !$p->{until_date} ) {
        my $wday = $dt->day_of_week % 7;     # 1=Mon..7=Sun -> 0..6 with Sunday=0
        return scalar grep { $_ == $wday } @{ $p->{dows} };
    }

    # Slow path: full RFC 5545 expansion. dtstart matters for INTERVAL>1.
    require DateTime::Event::ICal;
    require DateTime::Format::ICal;
    my $anchor = $anchor_iso
        ? eval { Koha::DateUtils::dt_from_string( $anchor_iso, 'iso' ) }
        : $dt->clone;
    $anchor ||= $dt->clone;
    $anchor->truncate( to => 'day' );

    my $set = eval {
        DateTime::Format::ICal->parse_recurrence(
            recurrence => $rrule,
            dtstart    => $anchor,
        );
    };
    if ( !$set ) {
        # Surface the failure to the plack error log so corrupt RRULEs are
        # noticed rather than silently making slots disappear from every week.
        warn "StaffRoster: RRule parse failed for '$rrule': " . ( $@ || 'unknown' );
        return 0;
    }

    my $check = $dt->clone->truncate( to => 'day' );
    return $set->contains($check) ? 1 : 0;
}
```

Three load-bearing details:

- **Anchor date is the recurrence `dtstart`.** Without it, `INTERVAL>1` is non-deterministic — "every other Monday starting from when?" Use the parent entity's `effective_from` so the answer is stable across requests.
- **`warn` on parse failure.** A silent return = 0 makes broken RRULEs invisible; admins find out only when staff complain that slots disappeared. Log it; the cron error log is good enough.
- **`truncate( to => 'day' )`** on both anchor and check. The recurrence set is keyed on instants; without truncation an `until_date` exactly on the boundary may match or miss depending on time-of-day round-trips.

### Per-date `applies_on_dates` for week APIs

A weekly API endpoint typically iterates the week and calls `_slot_applies_on` per (slot, date) pair. Bake that into the response so the frontend doesn't recompute:

```perl
my $start_dt = Koha::DateUtils::dt_from_string( $week_start, 'iso' );
for my $slot ( @{$slots} ) {
    my $anchor = _slot_anchor($dbh, $slot->{id});
    my %applies;
    for my $i ( 0 .. 6 ) {
        my $iso = $start_dt->clone->add( days => $i )->ymd;
        $applies{$iso} = _slot_applies_on( $slot->{recurrence_rule}, $iso, $anchor ) ? 1 : 0;
    }
    $slot->{applies_on_dates} = \%applies;
}
```

The frontend now picks `slot.applies_on_dates[iso]` for each grid cell. No client-side RRULE library, no surprise discrepancy between server "applies" and client render.

### Human-readable labels

For list views and audit logs:

```perl
sub _rrule_label {
    my ($rrule) = @_;
    my $p       = _parsed_rrule($rrule);
    return q{} if !@{ $p->{dows} };
    my @day_names    = qw( Sunday Monday Tuesday Wednesday Thursday Friday Saturday );
    my $days         = join q{, }, map { substr $day_names[$_], 0, 3 } @{ $p->{dows} };
    my $until_suffix = $p->{until_date} ? " (until $p->{until_date})" : q{};
    if ( $p->{freq} eq 'MONTHLY' ) {
        my %ord_label = ( 1 => '1st', 2 => '2nd', 3 => '3rd', 4 => '4th', -1 => 'Last' );
        my $ord       = $p->{ordinal} ? ( $ord_label{ $p->{ordinal} } || $p->{ordinal} ) : 'Each';
        my $every     = $p->{interval} > 1 ? "Every $p->{interval} months: " : q{};
        return "$every$ord $days of month$until_suffix";
    }
    my $every = $p->{interval} > 1 ? "Every $p->{interval} weeks: " : q{};
    return "$every$days$until_suffix";
}
```

### Pitfalls

| Pitfall | Symptom | Fix |
|---------|---------|-----|
| Persist `INTERVAL=1` | Diff churn on every save | Omit when interval == 1 |
| Skip the anchor date | INTERVAL>1 returns inconsistent answers | Use parent's `effective_from` as `dtstart` |
| Silent parse failure | Slots vanish from week view, no log entry | `warn` from the slow path |
| Storing day-of-week ints | Migrating to monthly recurrence requires schema change | Store RRULE strings from day one |
| `Koha::DateUtils::dt_from_string` without `eval` | Bad input dies | Always wrap; treat undef as "doesn't apply" |
| Empty BYDAY allowed through | Slot saves but never applies | Reject empty in `_rrule_from_params` |

### Where native integration would help

- `Koha::Recurrence` as a first-class module so plugins, holds, recalls, and cron jobs share one RRULE stack instead of each rolling their own.
- A standard Koha-side `applies_on($entity, $date)` that handles anchor lookup automatically.
- Shared label / serializer so the same string renders identically in Koha core, plugin admin pages, and patron-facing notices.
