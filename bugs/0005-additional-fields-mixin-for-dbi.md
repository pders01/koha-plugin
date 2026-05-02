# Bug TBD-0005: Expose `Koha::Object::Mixin::AdditionalFields` to plain DBI consumers

## Subject

`Bug TBD: Expose AdditionalFields mixin via Koha::AdditionalFields::for_table helper`

## Summary

Plugins can already opt into the full `Koha::Object` path by generating a DBIx::Class schema (`update_dbix_class_files.pl`), registering it via `Koha::Schema->register_class` + `Koha::Database->schema({ new => 1 })` in a `BEGIN` block, and writing `Koha::*` wrapper classes — once that's done the existing mixin works unchanged. The KohaAdvent 2020-12-07 post documents this route. The gap addressed here is for plugins that *don't* take that route: those keeping their tables on raw DBI cannot inherit `Koha::Object::Mixin::AdditionalFields` (no `Koha::Object` instance, no `result_source`) and end up reimplementing the load / save / delete / bulk-read quartet by hand. This patch exposes the mixin's behaviour through a new helper class `Koha::AdditionalFields::DBI` (entry point: `Koha::AdditionalFields::DBI->for_table($tablename)`), so a raw-DBI plugin gets the same load / save / delete / bulk semantics without registering a schema or subclassing `Koha::Object`.

The helper is **deliberately a separate class**, not a factory on `Koha::AdditionalFields`. `Koha::AdditionalFields` is a `Koha::Objects` subclass — blessing a plain hashref into it would inherit `search`/`find`/`next` without the DBIx::Class `result_source` wiring those methods need, producing instances that die at runtime the moment any inherited method is called. Splitting the helper into its own namespace keeps the `Koha::Objects` consumer surface clean.

## Rationale

Today's `koha-plugin-staff-roster` ships ~120 lines of:

- `_load_additional_fields` — the mixin's `additional_field_values_for_form` shape.
- `_save_additional_fields` — CGI multi-param to map.
- `_save_additional_fields_from_map` — JSON / API map shape.
- `_store_additional_field_values` — atomic delete + reinsert (needs Bug TBD-0003).
- `_delete_additional_fields` — record removal cleanup.
- `_bulk_additional_field_values` — list-view N+1 avoidance.

Every plugin using additional fields copies this. The mixin already does it for `Koha::Object` consumers; exposing the same logic to non-`Koha::Object` callers eliminates the duplication.

## Files touched

- `Koha/AdditionalFields/DBI.pm` — new helper class with `for_table` factory + `load` / `save_from_cgi` / `save_from_map` / `delete_for` / `bulk_for` methods.
- `Koha/Object/Mixin/AdditionalFields.pm` — refactor to use the new helper internally to prevent drift.
- `Koha/AdditionalFields.pm` — unchanged (remains the `Koha::Objects` subclass it is today).
- `t/db_dependent/Koha/AdditionalFields/DBI.t` — coverage for the DBI shape.

## Hook signature

Not a plugin hook — a shared helper. Plugins call:

> Per Koha coding guidelines, helpers reach for `C4::Context->dbh` themselves rather than accepting `$dbh` through the signature. The factory and every method below follow that rule — the caller never threads a database handle through.

```perl
use Koha::AdditionalFields::DBI;

my $af = Koha::AdditionalFields::DBI->for_table('staff_roster');

# Load:
my $data = $af->load($roster_id);   # { available => [...], values => { fid => [...] } }

# Save from CGI:
$af->save_from_cgi($roster_id, $cgi);

# Save from JSON map:
$af->save_from_map($roster_id, { 12 => ['hello'], 13 => 'world' });

# Delete on entity removal:
$af->delete_for($roster_id);

# Bulk for list views:
my $bulk = $af->bulk_for([ map { $_->{id} } @{$rosters} ]);
```

## Implementation sketch

```perl
package Koha::AdditionalFields::DBI;
use Modern::Perl;
use C4::Context;
use Koha::Database;

# Plain class — no Koha::Objects inheritance — so blessing a hashref here
# does not inherit ORM methods (`search`, `find`, `next`, ...) that would
# require a DBIx::Class result_source we have not set up.
sub for_table {
    my ( $class, $tablename ) = @_;
    return bless { tablename => $tablename }, $class;
}

sub load {
    my ( $self, $record_id ) = @_;
    my $dbh = C4::Context->dbh;
    my $available = $dbh->selectall_arrayref(
        q{SELECT id, name, authorised_value_category, marcfield, marcfield_mode, searchable, repeatable
          FROM additional_fields WHERE tablename = ? ORDER BY id},
        { Slice => {} }, $self->{tablename}
    ) || [];
    for my $f ( @{$available} ) {
        $f->{effective_authorised_value_category} = $f->{authorised_value_category};
    }
    my %values;
    if ($record_id) {
        my $rows = $dbh->selectall_arrayref(
            q{SELECT field_id, value FROM additional_field_values
              WHERE record_table = ? AND record_id = ?},
            { Slice => {} }, $self->{tablename}, $record_id
        ) || [];
        push @{ $values{ $_->{field_id} } }, $_->{value} for @{$rows};
    }
    return { available => $available, values => \%values };
}

sub save_from_map {
    my ( $self, $record_id, $map ) = @_;
    return if !$record_id || !$map;
    my $dbh    = C4::Context->dbh;
    my $fields = $dbh->selectall_arrayref(
        q{SELECT id FROM additional_fields WHERE tablename = ?},
        { Slice => {} }, $self->{tablename}
    ) || [];
    my %allowed = map { $_->{id} => 1 } @{$fields};
    my %values_by_id;
    for my $fid ( keys %{$map} ) {
        next if !$allowed{$fid};
        my $v = $map->{$fid};
        $values_by_id{$fid} = ref $v eq 'ARRAY' ? $v : [$v];
    }
    Koha::Database->txn(sub {
        $dbh->do(q{DELETE FROM additional_field_values WHERE record_table = ? AND record_id = ?},
                 undef, $self->{tablename}, $record_id);
        for my $fid ( keys %values_by_id ) {
            for my $v ( @{ $values_by_id{$fid} } ) {
                next if !defined $v || $v eq q{};
                $dbh->do(q{INSERT INTO additional_field_values (field_id, record_table, record_id, value)
                           VALUES (?, ?, ?, ?)},
                         undef, $fid, $self->{tablename}, $record_id, $v);
            }
        }
    });
}

sub save_from_cgi {
    my ( $self, $record_id, $cgi ) = @_;
    my $dbh    = C4::Context->dbh;
    my $fields = $dbh->selectall_arrayref(
        q{SELECT id FROM additional_fields WHERE tablename = ?},
        { Slice => {} }, $self->{tablename}
    ) || [];
    my %map = map { $_->{id} => [ $cgi->multi_param( 'additional_field_' . $_->{id} ) ] } @{$fields};
    return $self->save_from_map( $record_id, \%map );
}
```

## Test plan

1. Apply the patch.
2. Run `t/db_dependent/Koha/AdditionalFields.t`. New cases:
   - `for_table` + `load` returns the mixin's shape (`available` arrayref + `values` hashref).
   - `save_from_map` filters out unknown `field_id`s.
   - `save_from_map` is atomic (forced exception inside the helper leaves prior values intact).
   - `bulk_for` returns one query rather than N+1.
3. Refactor a plugin currently using its own helpers (e.g. staff-roster) to call `Koha::AdditionalFields::DBI->for_table('staff_roster')`. Confirm the create / edit / delete / list-view flows work identically, including the additional-fields-entry.inc include.
4. Confirm `Koha::Object::Mixin::AdditionalFields` continues to work — refactor it to delegate internally and rerun `t/db_dependent/Koha/Patron.t` / `t/db_dependent/Koha/Acquisition/Order.t` (or whatever uses the mixin).

## Plugin-side example

```perl
require Koha::AdditionalFields::DBI;
my $af = Koha::AdditionalFields::DBI->for_table('staff_roster');

sub _save_roster {
    my ($self, $cgi) = @_;
    Koha::Database->txn(sub {
        my $roster_id = _insert_or_update_roster($cgi);
        $af->save_from_cgi($roster_id, $cgi);
    });
}

sub _delete_roster {
    my ($self, $roster_id) = @_;
    $af->delete_for($roster_id);
    C4::Context->dbh->do(q{DELETE FROM staff_roster WHERE id = ?}, undef, $roster_id);
}

sub _list_rosters {
    my ($self) = @_;
    my $rosters = C4::Context->dbh->selectall_arrayref(...);
    my $bulk    = $af->bulk_for( [ map { $_->{id} } @{$rosters} ] );
    # ... merge bulk[record_id][field_id] into the row ...
}
```

## Cross-references

- Workaround documented in `docs/plugin-additional-fields.md`.
- Depends on Bug TBD-0003 (`Koha::Database->txn`) for the atomic delete-then-reinsert.
- Existing mixin: `Koha/Object/Mixin/AdditionalFields.pm`.

## Signed-off-by

(to be filled in during review)
