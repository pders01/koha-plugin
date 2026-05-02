## Consuming Koha taxonomies and calendar from a plugin

Plugins routinely need to reference Koha-managed concepts: branches, library groups, patron categories, desks, authorised values, the calendar. The Koha modules for each are stable and well documented for in-tree code, but their use from a plugin has a few gotchas around lazy loading, namespace conflicts, and validation. The patterns below cover the common ones.

### `use` at the top, per PERL31

Koha coding guideline PERL31 prefers `use` over `require`. Plugin authors instinctively reach for lazy `require` to keep boot fast on installs that don't touch every helper, but the guideline applies: hoist `use` to the top of the module unless you hit one of the explicit exceptions ("loading modules whose name is known only at runtime" or "fixing circular dependency problems").

`koha-plugin-staff-roster` shipped with lazy `require` everywhere; commit `27b734f` hoisted them all to the top:

```perl
package Koha::Plugin::Xyz::Paulderscheid::StaffRoster;
use Modern::Perl;
use base qw(Koha::Plugins::Base);

# Koha framework deps. C4::Log stays loaded lazily inside _audit (see
# comment on that sub) because the plugin must remain usable on installs
# without it. Everything else is a normal `use`.
use C4::Auth;
use C4::Context;
use C4::Letters;
use Koha::AuthorisedValues;
use Koha::Calendar;
use Koha::DateUtils;
use Koha::Desks;
use Koha::Libraries;
use Koha::Library::Groups;
use Koha::Patron::Categories;
use Koha::Patrons;
use DateTime::Event::ICal;
use DateTime::Format::ICal;
use Mojo::JSON qw( decode_json );
```

Two follow-on rules:

- **Lazy `require` only with a justifying comment** — for `C4::Log` the rationale is "must be loadable on pre-25159 Koha installs that lack the module path." Anywhere else, hoist.
- **Controllers don't `use` the plugin module that loads them** — the plugin loads `Koha::Plugins`, and the plugin runner loads the controllers. Top-of-controller `use Koha::Plugin::...` works because the main plugin module doesn't reciprocally `use` the controllers — no cycle. The staff-roster controllers do exactly this.

Examples in the rest of this doc still use `require` for the helpers themselves because the surrounding context is a method body, not a module top-level — the `require` there is a no-op once the module's been loaded once via `use` at the top of the calling plugin.

```perl
sub _validate_location {
    my ( $self, $location ) = @_;
    require Koha::AuthorisedValues;
    return Koha::AuthorisedValues->search({
        category         => 'STAFFROSTER_LOCATION',
        authorised_value => $location,
    })->count;
}
```

The `require` runs once per process; subsequent calls are free. This also makes the plugin loadable on installs missing the module (very old Koha, partial test environments).

### Authorised values

Two flavours:

- **Open consumption** — read AVs to populate dropdowns. No validation; the user picks from whatever exists.
- **Gated input** — the plugin restricts a column to entries from a chosen AV category. Validate on save; reject otherwise.

```perl
# Render dropdown options
require Koha::AuthorisedValues;
my @locations = Koha::AuthorisedValues->search(
    { category => $self->retrieve_data('authorised_value_location_category') || 'STAFFROSTER_LOCATION' },
    { order_by => 'lib' },
)->as_list;
$template->param( location_options => \@locations );

# Validate on save
if ( $self->retrieve_data('use_authorised_value_locations') && length $location ) {
    my $cat   = $self->retrieve_data('authorised_value_location_category') || 'STAFFROSTER_LOCATION';
    require Koha::AuthorisedValues;
    my $match = Koha::AuthorisedValues->search(
        { category => $cat, authorised_value => $location } )->count;
    if ( !$match ) {
        push @{$messages}, { type => 'danger', code => 'slot_location_not_in_av',
                             value => $location, category => $cat };
        return;
    }
}
```

Make the category configurable. Sites already use AV categories for their own needs; hardcoding `STAFFROSTER_LOCATION` works only if every install creates exactly that category.

### Patron categories and desks

`Koha::Patron::Categories` and `Koha::Desks` follow the same shape:

```perl
sub _staff_categorycodes {
    my ($self) = @_;
    require Koha::Patron::Categories;
    my $cats = Koha::Patron::Categories->search(
        { category_type => 'S' },             # 'S' = staff
        { order_by      => 'description' },
    );
    return [ $cats->get_column('categorycode') ];
}

# Branch-scoped desks
require Koha::Desks;
my @desks = Koha::Desks->search(
    { branchcode => $roster->{branch_id} },
    { order_by => 'desk_name' },
)->as_list;
```

Always filter desks by branchcode in branch-scoped UIs — the global desk list is meaningless to a single branch.

### Library groups

`Koha::Library::Groups` is a tree. Flatten it for a select dropdown that shows depth via indentation:

```perl
sub _flatten_groups {
    my ( $groups, $depth ) = @_;
    my @flat;
    for my $g ( @{$groups} ) {
        push @flat, {
            id    => $g->id,
            title => ( '— ' x $depth ) . $g->title,
            depth => $depth,
        };
        my $children = $g->children;
        if ( $children && $children->count ) {
            push @flat, _flatten_groups( [ $children->as_list ], $depth + 1 );
        }
    }
    return @flat;
}

require Koha::Library::Groups;
my $root_groups = [
    Koha::Library::Groups->search(
        { parent_id => undef },
        { order_by  => 'title' },
    )->as_list
];
my @flat = _flatten_groups( $root_groups, 0 );
```

Resolving a group to its leaf branchcodes (for calendar lookups, visibility checks):

```perl
require Koha::Library::Groups;
my $group = Koha::Library::Groups->find($id) or return ();
my $libs  = $group->libraries;
my @codes = $libs ? $libs->get_column('branchcode') : ();
```

`->libraries` walks the subtree, so a parent group returns every leaf below it.

### The Koha calendar

`Koha::Calendar` answers "is this branch closed on this date." The plugin pattern needs a defensive twist for multi-branch entities (a roster covering a library group, an "all-branches" entity):

```perl
sub _is_closed_for_roster {
    my ( $self, $roster, $date ) = @_;
    return 0 if !$self->retrieve_data('use_koha_calendar');

    my @branches = $self->_branchcodes_for_roster($roster);
    return 0 if !@branches;

    require Koha::Calendar;
    require Koha::DateUtils;
    my $dt = eval { Koha::DateUtils::dt_from_string( $date, 'iso' ) };
    return 0 if !$dt;

    for my $b (@branches) {
        my $cal = Koha::Calendar->new( branchcode => $b );
        return 0 if !$cal->is_holiday($dt);    # any branch open -> roster open
    }
    return 1;
}
```

Decisions worth calling out:

- **"Any branch open" beats "all branches closed."** Closing a roster because one branch in a group is dark is more disruptive than rendering a possibly-stale slot. Pick the conservative side per your domain.
- **Always wrap `dt_from_string` in `eval`.** It dies on malformed input. Plugin endpoints should never propagate that to the user.
- **Cache the `Koha::Calendar` per branchcode** if you call this in a loop over many dates. Construction is cheap but not free — reuse the object across the date range you're checking.
- **Memcached invalidation when seeding holidays.** `Koha::Calendar` memoises the per-branch holiday set in `Koha/Calendar.pm`'s `_holidays` for ~21h. Direct `INSERT INTO special_holidays` is invisible to live Plack workers until the cache key is dropped: `Koha::Caches->get_instance->clear_from_cache("${branchcode}_holidays")`. Plugin code that mutates calendar state via SQL must invalidate; plugin endpoints that mutate via `Koha::Holiday->store` or similar Koha::Object methods get invalidation for free. The same trap surfaces in cypress integration tests — see [`plugin-cypress.md`](plugin-cypress.md) for the per-test flush pattern.

### Identifying the current user

`C4::Context->userenv` is the canonical source. Wrap it once and reuse:

```perl
sub _user_branch {
    my $env = C4::Context->userenv;
    return if !$env || !$env->{number};
    require Koha::Patrons;
    my $patron = Koha::Patrons->find( $env->{number} );
    return $patron ? $patron->branchcode : undef;
}

sub _is_superlib {
    my $env = C4::Context->userenv or return 0;
    my $f = $env->{flags} // 0;
    return $f == 1 || ( $f & 1 ) ? 1 : 0;
}
```

`$env->{branch}` exists too but reflects the session's *current* branch (set by the staff client), not the patron's home branch. Use the right one for the question being asked.

### Pitfalls

| Pitfall | Symptom | Fix |
|---------|---------|-----|
| `use Koha::Foo` at module top | Plugin slow to load, breaks early-boot | `require` inside the helper |
| Hardcoded AV category | Sites with their own taxonomy can't customise | Make it a configurable `retrieve_data` value |
| Unfiltered desks list | Per-branch UI shows desks from other branches | Filter by `branchcode` in the search |
| `dt_from_string` without `eval` | Bad input dies with a 500 | Always wrap and treat undef as "couldn't parse" |
| `Koha::Calendar->new` per date | Heavy in tight loops | Cache by branchcode for the loop's duration |
| `flags == 1` only | Misses the bitmask form of superlibrarian | Test both `$f == 1` and `$f & 1` |

### Where native integration would help

- A `Koha::Plugin::Helpers::*` namespace with the lazy-load + validate variants of the most common Koha lookups (AV, desks, calendar, library groups).
- Per-plugin AV category registration (declare in `PLUGIN.yml`, get an admin UI section automatically, no need to validate by hand).
- A blessed user-context helper that returns a structured `{ borrowernumber, home_branch, current_branch, is_superlibrarian, group_ids }` so plugins stop reaching into `userenv` directly.
