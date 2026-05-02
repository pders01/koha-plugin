# Bug TBD-0011: Add `Koha::Recurrence` shared RFC 5545 helper

## Subject

`Bug TBD: Add Koha::Recurrence module wrapping RFC 5545 RRULE parsing + apply checks`

## Summary

Plugins that need recurrence (staff rosters, recurring holds, recurring bookings, recurring memberships) hand-roll their own RRULE parser and apply-check loop on top of `DateTime::Event::ICal`. Each implementation gets the same fast-path / slow-path split, the same anchor / dtstart resolution problem, and the same warn-on-parse-failure handling. There is no shared module.

This patch introduces `Koha::Recurrence`, a thin OO wrapper around `DateTime::Format::ICal` and `DateTime::Event::ICal` that exposes `parse`, `applies_on`, `next_occurrences`, `serialize`, and `label` methods. Both core (Booking, Recall, Subscription) and plugins consume the same module.

## Coding guideline compliance

- **PERL10** — no `$dbh` in signatures.
- **PERL15** — pure Koha:: namespace, no C4:: refs except `C4::Context` indirectly (none needed).
- **PERL16** — constructor takes `\%params`.
- **PERL26** — bad input raises `Koha::Exceptions::Recurrence::InvalidRule`.

## Rationale

`koha-plugin-staff-roster` ships ~150 lines of RRule code (see `docs/plugin-rrule.md`). Bookings (`Koha::Bookings`) and recalls (`Koha::Recalls`) re-parse iCal strings inline. Subscriptions (`C4::Serials`) maintain a separate predict-next implementation. Centralising:

- Removes drift between plugin and core handling of `BYDAY`, `INTERVAL`, `UNTIL`.
- Lets future iCal additions (BYMONTHDAY, BYSETPOS) ship in one place.
- Keeps the heavy `DateTime::Event::ICal` lazy-load behind a single seam.

## Files touched

- `Koha/Recurrence.pm` — new module.
- `Koha/Exceptions/Recurrence.pm` — new module.
- `t/Koha/Recurrence.t` — coverage.
- Optional follow-ups: refactor `Koha::Bookings`, `Koha::Recalls`, `C4::Serials::predictnextexpected` to call the new module.

## API

```perl
use Koha::Recurrence;

my $r = Koha::Recurrence->new({
    rrule  => 'FREQ=WEEKLY;BYDAY=MO,WE',
    anchor => '2026-01-05',                 # ISO date used as dtstart
});

$r->applies_on('2026-01-12');               # 1
$r->applies_on('2026-01-13');               # 0
$r->next_occurrences({ from => '2026-01-12', count => 4 });
$r->serialize;                               # canonical RRULE string
$r->label;                                   # human-readable summary
```

## Implementation sketch

```perl
package Koha::Recurrence;
use Modern::Perl;
use Koha::Exceptions::Recurrence;

my %ICAL_TO_DOW = ( SU => 0, MO => 1, TU => 2, WE => 3, TH => 4, FR => 5, SA => 6 );
my %DOW_TO_ICAL = reverse %ICAL_TO_DOW;

sub new {
    my ( $class, $params ) = @_;
    my $self = bless { %{ $params // {} } }, $class;
    $self->_parse;
    return $self;
}

sub from_params {
    my ( $class, $params ) = @_;
    return $class->new({
        rrule  => _serialize($params),
        anchor => $params->{anchor},
    });
}

sub _parse {
    my ($self) = @_;
    my %p = ( freq => 'WEEKLY', interval => 1, dows => [], byday_codes => [] );
    if ( my $r = $self->{rrule} ) {
        $p{freq}     = $1 if $r =~ /FREQ=([A-Z]+)/sm;
        $p{interval} = $1 + 0 if $r =~ /INTERVAL=(\d+)/sm;
        $p{until}    = "$1-$2-$3" if $r =~ /UNTIL=(\d{4})(\d{2})(\d{2})/sm;
        if ( $r =~ /BYDAY=([^;]+)/sm ) {
            for my $tok ( split /,/sm, $1 ) {
                next if $tok !~ /^(-?\d+)?([A-Z]{2})$/sm;
                my ( $ord, $code ) = ( $1, $2 );
                next if !defined $ICAL_TO_DOW{$code};
                push @{ $p{dows} },        $ICAL_TO_DOW{$code};
                push @{ $p{byday_codes} }, $code;
                $p{ordinal} = $ord + 0 if defined $ord;
            }
        }
    }
    $self->{parsed} = \%p;
    return;
}

sub applies_on {
    my ( $self, $date ) = @_;
    return 0 if !$self->{rrule} || !$date;
    require Koha::DateUtils;
    my $dt = eval { Koha::DateUtils::dt_from_string( $date, 'iso' ) };
    return 0 if !$dt;

    my $p = $self->{parsed};
    return 0 if !@{ $p->{dows} };

    if ( $p->{freq} eq 'WEEKLY' && $p->{interval} == 1 && !$p->{until} ) {
        my $wday = $dt->day_of_week % 7;
        return scalar grep { $_ == $wday } @{ $p->{dows} };
    }

    require DateTime::Event::ICal;
    require DateTime::Format::ICal;
    my $anchor = eval { Koha::DateUtils::dt_from_string( $self->{anchor} // $date, 'iso' ) };
    $anchor //= $dt->clone;
    $anchor->truncate( to => 'day' );

    my $set = eval {
        DateTime::Format::ICal->parse_recurrence(
            recurrence => $self->{rrule},
            dtstart    => $anchor,
        );
    };
    if ( !$set ) {
        warn "Koha::Recurrence: parse failed for '" . $self->{rrule} . "': " . ( $@ // 'unknown' );
        return 0;
    }
    return $set->contains( $dt->clone->truncate( to => 'day' ) ) ? 1 : 0;
}

sub label { ... }            # human-readable summary
sub serialize { return $_[0]->{rrule}; }
sub next_occurrences { ... }
```

## Test plan

1. Apply the patch.
2. Run `t/Koha/Recurrence.t`. New cases:
   - Plain weekly: `FREQ=WEEKLY;BYDAY=MO,WE` matches Mondays and Wednesdays, misses other days.
   - Interval > 1: `FREQ=WEEKLY;INTERVAL=2;BYDAY=TU` — only every other Tuesday from the anchor.
   - Monthly with ordinal: `FREQ=MONTHLY;BYDAY=1MO` — only first Monday of each month.
   - UNTIL: matches before the date, misses after.
   - Empty BYDAY: returns 0 / does not throw.
   - Malformed RRULE: warns + returns 0 / does not die.
   - `anchor` defaults to the check date when omitted (preserves backward-compat for plain weekly INTERVAL=1).
3. Refactor a plugin currently parsing RRULE inline (e.g. staff-roster) to call `Koha::Recurrence`. Confirm week views render identically.
4. Verify `Koha::Bookings`, `Koha::Recalls` continue to behave the same after the optional follow-up refactor (regression coverage).

## Plugin-side example

```perl
require Koha::Recurrence;

sub _slot_applies_on {
    my ( $rrule, $date, $anchor ) = @_;
    return Koha::Recurrence->new({ rrule => $rrule, anchor => $anchor })->applies_on($date);
}
```

## Cross-references

- Workaround documented in `docs/plugin-rrule.md`.
- Existing implementations to converge on this module: `koha-plugin-staff-roster`, `Koha::Bookings`, `Koha::Recalls`, `C4::Serials::predictnextexpected`.

## Signed-off-by

(to be filled in during review)
