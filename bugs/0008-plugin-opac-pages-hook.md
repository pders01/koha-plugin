# Bug TBD-0008: Add `opac_pages` plugin hook for plugin-rendered OPAC pages

## Subject

`Bug TBD: Add opac_pages plugin hook reusing opac-page.tt chrome`

## Summary

`opac/opac-page.pl` renders patron-facing pages stored in `additional_contents` with `category='pages'`. The category is a closed enum, the content is static HTML, and the renderer has no way to delegate to a plugin. Plugins that want a themed, login-aware OPAC page have to hand-write a `.pl` controller mounted under `/cgi-bin/koha/plugins/run.pl` and recreate masthead, breadcrumbs, and `usermenu.inc` integration.

This patch introduces an `opac_pages` plugin hook so a plugin declares slug + handler; Koha mounts the page at `/cgi-bin/koha/opac/page/<plugin-slug>/<page-slug>` and renders the handler's output inside the standard `opac-page.tt` chrome.

## Coding guideline compliance

- **PERL10** — handler dispatcher uses `C4::Context->dbh` only when needed; no `$dbh` parameter.
- **PERL15** — registry helper lives in `Koha::AdditionalContents::PluginPages` (new module).
- **PERL30** — handler receives `\%context` (logged_in_user, language, branchcode) by reference.
- **SEC1** — page handlers GET-only by default; mutating actions go through `cud-` ops with the standard CSRF middleware.

## Rationale

Today's options for a plugin OPAC page:

- Custom `.pl` script under `plugins/run.pl` — no `usermenu.inc` integration, breadcrumbs by hand, theme drift.
- Static HTML in `additional_contents` `pages` category — no per-user data.
- DOM-patch existing pages via `opac_js` — brittle, no server-side auth.

Reusing `opac-page.tt`'s chrome eliminates theme drift. Pairs naturally with Bug TBD-0006 (OPAC user-menu tab) so the tab points at the page.

## Files touched

- `Koha/AdditionalContents/PluginPages.pm` — new module that resolves a slug to a `(plugin, handler)` pair.
- `opac/opac-page.pl` — fall through to plugin pages when the slug isn't found in `additional_contents`.
- New routing entry in `Plack` config / Apache rewrite: `/cgi-bin/koha/opac/page/<plugin-slug>/<page-slug>` → `opac-page.pl`.
- `t/db_dependent/opac/opac-page-plugin.t` — coverage.

## Hook signature

```perl
sub opac_pages {
    my ($self) = @_;
    return [
        {
            slug          => 'my-roster',
            title         => 'My Roster',
            handler       => 'render_opac_roster',
            require_login => 1,
        },
        {
            slug    => 'about-staffing',
            title   => 'About staffing',
            handler => 'render_opac_about',
        },
    ];
}

sub render_opac_roster {
    my ( $self, $params ) = @_;       # { logged_in_user, language, branchcode }
    my $template = $self->get_template({ file => 'opac-roster.tt' });
    $template->param( shifts => $self->_shifts_for( $params->{logged_in_user} ) );
    return $template->output;          # placed inside Koha's standard opac-page.tt chrome
}
```

## Implementation sketch

```perl
# opac/opac-page.pl — at the bottom of the existing dispatcher.
my $static_page = Koha::AdditionalContents->find($page_id);
if ( $static_page && $static_page->category eq 'pages' ) {
    # ... existing path ...
}
elsif ( my $plugin_page = Koha::AdditionalContents::PluginPages->resolve( $query->path_info ) ) {
    if ( $plugin_page->{require_login} && !$borrowernumber ) {
        print $query->redirect('/cgi-bin/koha/opac-user.pl');
        exit;
    }
    my $body = eval {
        $plugin_page->{plugin}->${\ $plugin_page->{handler} }({
            logged_in_user => $borrowernumber ? Koha::Patrons->find($borrowernumber) : undef,
            language       => C4::Languages::getlanguage($query),
            branchcode     => $homebranch,
        });
    };
    $template->param(
        page  => $body // q{},
        title => $plugin_page->{title},
    );
    output_html_with_http_headers $query, $cookie, $template->output;
    exit;
}
else {
    print $query->redirect('/cgi-bin/koha/errors/404.pl');
    exit;
}
```

`Koha::AdditionalContents::PluginPages->resolve($path_info)` parses the slug, queries `Koha::Plugins`, calls `opac_pages`, matches the requested slug, and returns `{ plugin, handler, title, require_login }`. Cached per request.

## Test plan

1. Apply the patch.
2. Enable plugins in `koha-conf.xml`.
3. Install a plugin that implements `opac_pages` returning two pages: one with `require_login => 1`, one without.
4. Visit `/cgi-bin/koha/opac/page/myplugin/about-staffing` while logged out. Confirm the page renders with masthead, breadcrumbs, and the body produced by the handler.
5. Visit `/cgi-bin/koha/opac/page/myplugin/my-roster` while logged out. Confirm the redirect to `opac-user.pl`. Log in. Confirm the page now renders with the patron-specific body.
6. Confirm the page's `<title>` element uses the declared title.
7. Disable the plugin. Both URLs return 404.
8. Combine with Bug TBD-0006: install a plugin that ships both `opac_user_menu_tab` and `opac_pages`. Confirm the sidebar entry links to the rendered page and the tab gets `class="active"` on the right view.

## Plugin-side example

```perl
package Koha::Plugin::Com::Example::MyPlugin;
use base qw(Koha::Plugins::Base);

sub opac_pages {
    return [
        {
            slug          => 'my-roster',
            title         => 'My Roster',
            handler       => 'render_opac_roster',
            require_login => 1,
        },
    ];
}

sub render_opac_roster {
    my ( $self, $params ) = @_;
    my $patron   = $params->{logged_in_user};
    my $template = $self->get_template({ file => 'opac-roster.tt' });
    $template->param( shifts => $self->_shifts_for($patron) );
    return $template->output;
}
```

## Cross-references

- Survey: `docs/koha-extension-gaps.md` § 3.
- Pairs with Bug TBD-0006 (OPAC user menu tab) — tab `url` points at this page.
- Adjacent: Bug TBD-0009 (AdditionalContents merge hook) for the inverse direction (plugin contributes content to existing slots).

## Signed-off-by

(to be filled in during review)
