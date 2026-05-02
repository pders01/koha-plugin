## Extending Koha's REST API from a plugin

Koha lets a plugin contribute its own REST routes by implementing two hooks: `api_namespace` and `api_routes`. The result mounts under `/api/v1/contrib/<namespace>/...`. The wiring is straightforward, but the conventions around schemas, permissions, error responses, and shared helpers between the controller and the staff-side plugin module are easy to get wrong.

### Hook output

```perl
sub api_namespace {
    my $self = shift;
    return 'staffroster';   # short, kebab-friendly slug
}

sub api_routes {
    my ( $self, $args ) = @_;
    my $spec_str = $self->mbf_read('openapi.json');
    return decode_json($spec_str);
}
```

`mbf_read` reads bundled files from the plugin's directory. Keeping the spec in `openapi.json` rather than inlining it keeps Perl readable and lets you generate / lint the spec with normal OpenAPI tooling.

### `openapi.json` layout

Koha consumes OpenAPI 2.0 (Swagger). The spec is paths-only; Koha merges it into its own definition. Each path uses two Koha-specific extensions:

- `x-mojo-to` — the controller class + method that handles the request.
- `x-koha-authorization` — the permission predicate. For plugin-defined codes, point at `plugins:<your_code>` (see [`plugin-permissions.md`](plugin-permissions.md)).

Minimal route:

```json
{
  "/assignments/{assignment_id}": {
    "delete": {
      "operationId": "deleteAssignment",
      "parameters": [
        { "in": "path", "name": "assignment_id", "type": "integer", "required": true,
          "description": "assignment_id identifier" }
      ],
      "produces": ["application/json"],
      "responses": {
        "204": { "description": "Unassign" },
        "400": { "description": "Bad request", "schema": { "$ref": "#/definitions/Error" } },
        "403": { "description": "Access forbidden", "schema": { "$ref": "#/definitions/Error" } },
        "404": { "description": "Not found",       "schema": { "$ref": "#/definitions/Error" } },
        "409": { "description": "Conflict (slot full, overlap, calendar closed)",
                                                    "schema": { "$ref": "#/definitions/Error" } },
        "500": { "description": "Internal error",  "schema": { "$ref": "#/definitions/Error" } }
      },
      "summary": "Unassign",
      "tags": ["StaffRoster"],
      "x-koha-authorization": { "permissions": { "plugins": "staffroster_assign" } },
      "x-mojo-to": "Xyz::Paulderscheid::StaffRoster::AssignmentController#delete"
    }
  }
}
```

Conventions worth following:

- **Declare every status code your controller can return.** Mojolicious validates responses against the spec; an undeclared 409 surfaces as a generic 500 to the client. Always include the 4xx codes that match the controller's `return $c->render(status => ..., ...)` calls.
- **Use the `plugins:<code>` permission form.** Wholesale `plugins` grants pass automatically; limited-mode users need the specific code in `user_permissions`. See the permissions doc for the table layout.
- **Keep `operationId` unique across the whole spec.** Koha merges your paths into the global definition; collisions get rejected at startup.
- **Path params get a `description`.** Lint tools complain otherwise, and the description is used in generated client SDKs.

### The controller

Inherit `Mojolicious::Controller` and let `openapi->valid_input` validate against the spec before you touch anything:

```perl
package Koha::Plugin::Xyz::Paulderscheid::StaffRoster::RosterController;

use Modern::Perl;
use Mojo::Base 'Mojolicious::Controller';

use C4::Context;
use Try::Tiny qw( catch try );

sub get_week {
    my $c = shift->openapi->valid_input or return;

    return try {
        my $roster_id  = $c->validation->param('roster_id');
        my $week_start = $c->req->param('start') // _current_week_start();

        my $dbh    = C4::Context->dbh;
        my $roster = $dbh->selectrow_hashref(...);

        return $c->render( status => 404, openapi => { error => 'Roster not found' } )
            if !$roster;

        require Koha::Plugin::Xyz::Paulderscheid::StaffRoster;
        my $plugin = Koha::Plugin::Xyz::Paulderscheid::StaffRoster->new;
        return $c->render( status => 403, openapi => { error => 'Not authorized for this roster' } )
            if !$plugin->_can_view_roster($roster);

        # ... build response ...

        return $c->render(
            status  => 200,
            openapi => { roster => $roster, slots => $slots, ... },
        );
    }
    catch {
        $c->unhandled_exception($_);
    };
}
```

Notes:

- **`valid_input or return`** — short-circuits with a 400 + JSON error when the request body or query params don't match the spec. Skipping it means controllers re-implement validation by hand.
- **`require` the plugin module inside the action**, not at the top. The controller class loads early; lazy `require` defers the heavier plugin module until a request actually hits.
- **Reuse plugin helpers from the controller.** Instantiate the plugin with `Koha::Plugin::...->new` to call permission gates, calendar helpers, RRule logic. That way the API and the staff UI share the same authorisation and business rules.
- **Always respond via `openapi => {...}`**. `json => {...}` skips response-validation. With `openapi`, an undeclared response shape fails fast in development.
- **Catch-all via `Try::Tiny`** — let `unhandled_exception` produce the 500 response so stack traces never leak to clients.

### Sharing logic between staff UI and API

Plugins typically grow a staff UI and an API in parallel. Keep the business rules in the plugin module (`Koha/Plugin/.../StaffRoster.pm`) and let both controllers and `tool` / `admin` handlers call them:

```perl
# In the plugin module — the source of truth
sub _can_view_roster { my ($self, $roster) = @_; ... }

# In the controller — same call shape
require Koha::Plugin::...::StaffRoster;
my $plugin = Koha::Plugin::...::StaffRoster->new;
return $c->render( status => 403, openapi => { error => '...' } )
    if !$plugin->_can_view_roster($roster);

# In the staff handler — same call shape
return $self->_can_view_roster($roster)
    ? _render_view($template, $roster)
    : _render_denied($template);
```

Splitting the logic two ways (one for HTML, one for JSON) is the failure mode this avoids. Two-way splits drift; sites that grant permission via the API but deny via the UI quickly become unsupportable.

### Localized error envelope

Plain `{ error: 'Slot full (3/3)' }` forces the server's locale on the client. A localized frontend can't re-render the message in the user's language without re-implementing the rule that produced it. Use a templated envelope so the server expresses *which* error and *what arguments* fill it, and let the client pick the active locale's translation:

```perl
# Controller
return $c->render(
    status  => 409,
    openapi => {
        error         => "Slot full ($filled/$max)",      # English fallback for curl / legacy clients
        template      => 'slot_full_filled_max',          # i18n key; client looks up in its dict
        template_args => { filled => $filled, max => $max },
    },
);
```

Rules:

- **Always include `error`.** Curl, legacy clients, and CI assertions read it. Keep it human-readable English.
- **`template` is a key, not a sentence.** `slot_full_filled_max`, not `"Slot full ({filled}/{max})"`. The string lives in the locale dict.
- **`template_args` is a flat hash of placeholders.** Keep keys short; clients substitute via `{key}` interpolation.

Client-side resolver:

```ts
// src/api.ts
async function asJson<T>(res: Response): Promise<T> {
    const body = await res.json();
    if (!res.ok && body.template) {
        const fmt   = __(body.template);
        const args  = body.template_args ?? {};
        const msg   = fmt.replace(/{(\w+)}/g, (_, k) => String(args[k] ?? `{${k}}`));
        throw new Error(msg);
    }
    if (!res.ok) throw new Error(body.error ?? `HTTP ${res.status}`);
    return body as T;
}
```

```json
// src/i18n/de.json
{
    "slot_full_filled_max": "Slot voll ({filled}/{max})",
    "self_unclaim_lockout":  "Sperrfrist: noch {hours_until_shift}h bis zur Schicht",
    "Slot not found":        "Slot nicht gefunden"
}
```

Fallback chain: `template` lookup → English `error` → `HTTP <status>`. Each step degrades gracefully so a missing translation never strands the user with `[object Object]`.

Static error strings (no placeholders) skip the envelope and ship as plain `{ error: 'Slot not found' }` — the client's `__()` lookup against the literal English source key still localizes them.

### Safari fetch cache trap

Frontend code that polls a plugin endpoint must explicitly bypass the HTTP cache, and it has to do so in a way that is portable across browsers. The naive `fetch(url, { cache: 'no-store' })` works, but the more common `cache: false` shortcut shipped by some HTTP wrapper libraries (`@jpahd/lit-stack` and others) maps differently per browser:

| Library `cache: false` | Chromium | Firefox | Safari |
|------------------------|----------|---------|--------|
| Resolves to | `"no-cache"` | `"default"` | `"force-cache"` |

On Safari, the result is the opposite of the intent — the endpoint serves last-fetched-week snapshots from disk and the user thinks the page hasn't refreshed. Always use the option that resolves to `"no-cache"` (or `"no-store"`) on every browser:

```ts
// src/api.ts
const ENDPOINTS = {
    rosterWeek:     { url: `${BASE}/rosters`,        ignoreCache: true },
    availableStaff: { url: `${BASE}/staff/available`, ignoreCache: true },
    myOpenSlots:    { url: `${BASE}/me/open_slots`,   ignoreCache: true },
};
```

`ignoreCache: true` (or whatever your wrapper calls it) must produce `cache: "no-cache"` on every browser, not `"force-cache"` on Safari. Verify by inspecting the wrapper's source — the bug is invisible in development unless you actually open Safari.

### Static files

`static_routes` is the sibling hook for serving static assets through the API. Same pattern: read `staticapi.json`, return the parsed spec. Useful for the JS bundle that powers a Lit / Vue staff UI without touching Apache config.

```perl
sub static_routes {
    my ( $self, $args ) = @_;
    my $spec_str = $self->mbf_read('staticapi.json');
    return decode_json($spec_str);
}
```

### Pitfalls

| Pitfall | Symptom | Fix |
|---------|---------|-----|
| Controller returns 409 not in spec | Client sees 500 | Declare every status code in `responses` |
| `use` plugin module at controller top | Slow controller load, circular-require risk | `require` inside the action |
| Render with `json => {...}` | Schema mismatches go silent | Always `openapi => {...}` |
| Skip `valid_input or return` | Hand-rolled validation drifts from spec | Always validate via the OpenAPI middleware |
| Hardcoded permission check in controller, none in spec | Spec lies, generated docs say "no auth" | Put the permission in `x-koha-authorization` |
| Duplicate `operationId` across plugins | Koha refuses to start | Prefix every operationId with your plugin slug |

### Where native integration would help

- A `Koha::Plugin::API::Controller` base that bundles the `valid_input` boilerplate and a typed render helper.
- A `permissions` block in `PLUGIN.yml` that auto-references its codes from `x-koha-authorization` so spec and registration stay in sync.
- Shared response definitions (`#/definitions/Error`) for plugins to reuse instead of redeclaring the same error envelope on every endpoint.
- Per-plugin operationId namespacing handled at merge time so plugin authors don't need to police it themselves.
