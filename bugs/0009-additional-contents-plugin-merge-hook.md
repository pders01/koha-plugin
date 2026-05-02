# Bug TBD-0009: Add `additional_content` plugin hook merged at `AdditionalContents->get`

## Subject

`Bug TBD: Add additional_content plugin hook for OpacNav / OpacMainUserBlock slots`

## Summary

Templates fetch admin-authored content for named locations (`OpacNav`, `OpacNavRight`, `OpacNavBottom`, `OpacMainUserBlock`, `OpacMySummaryNote`, `opaccredits`, `opacheader`, `OpacCustomSearch`) via:

```html
[% SET OpacNav = AdditionalContents.get( location => "OpacNav", lang => lang, library => branchcode ) %]
```

The location enum is closed; plugins cannot register content for an existing slot programmatically. Sites that want plugin-supplied banners or per-branch promos rely on admins pasting HTML into the staff client by hand.

This patch adds an `additional_content` plugin hook merged inside the TT-side `Koha::Template::Plugin::AdditionalContents->get` (which is what templates actually call via `[% USE AdditionalContents %]`) so plugin-contributed rows render alongside admin rows at every existing call site, with no per-template changes.

Note: the data-layer entry point `Koha::AdditionalContents->search_for_display` returns a `Koha::AdditionalContentsLocalizations` resultset (DBIx::Class query-backed) — merging arbitrary plugin rows into a resultset is brittle. The TT plugin wraps the resultset for templates and is the right seam: it controls the shape templates see and can append plugin rows without touching the ORM layer.

## Coding guideline compliance

- **PERL10** — internal helper uses `C4::Context->dbh` only when needed; no `$dbh` parameter.
- **PERL15** — merging happens inside `Koha::AdditionalContents`.
- **PERL16** — hook accepts a hashref of context.
- **PERL30** — `Koha::Plugins->call('additional_content', \%params)` passes a reference.

## Rationale

Most OPAC and staff-side templates already `[% SET ... = AdditionalContents.get(...) %]`. Layering plugin contributions inside `get` means every existing call site picks them up automatically. No new Template::Toolkit plugin method, no per-template plumbing.

## Files touched

- `Koha/Template/Plugin/AdditionalContents.pm` — call the hook inside the TT plugin's `get`, append plugin contributions to the result hashref's `content` list.
- `t/db_dependent/Koha/Template/Plugin/AdditionalContents.t` — coverage for plugin-augmented results.
- Optional: kitchen-sink plugin grows an `additional_content` example.

The ORM class `Koha/AdditionalContents.pm` is **not** modified. `Koha::AdditionalContents->search_for_display` continues to return a pure ORM resultset; the merge happens one layer up where the resultset is already being unwrapped for the template anyway.

## Hook signature

```perl
sub additional_content {
    my ( $self, $params ) = @_;
    # $params = { location, lang, library_id, blocktitle }
    return [] if $params->{location} ne 'OpacMainUserBlock';
    return [{
        title   => 'Roster sign-up',
        content => $self->_render_user_block_html($params),
        order   => 50,
    }];
}
```

## Implementation sketch

```perl
# Koha/Template/Plugin/AdditionalContents.pm
sub get {
    my ( $self, $params ) = @_;

    # ... existing search_for_display() call, unchanged ...
    my $content = Koha::AdditionalContents->search_for_display({
        category => $params->{category},
        location => $params->{location},
        lang     => $params->{lang} || 'default',
        ( $params->{library} ? ( library_id => $params->{library} ) : () ),
        ( $params->{id}      ? ( id         => $params->{id} )      : () ),
    });

    # Materialise the resultset and append plugin contributions. Existing
    # templates iterate `[% FOREACH a IN block.content %] [% a.title %] %]`
    # — that auto-resolves on both Koha::AdditionalContentsLocalization
    # objects and plain hashrefs, so plugin rows do not need to be blessed.
    my @rows = $content->as_list;

    if ( C4::Context->config('enable_plugins') ) {
        for my $plugin ( Koha::Plugins->new->GetPlugins({ method => 'additional_content' }) ) {
            try {
                my $extras = $plugin->additional_content($params);
                next if ref $extras ne 'ARRAY';
                push @rows, @{$extras};
            }
            catch { warn "Error calling 'additional_content' on " . $plugin->{class} . " ($_)"; };
        }
        @rows = sort {
            ( ref $a eq 'HASH' ? $a->{order} // 100 : 100 )
                <=> ( ref $b eq 'HASH' ? $b->{order} // 100 : 100 )
        } @rows;
    }

    return unless @rows;
    return {
        content    => \@rows,
        location   => $params->{location},
        blocktitle => $params->{blocktitle},
    };
}
```

The schema of plugin-returned rows mirrors what existing templates expect (`title`, `content`); `order` is honoured for stacking. Plugin rows have no `id`, so admins cannot edit them via the staff client — the plugin is the source of truth.

Behaviour change worth flagging in review: today `block.content` is a `Koha::Objects` resultset; under this patch it becomes an arrayref. Templates that call resultset-only methods (`->count`, `->next`) on `block.content` need to switch to `block.content.size` / `[% FOREACH … %]`. A grep over `koha-tmpl/**/*.tt` catches these — the survey under `docs/koha-extension-gaps.md` § 4 lists the call sites and they all already use `FOREACH`, but reviewers should confirm.

## Test plan

1. Apply the patch.
2. Enable plugins in `koha-conf.xml`.
3. Install a plugin that implements `additional_content` returning a row for `OpacMainUserBlock`.
4. Visit the OPAC main page. Confirm the plugin's HTML renders inside the user block alongside any admin-authored content.
5. Configure two plugins, both contributing to `OpacMainUserBlock`, with `order => 10` and `order => 20`. Confirm they render in order.
6. Make one plugin's `additional_content` throw. Confirm the OPAC still renders, the bad plugin is `warn`-logged, and the good plugin's content still appears.
7. Disable plugins in `koha-conf.xml`. Confirm only admin-authored content shows.
8. Test all major locations (`OpacNav`, `OpacMainUserBlock`, `OpacMySummaryNote`, `opaccredits`) — same code path.
9. Confirm the per-branch / per-language filtering still works: a plugin can inspect `params.library_id` and `params.lang` and return different content.

## Plugin-side example

```perl
sub additional_content {
    my ( $self, $params ) = @_;
    return [] if $params->{location} ne 'OpacMainUserBlock';
    my $branch = $params->{library_id} // q{};
    return [{
        title   => '',
        content => qq{<div class="page-section">Welcome to $branch — see your <a href="/cgi-bin/koha/opac/page/myplugin/my-roster">roster</a>.</div>},
        order   => 50,
    }];
}
```

## Cross-references

- Survey: `docs/koha-extension-gaps.md` § 4.
- Sibling shape: Bug 39870 (`notices_content`) — same merge-into-existing-context pattern.
- Pairs with Bug TBD-0008 (plugin OPAC pages) — banner here, link to plugin page.

## Signed-off-by

(to be filled in during review)
