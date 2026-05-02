## Wiring Koha additional fields to plugin entities

Koha's `additional_fields` / `additional_field_values` machinery lets admins add custom fields to a record type without schema changes. Core wires it up via `Koha::Object::Mixin::AdditionalFields`. Plugins *can* opt into the full `Koha::Object` path — generate a DBIx::Class schema with `update_dbix_class_files.pl`, register it via `Koha::Schema->register_class` + `Koha::Database->schema({ new => 1 })` in a `BEGIN` block, and write `Koha::*` wrapper classes (the [KohaAdvent 2020-12-07 post](https://koha-community.gitlab.io/KohaAdvent/2020-12-07-dbic/) walks through it). The pattern below targets the lighter-weight alternative: plugins that keep their tables on raw DBI and skip the schema-registration dance. Those plugins can't inherit the mixin, but they can still integrate with the same admin UI and storage tables and reuse the staff-side template includes.

### What the user gets

- Admins manage field definitions through the standard `admin/additional-fields.pl` page (deep-link with `?tablename=staff_roster`).
- The plugin's create/edit form renders fields via `additional-fields-entry.inc` — same controls and validation core uses.
- Values are stored in `additional_field_values` keyed by `(record_table, record_id, field_id)`, so the data is portable and queryable from outside the plugin.

### Pattern

When the plugin keeps its tables on raw DBI (no DBIx::Class schema
registered) the `Koha::Object::Mixin::AdditionalFields` route is closed —
the mixin needs a `Koha::Object` instance with a `result_source` to drive
its load / save / delete loop. We do the equivalent reads / writes by
hand. The four helpers below cover load, save (CGI form), save (JSON
map), delete, and a bulk read for list views. Plugins that *do* register
a DBIx::Class schema (per the KohaAdvent 2020-12-07 post linked above)
inherit the mixin directly and skip this section.

Per Koha coding guidelines (see `https://wiki.koha-community.org/wiki/Coding_Guidelines`), helpers reach for `C4::Context->dbh` themselves rather than accepting `$dbh` through the signature. DBI hands out the same connection on each call within a request.

#### Load

```perl
# Returns { available => [field_hash, ...], values => { field_id => [val,..] } }
sub _load_additional_fields {
    my ( $tablename, $record_id ) = @_;
    my $dbh = C4::Context->dbh;
    my $available = $dbh->selectall_arrayref(
        q{SELECT id, name, authorised_value_category, marcfield, marcfield_mode, searchable, repeatable
          FROM additional_fields WHERE tablename = ? ORDER BY id},
        { Slice => {} }, $tablename
    ) || [];

    # The TT include calls $field->effective_authorised_value_category as a
    # method. Wrap each hash so the include works without changes.
    for my $f ( @{$available} ) {
        $f->{effective_authorised_value_category} = $f->{authorised_value_category};
    }

    my %values;
    if ($record_id) {
        my $rows = $dbh->selectall_arrayref(
            q{SELECT field_id, value FROM additional_field_values
              WHERE record_table = ? AND record_id = ?},
            { Slice => {} }, $tablename, $record_id
        ) || [];
        push @{ $values{ $_->{field_id} } }, $_->{value} for @{$rows};
    }
    return { available => $available, values => \%values };
}
```

The hashref shape matters: `additional-fields-entry.inc` reads
`field.id`, `field.name`, `field.repeatable`,
`field.effective_authorised_value_category`, `field.marcfield`,
`field.marcfield_mode`. Do not trim the column list without checking the include.

#### Render in your form template

```html
[% PROCESS 'additional-fields-entry.inc'
   available_fields = additional_fields_available
   values           = additional_fields_values %]
```

Pass the hash from `_load_additional_fields` straight through. The include emits one input per field, named `additional_field_<id>`.

#### Save (form post)

```perl
sub _save_additional_fields {
    my ( $tablename, $record_id, $cgi ) = @_;
    return if !$record_id;
    my $fields = _additional_field_defs($tablename);
    return if !@{$fields};
    my %values_by_id =
        map { $_->{id} => [ $cgi->multi_param( 'additional_field_' . $_->{id} ) ] } @{$fields};
    return _store_additional_field_values( $tablename, $record_id, \%values_by_id );
}
```

`multi_param` is required for repeatable fields — single `param` collapses them.

#### Save (JSON / API)

```perl
# Same as _save_additional_fields but accepts a pre-built map
# { field_id => [values, ...] }. Used by JSON API endpoints.
sub _save_additional_fields_from_map {
    my ( $tablename, $record_id, $map ) = @_;
    return if !$record_id || !$map;
    my $fields = _additional_field_defs($tablename);
    return if !@{$fields};
    my %allowed   = map { $_->{id} => 1 } @{$fields};
    my %values_by_id;
    for my $fid ( keys %{$map} ) {
        next if !$allowed{$fid};
        my $v = $map->{$fid};
        $values_by_id{$fid} = ref $v eq 'ARRAY' ? $v : [$v];
    }
    return _store_additional_field_values( $tablename, $record_id, \%values_by_id );
}
```

Always validate `$fid` against `additional_fields.id` for that tablename. Without the `%allowed` filter, an attacker could write rows for unrelated entities.

#### Atomic delete-then-reinsert

The mixin pattern is "wipe all values, write the new ones." Without a transaction wrapper, a failed insert leaves the record with **no** values — visibly worse than the previous state.

```perl
sub _store_additional_field_values {
    my ( $tablename, $record_id, $values_by_id ) = @_;
    my $dbh = C4::Context->dbh;

    # Wrap delete + reinsert in a single transaction so a failed insert leaves
    # the prior values untouched. The default plack handler runs with
    # AutoCommit=1, so the bare delete-then-loop above could otherwise commit a
    # partial state if any insert blew up.
    my $autocommit_was = $dbh->{AutoCommit};
    $dbh->begin_work if $autocommit_was;
    eval {
        $dbh->do(q{DELETE FROM additional_field_values WHERE record_table = ? AND record_id = ?},
                 undef, $tablename, $record_id);
        for my $fid ( keys %{$values_by_id} ) {
            for my $v ( @{ $values_by_id->{$fid} } ) {
                next if !defined $v || $v eq q{};
                $dbh->do(q{INSERT INTO additional_field_values (field_id, record_table, record_id, value)
                           VALUES (?, ?, ?, ?)},
                         undef, $fid, $tablename, $record_id, $v);
            }
        }
        $dbh->commit if $autocommit_was;
        1;
    } or do {
        my $err = $@ || 'unknown error';
        $dbh->rollback if $autocommit_was;
        die $err;
    };
    return;
}
```

See [`plugin-transactions.md`](plugin-transactions.md) for why this manual `begin_work` / `commit` / `rollback` dance is necessary under Plack's default `AutoCommit=1`.

#### Delete on entity removal

```perl
sub _delete_additional_fields {
    my ( $tablename, $record_id ) = @_;
    return if !$record_id;
    C4::Context->dbh->do(
        q{DELETE FROM additional_field_values WHERE record_table = ? AND record_id = ?},
        undef, $tablename, $record_id);
    return;
}
```

Always call this from your plugin's `_delete_<entity>` handler. Forgotten cleanup leaves orphan rows that resurrect when an id is reused.

#### Bulk read for list views

```perl
# { record_id => { field_id => [vals,...] } } for a list view that wants to
# render every roster's additional field summary in one query.
sub _bulk_additional_field_values {
    my ( $tablename, $record_ids ) = @_;
    return {} if !$record_ids || !@{$record_ids};
    my $dbh          = C4::Context->dbh;
    my $placeholders = join q{,}, ('?') x @{$record_ids};
    my $rows = $dbh->selectall_arrayref(
        qq{SELECT record_id, field_id, value FROM additional_field_values
           WHERE record_table = ? AND record_id IN ($placeholders)},
        { Slice => {} }, $tablename, @{$record_ids}
    ) || [];
    my %out;
    push @{ $out{ $_->{record_id} }{ $_->{field_id} } }, $_->{value} for @{$rows};
    return \%out;
}
```

Folding additional fields into a list view via N+1 queries is the failure mode this avoids — a single `IN (...)` lookup keyed on the page's record ids is enough for normal page sizes.

### Wiring it into save / delete / view paths

```perl
# Inside a save handler
_txn(sub {
    my $dbh = C4::Context->dbh;
    $dbh->do(q{INSERT/UPDATE staff_roster ...});
    _save_additional_fields( 'staff_roster', $roster_id, $cgi );
});

# Inside a delete handler — drop the values BEFORE the parent row to avoid
# orphans even if the parent delete fails midway.
_delete_additional_fields( 'staff_roster', $roster_id );
C4::Context->dbh->do(q{DELETE FROM staff_roster WHERE id = ?}, undef, $roster_id);

# Inside the list view
my $dbh     = C4::Context->dbh;
my $rosters = $dbh->selectall_arrayref(...);
my $defs    = $dbh->selectall_arrayref(
    q{SELECT id, name FROM additional_fields WHERE tablename = ? ORDER BY id},
    { Slice => {} }, 'staff_roster'
);
my $bulk = _bulk_additional_field_values( 'staff_roster', [ map { $_->{id} } @{$rosters} ] );
for my $r ( @{$rosters} ) {
    $r->{additional_field_summary} = [
        map  { { name => $_->{name}, values => $bulk->{ $r->{id} }{ $_->{id} } || [] } }
        grep { $bulk->{ $r->{id} }{ $_->{id} } && @{ $bulk->{ $r->{id} }{ $_->{id} } } }
             @{$defs}
    ];
}
```

### Pitfalls

| Pitfall | Symptom | Fix |
|---------|---------|-----|
| Forget `multi_param` for repeatable fields | Only the last value is saved | Use `multi_param` (CGI) or coerce to arrayref (JSON) |
| Skip `%allowed` filter in API save | Caller writes rows for any tablename | Validate `$fid` against `additional_fields.id WHERE tablename = ?` |
| No transaction around delete-then-reinsert | Failed insert wipes existing values | Wrap in `begin_work` / `commit` / `rollback` |
| Forget delete in entity-removal handler | Orphan rows resurrect on id reuse | Call `_delete_additional_fields` first |
| Drop `effective_authorised_value_category` | Include throws "no such method" | Mirror it from `authorised_value_category` |

### Where native integration would help

- `Koha::Object::Mixin::AdditionalFields` extended to raw-DBI consumers (plugins that haven't registered a DBIx::Class schema) via a documented helper class that takes `($tablename, $record_id)` and reaches for `C4::Context->dbh` internally.
- A scaffold helper that emits the full save / load / delete / bulk-read quartet so plugins don't copy-paste it.
- A shared API contract for "save-from-map" so JSON endpoints can reuse the same validator instead of writing the `%allowed` filter by hand.
