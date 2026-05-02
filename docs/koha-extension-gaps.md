## Koha extension gaps: built extensible, no plugin wiring

Several Koha subsystems are internally extensible — driven by enums, lookup tables, registries, or location-keyed includes — but have no plugin hook layered on top. A site administrator can configure them; a plugin author cannot. This document catalogues the most useful of those gaps, with current code references, the workaround (where one exists), and a sketch of what a native hook would look like.

The goal is a punch list for native integration. Each section follows the same shape: what is extensible inside Koha, where the seam lives, why a plugin can't reach it today, and the smallest hook that would close the gap.

Repo references in this doc are to `~/Projects/kcom/koha`.

---

### 1. OPAC user-menu sidebar tabs

**Where it lives:** `koha-tmpl/opac-tmpl/bootstrap/en/includes/usermenu.inc`. A flat `<ul>` of hardcoded `<li>` items, each gated on a syspref or a `feature_enabled('patron_consent_type')` plugin call.

**Why it's nearly extensible:** the include already calls `[% USE KohaPlugins %]` and uses `KohaPlugins.feature_enabled('patron_consent_type')` for one specific case (the consent link). The plumbing exists — the template plugin loads, plugin discovery works — but every other tab is still a static line in the template.

**Why a plugin can't reach it:** `KohaPlugins` exposes no `get_plugins_opac_user_menu_tabs` method. Plugins that want a sidebar entry for a custom OPAC page (saved searches, library card images, course schedules, donations) must:

1. Provide the page via `opac-pages.pl` workaround (see § 3) or a custom `.pl` script,
2. Inject a `<li>` into the menu via `opac_js` DOM hacking,
3. Re-create the `class="active"` state JS-side because the include sets it via TT flags only known at server render time.

This is the OPAC counterpart to the [permission-label workaround](plugin-permissions.md) — an `opac_js` injector parses the rendered HTML and patches in nodes.

**Hook sketch:**

```perl
# In Koha::Template::Plugin::KohaPlugins
sub get_plugins_opac_user_menu_tabs {
    my ( $self, $params ) = @_;   # { active => 'rosterview', logged_in_user => $patron }
    my $tabs = [];
    return $tabs unless C4::Context->config('enable_plugins');
    my @plugins = Koha::Plugins->new->GetPlugins({ method => 'opac_user_menu_tab' });
    for my $plugin (@plugins) {
        try {
            push @{$tabs}, $plugin->opac_user_menu_tab($params);
        } catch { warn "Error calling 'opac_user_menu_tab' on " . $plugin->{class} . " ($_)"; };
    }
    return $tabs;
}
```

Plugin side (mirrors the existing `intranet_catalog_biblio_tab` shape):

```perl
sub opac_user_menu_tab {
    my ( $self, $params ) = @_;
    my $patron = $params->{logged_in_user} or return;
    return if !$patron->has_permission( ... );   # plugin-decided gating
    return Koha::Plugins::Tab->new({
        title => 'My Roster',
        url   => '/cgi-bin/koha/plugins/run.pl?class=' . $self->{class} . '&method=opac',
        view  => 'rosterview',                   # used to compute class="active"
    });
}
```

Template change in `usermenu.inc`:

```html
[% FOREACH tab IN KohaPlugins.get_plugins_opac_user_menu_tabs(active => active_view, logged_in_user => logged_in_user) %]
    <li [% IF tab.view == active_view %]class="active"[% END %]>
        <a href="[% tab.url | url %]">[% tab.title | html %]</a>
    </li>
[% END %]
```

`Koha::Plugins::Tab` already exists at `Koha/Plugins/Tab.pm` — currently used only for biblio detail tabs. Extending it to OPAC tabs is mostly a template + KohaPlugins method addition.

**Adjacent gap:** the staff-side patron details page (`members/moremember.pl`) has a similar tabbed layout and the same lack of plugin hook. The same `Koha::Plugins::Tab` shape would cover both with a `staff_patron_tab` hook.

---

### 2. Messaging preferences

**Where it lives:** three tables form the messaging preference triad, all driven by lookup rows:

| Table | Rows seeded by | Used for |
|-------|----------------|----------|
| `message_attributes` | `installer/data/mysql/mandatory/sample_notices_message_attributes.sql` | The list of "things a patron can opt in/out of": `Item_Due`, `Hold_Filled`, `Auto_Renewals`, `Recall_Waiting`, etc. |
| `message_transports` | `sample_notices_message_transports.sql` | Maps `(message_attribute_id, transport_type, is_digest)` to a `(letter_module, letter_code)` notice template. |
| `borrower_message_preferences` | Patron's per-attribute opt-in (digest, days-in-advance) | Drives whether `EnqueueLetter` actually fires for a transport. |

Render path: `C4/Form/MessagingPreferences.pm` reads `message_attributes` via `Koha::Patron::MessagePreference::Attributes`, the OPAC template at `koha-tmpl/opac-tmpl/bootstrap/en/modules/opac-messaging.tt` renders one `<tr>` per attribute, and the human label comes from a hardcoded `[% IF messaging_preference.Item_Due %]<span>Item due</span>[% ELSIF ... %]` ladder over every known attribute name.

**Why it's nearly extensible:** `message_attributes.message_name` is a `varchar(40)` with a `UNIQUE` index — anyone can `INSERT INTO message_attributes (message_name, takes_days) VALUES ('Roster_Reminder', 1)` and the row appears in the form. `message_transports` lets a plugin tie that attribute to a `(letter_module, letter_code)` notice template. The data layer is fully open.

**Why a plugin can't reach it:**

- The OPAC and staff template label ladders have no `[% CASE %]` for unknown attributes. A plugin that registers `Roster_Reminder` shows up in the form with `<span>Unknown</span>` as the label and no description column.
- There is no hook to translate the label, so the JS workaround used for [permission labels](plugin-permissions.md) (an `intranet_js` injector matching on `tr#roster_reminder_message`) is the only way to get a human name in. On the OPAC side, `opac_js` is the equivalent injector.
- `EnqueueLetter` fires only when `borrower_message_preferences` says the patron wants this attribute, on a transport mapped by `message_transports` to a notice template. A plugin must seed all three tables on install, manage upgrades when adding new attributes, and clean them up on uninstall — without fixtures resembling those in `koha-plugin-staff-roster`'s [permissions](plugin-permissions.md) and [audit](plugin-audit-logging.md) lifecycle docs.
- `transform_prepared_letter` exists as a plugin hook, but it intercepts after Koha decides to send. There is no symmetrical "register a new attribute the user can opt into" hook.

**Workaround pattern for a plugin today:**

```perl
sub install {
    my ($self) = @_;
    my $dbh = C4::Context->dbh;

    $dbh->do(q{INSERT IGNORE INTO message_attributes (message_name, takes_days)
               VALUES ('Roster_Reminder', 1)});
    my ($attr_id) = $dbh->selectrow_array(
        q{SELECT message_attribute_id FROM message_attributes WHERE message_name = ?},
        undef, 'Roster_Reminder');

    for my $transport (qw( email sms )) {
        $dbh->do(q{INSERT IGNORE INTO message_transports
                   (message_attribute_id, message_transport_type, is_digest, letter_module, letter_code)
                   VALUES (?, ?, 0, 'circulation', 'STAFFROSTER_REMINDER')},
                 undef, $attr_id, $transport);
    }
    return 1;
}

sub opac_js {
    my ($self) = @_;
    return <<~'JS';
    <script>
    (function () {
      if ((document.body && document.body.id) !== 'opac-messaging') return;
      var row = document.getElementById('roster_reminder_message');
      if (!row) return;
      var label = row.querySelector('td:first-child span');
      if (label && label.textContent.trim() === 'Unknown') {
          label.textContent = 'Staff roster shift reminder';
      }
    })();
    </script>
    JS
}
```

The same shape is needed for `intranet_js` to relabel the row on `members/messaging.pl`. The cleanup mirrors `_unregister_permissions`: delete from `message_attributes`, `message_transports`, `borrower_message_preferences` in the right order.

**Hook sketch:** a single declarative method that the form template + `EnqueueLetter` infrastructure both consult.

```perl
sub messaging_preferences {
    my ($self) = @_;
    return [
        {
            message_name => 'Roster_Reminder',
            label        => 'Staff roster shift reminder',     # i18n via $self->mbf_dir
            takes_days   => 1,
            transports   => [
                { type => 'email', letter_module => 'circulation', letter_code => 'STAFFROSTER_REMINDER' },
                { type => 'sms',   letter_module => 'circulation', letter_code => 'STAFFROSTER_REMINDER' },
            ],
        },
    ];
}
```

Koha would handle: registration on install, label rendering on form (no more SWITCH/CASE), letter-template lookup on send, and cleanup on uninstall. The plugin stops touching three SQL tables and writing two JS injectors.

---

### 3. OPAC `pages` feature

**Where it lives:** `tools/additional-contents.pl?category=pages` (admin UI). Records land in `additional_contents` with `category='pages'`. Rendered by `opac/opac-page.pl?page_id=<n>` against `koha-tmpl/opac-tmpl/bootstrap/en/modules/opac-page.tt`.

The page renderer is dead simple — fetch the row, validate category and visibility, render its `translated_content`:

```perl
my $page = Koha::AdditionalContents->find($page_id);
if (  !$page
    || $page->category ne 'pages'
    || $page->branchcode && $page->branchcode != $homebranch
    || $page->location ne 'opac_only' && $page->location ne 'staff_and_opac' )
{
    print $query->redirect('/cgi-bin/koha/errors/404.pl');
    exit;
}
my $content = $page->translated_content( C4::Languages::getlanguage($query) );
$template->param( page => $content );
```

**Why it's interesting for plugins:** the `pages` category is exactly the right primitive for plugin-rendered patron-facing content. A plugin could register a "page" identified by code or slug, and either:

1. Render dynamic content into the page slot (replacing the static HTML stored in `additional_contents`), or
2. Reuse the chrome (breadcrumbs, navigation, masthead, layout) and only contribute a body block.

Either fits naturally on top of `opac-page.pl`.

**Why a plugin can't reach it today:**

- `additional_contents.category` is an enum baked into both the admin tool and the OPAC renderer. There is no `category='plugin'` branch.
- `Koha::AdditionalContents` provides no hook for plugin-rendered translation — the model assumes static localized HTML.
- A plugin that wants the same chrome (`opac-page.tt`, `usermenu.inc`, breadcrumbs) has to copy the template into its plugin directory, and the OPAC theme drift between versions makes that brittle.

**Workaround patterns today:**

| Need | Workaround | Cost |
|------|------------|------|
| Plugin-owned OPAC page | Hand-write a `.pl` controller mounted under `/cgi-bin/koha/plugins/run.pl?class=...&method=opac` | Custom routing, breadcrumbs, masthead, no `usermenu.inc` integration |
| Static-but-dynamic content (per-user) | Insert a row into `additional_contents` with placeholder, post-process via `opac_js` | Brittle DOM patching, no per-user data on server side |
| Plugin-supplied OPAC page slot | Use `OpacMainUserBlock` location + AdditionalContents | Site admin must paste the right HTML; no plugin authority over location |

**Hook sketch:**

```perl
# Plugin-side
sub opac_pages {
    my ($self) = @_;
    return [
        {
            slug      => 'my-roster',
            title     => 'My Roster',
            handler   => 'render_opac_roster',   # method on $self
            require_login => 1,
        },
    ];
}

sub render_opac_roster {
    my ( $self, $params ) = @_;   # { logged_in_user, language, branchcode }
    my $template = $self->get_template({ file => 'opac-roster.tt' });
    $template->param( shifts => $self->_shifts_for( $params->{logged_in_user} ) );
    return $template->output;     # placed inside Koha's standard opac-page.tt chrome
}
```

Koha would mount these at `/cgi-bin/koha/opac/page/<plugin-slug>/<page-slug>`, reuse the existing `opac-page.tt` chrome, and pass `logged_in_user`, `lang`, and the home branch to the handler. Combined with the user-menu hook from § 1, a plugin gets a navigated, themed, login-aware page with no theme drift.

---

### 4. AdditionalContents locations (`OpacNav`, `OpacMainUserBlock`, etc.)

**Where it lives:** `Koha::AdditionalContents` enumerates the allowed locations: `OpacNav`, `OpacNavRight`, `OpacNavBottom`, `OpacMainUserBlock`, `OpacMySummaryNote`, `opaccredits`, `opacheader`, `OpacCustomSearch`, etc. Templates `[% SET OpacNav = AdditionalContents.get(location => "OpacNav", ...) %]` to fetch the rendered HTML for each slot.

**Why it's interesting:** these are exactly the slots a plugin would want to inject into — a sidebar promo, a usage hint on a specific page, a per-branch banner. They already do per-branch / per-language fan-out.

**Why a plugin can't reach it:**

- The location enum is closed. A plugin can't register a new slot.
- A plugin can't register *content* for an existing slot programmatically — only sysadmins can, via the staff client.
- There is no hook in `AdditionalContents.get` to let a plugin contribute alongside admin-authored rows for a location.

**Hook sketch:** an `additional_content` hook returning rows to merge with the admin table:

```perl
sub additional_content {
    my ( $self, $params ) = @_;   # { location, lang, library_id }
    return [] if $params->{location} ne 'OpacMainUserBlock';
    return [{
        title   => '',
        content => $self->_render_user_block_html($params),
        order   => 50,    # mid-stack
    }];
}
```

The merge happens at `AdditionalContents->get` so every existing template `[% SET OpacNav = AdditionalContents.get(...) %]` automatically picks up plugin contributions. No per-template plumbing.

---

### 5. `Koha::Plugins::Tab` — already exists, mostly unused

`Koha/Plugins/Tab.pm` is a small object (id, title, content, ...) used solely by `intranet_catalog_biblio_tab`. The shape is generic enough to power:

- OPAC user menu tabs (§ 1)
- Staff patron-detail tabs (`members/moremember.pl`)
- Staff biblio toolbar buttons (already partly via `intranet_catalog_biblio_enhancements_toolbar_button`)
- Admin home page extensions (`/cgi-bin/koha/admin/admin-home.pl`)
- OPAC main page tiles

Each of these would be a small `KohaPlugins.get_plugins_<area>_tabs` method following the same pattern that already works for biblio tabs. Nothing in `Koha::Plugins::Tab` itself needs to change.

---

### 6. Staff sidebar / sub-permissions surface

Documented separately in [`plugin-permissions.md`](plugin-permissions.md). Mentioned here for completeness: the same theme — open data layer, hardcoded SWITCH/CASE rendering — applies to the permissions form (`includes/permissions.inc`) and to messaging (§ 2 above). A single shared "label registry" hook for plugin codes would cover both surfaces.

---

### Recurring shape

Every gap in this list shares structure:

| Layer | Open? | Why plugins can't reach it |
|-------|-------|---------------------------|
| Schema / data | **Open** — INSERT works | No plugin lifecycle around the rows |
| Render | **Hardcoded** — SWITCH/CASE, enum branches, static includes | No plugin hook in the rendering path |
| Discovery | **Mixed** — some `KohaPlugins.*` methods exist for adjacent surfaces | New surfaces require a new method per area |

The native fix in each case follows the pattern Koha already uses for biblio tabs: a `Koha::Plugins::Tab`-shaped declarative hook + a `KohaPlugins.get_plugins_<area>` template helper + (where lifecycle matters) install/upgrade/uninstall management of the underlying rows.

### Where to start

If the goal is the largest plugin-author surface area for the smallest core change:

1. **OPAC user menu tabs (§ 1)** — smallest hook, biggest UX win. Mirrors an existing pattern almost verbatim.
2. **Plugin OPAC pages (§ 3)** — gives plugins a real place to live in the OPAC. Combines well with § 1.
3. **Messaging preferences (§ 2)** — solves a long-standing customisation pain point. Lifecycle is more involved (three tables) but the hook shape is small.
4. **AdditionalContents merge hook (§ 4)** — opens every existing slot to plugin content with no per-template change.
5. **Generalize `Koha::Plugins::Tab` (§ 5)** — sweep of small additions; each one closes a tabbed-UI gap.

### Cross-references

- [Plugin permissions](plugin-permissions.md) — the SWITCH/CASE label workaround mirrors what's needed for messaging in § 2.
- [Plugin REST API](plugin-rest-api.md) — `x-koha-authorization` and `api_routes` are the *non-gap* contrast: a plugin surface that is fully wired.
- [UI conventions](plugin-ui-conventions.md) — the chrome a plugin OPAC page (§ 3) would inherit instead of recreating.
- [Audit logging](plugin-audit-logging.md), [transactions](plugin-transactions.md) — install/upgrade/uninstall lifecycle a messaging-preferences plugin (§ 2) needs.
