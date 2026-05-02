## Cypress integration tests for plugins

Plugin REST endpoints touch real Koha tables, real `Koha::Calendar`, real CSRF middleware. Unit tests on the plugin module catch logic bugs but not integration failures (calendar memoisation, route mounting, Plack restart timing). Running Cypress against a live `koha-testing-docker` (ktd) instance closes that gap without standing up a parallel test harness.

`koha-plugin-staff-roster` ships this end-to-end. Pattern below maps to commits `5fe0b21`, `bcebe8c`, `58f5e2c`.

### Approach

Ride Koha's own Cypress installation rather than bundling one into the plugin:

- ktd ships `/kohadevbox/Cypress/12.17.4/Cypress/Cypress` pre-installed with the staff client's plugin tasks (`cy.task("query", ...)`, `cy.login()`).
- Specs live in the plugin tree at `cypress/integration/<plugin>/`.
- A runner script syncs the plugin into the container, reinstalls (so REST routes mount), restarts Plack, drops the specs into Koha's `t/cypress/integration/<plugin>/`, and invokes `npx cypress run --spec '...'`.
- The plugin doesn't need its own Cypress dependency; `cy.task("query", ...)` lets specs seed and tear down via SQL.

### Layout

```
koha-plugin-myplugin/
    cypress/
        integration/
            myplugin/
                _fixtures.ts          # createFixture / cleanupFixture / constants
                feature_a_spec.ts
                feature_b_spec.ts
    scripts/
        run-cypress.sh
    justfile                          # `just test-cypress`
```

The `_` prefix on `_fixtures.ts` keeps it out of the spec glob.

### Runner script

```sh
#!/bin/sh
set -eu

CONTAINER=${KOHA_CONTAINER:-dev-koha-1}
PLUGIN_DIR=/var/lib/koha/kohadev/plugins
KOHA_DIR=/kohadevbox/koha
SPEC_GLOB='t/cypress/integration/myplugin/*_spec.ts'

ROOT=$(cd "$(dirname "$0")/.." && pwd)

echo "[run-cypress] syncing plugin source -> ${CONTAINER}:${PLUGIN_DIR}"
docker exec "$CONTAINER" rm -rf "$PLUGIN_DIR/Koha"
docker cp "$ROOT/Koha" "$CONTAINER:$PLUGIN_DIR/Koha"

echo "[run-cypress] installing plugin (idempotent)"
docker exec "$CONTAINER" sh -c "
  KOHA_CONF=/etc/koha/sites/kohadev/koha-conf.xml \
  perl -e 'use Koha::Plugins; my (\$p) = grep { ref(\$_) =~ /MyPlugin/ } Koha::Plugins->new->GetPlugins; \$p->install if \$p && \$p->can(q{install}); 1'
"

echo "[run-cypress] restarting Plack so new routes mount"
docker exec "$CONTAINER" koha-plack --restart kohadev >/dev/null
sleep 3

echo "[run-cypress] copying specs into ${CONTAINER}:${KOHA_DIR}/t/cypress/integration/myplugin"
docker exec "$CONTAINER" rm -rf "$KOHA_DIR/t/cypress/integration/myplugin"
docker cp "$ROOT/cypress/integration/myplugin" \
    "$CONTAINER:$KOHA_DIR/t/cypress/integration/myplugin"

echo "[run-cypress] launching cypress"
docker exec "$CONTAINER" sh -c "
  cd $KOHA_DIR && \
  CYPRESS_RUN_BINARY=/kohadevbox/Cypress/12.17.4/Cypress/Cypress \
  npx cypress run --spec '$SPEC_GLOB'
"
```

Three loadbearing details:

- **`docker cp` to a removed target** — `docker cp ROOT/Koha CONTAINER:DIR/Koha` nests when the target already exists. Always `rm -rf` first or new files won't reach the controllers. Same trap from the unit-test workflow in `CLAUDE.md`.
- **Plack restart + 3s sleep** — REST routes are cached per worker. Without the restart + sleep, the spec hits stale routes and 404s.
- **Plugin install via `perl -e`** — runs the install method inside the container so any schema changes in your branch land before the specs run. `INSERT IGNORE` / `ON DUPLICATE KEY UPDATE` patterns mean re-running is free.

### Fixture helpers

```ts
// cypress/integration/myplugin/_fixtures.ts
export const TEST_BRANCH = "CPL";
export const SUPERLIBRARIAN_BORROWERNUMBER = 51;

export type Fixture = { rosterId: number; slotId: number; typeId: number };

export function createRosterFixture(): Cypress.Chainable<Fixture> {
    return cy.task<{ insertId: number }>("query", {
        sql: `INSERT INTO staff_roster_types (code, name, color, is_active, created_at, updated_at)
              VALUES ('CPRESS', 'Cypress test', '#000', 1, NOW(), NOW())`,
    }).then(typeRes => {
        const typeId = typeRes.insertId;
        return cy.task<{ insertId: number }>("query", {
            sql: `INSERT INTO staff_roster (roster_type_id, branch_id, name, effective_from, is_active, created_at, updated_at)
                  VALUES (?, ?, 'Cypress roster', '2026-05-04', 1, NOW(), NOW())`,
            bindings: [typeId, TEST_BRANCH],
        }).then(rosterRes => {
            const rosterId = rosterRes.insertId;
            return cy.task<{ insertId: number }>("query", {
                sql: `INSERT INTO staff_roster_slots (roster_id, recurrence_rule, start_time, end_time,
                                                       min_staff, max_staff, created_at, updated_at)
                      VALUES (?, 'FREQ=WEEKLY;BYDAY=MO', '09:00:00', '17:00:00', 1, 1, NOW(), NOW())`,
                bindings: [rosterId],
            }).then(slotRes => ({
                rosterId,
                slotId: slotRes.insertId,
                typeId,
            }));
        });
    });
}

export function cleanupRosterFixture(f: Partial<Fixture>) {
    if (f.rosterId) {
        cy.task("query", {
            sql: `DELETE FROM staff_roster WHERE id = ?`,
            bindings: [f.rosterId],
        });
    }
    if (f.typeId) {
        cy.task("query", {
            sql: `DELETE FROM staff_roster_types WHERE id = ?`,
            bindings: [f.typeId],
        });
    }
}
```

Both helpers must be defensive against a partial setup: if the second INSERT failed, the cleanup still has to run. That's why every cleanup branch is `if (f.rosterId)` — undefined fields skip cleanly.

### Spec shape

```ts
// cypress/integration/myplugin/feature_a_spec.ts
import {
    createRosterFixture,
    cleanupRosterFixture,
    type Fixture,
    TEST_BRANCH,
} from "./_fixtures";

interface RosterWeekResponse {
    week_start: string;
    roster: { id: number; name: string };
    slots: Array<{ id: number; applies_on_dates: string[] }>;
    assignments: unknown[];
    exceptions: Array<{ exception_date: string; source?: string }>;
}

describe("MyPlugin /rosters/:id/week", () => {
    let fixture: Partial<Fixture> = {};

    before(() => { cy.login(); });

    beforeEach(() => {
        fixture = {};
        createRosterFixture().then(f => { fixture = f; });
    });

    afterEach(() => { cleanupRosterFixture(fixture); });

    it("returns the roster header + applies_on_dates", () => {
        cy.task<RosterWeekResponse>("apiGet", {
            endpoint: `/api/v1/contrib/myplugin/rosters/${fixture.rosterId}/week?start=2026-05-04`,
        }).then(res => {
            expect(res.week_start).to.eq("2026-05-04");
            expect(res.slots[0].applies_on_dates).to.deep.eq(["2026-05-04"]);
        });
    });
});
```

Notes:

- **Per-test namespace via `beforeEach` fixture** — parallel runs don't collide because each spec creates its own roster/slot ids.
- **Type the API response inside the spec** — Cypress's webpack doesn't resolve cross-tree imports cleanly, so `import type { RosterWeekResponse } from "../../../src/api"` fails. Inline the shape; the source of truth still lives in `src/api.ts`.
- **Always `cleanupRosterFixture` in `afterEach`** — leaving rows behind poisons the next run.

### Per-test cache invalidation

`Koha::Calendar` and several other Koha modules memoise expensive data in memcached for ~21h. Inserts done via `cy.task("query", ...)` are invisible to live Plack workers until the relevant cache key is dropped:

```ts
function flushHolidayCache(branchcode: string) {
    cy.exec(
        `KOHA_CONF=/etc/koha/sites/kohadev/koha-conf.xml perl -MKoha::Caches -e ` +
            `'Koha::Caches->get_instance->clear_from_cache("${branchcode}_holidays")'`,
    );
}

it("merges Koha calendar closures into the week", () => {
    cy.task("query", {
        sql: `INSERT INTO special_holidays (branchcode, day, month, year, isexception, title, description)
              VALUES (?, 5, 5, 2026, 0, 'Cypress', '')`,
        bindings: [TEST_BRANCH],
    });
    flushHolidayCache(TEST_BRANCH);
    cy.task<RosterWeekResponse>("apiGet", { endpoint: `...` }).then(res => {
        const calendarRow = res.exceptions.find(e => e.source === "calendar");
        expect(calendarRow).to.exist;
    });
});
```

Cache keys to know:

| Module | Memoises | Key shape | Where to look |
|--------|----------|-----------|---------------|
| `Koha::Calendar` | `_holidays` per branch | `<branchcode>_holidays` | `Koha/Calendar.pm` |
| `Koha::AuthorisedValues` | per category | `AuthorisedValues_<category>` | Browser, but check |
| `Koha::Patron::Categories` | full list | `categories_for_template` | `Koha/Patron/Categories.pm` |
| Sysprefs | each pref | `sysprefs_*` | `C4::Context` |

When in doubt, dump the cache: `Koha::Caches->get_instance->flush_all` between tests. Heavier, but immune to drift in the key naming.

### Wiring `just test-cypress`

```just
test-cypress:
    sh scripts/run-cypress.sh

test-cypress-spec name:
    sh scripts/run-cypress.sh "{{name}}"
```

The two-recipe form lets you run a single spec while iterating (`just test-cypress-spec get_week`).

### Pitfalls

| Pitfall | Symptom | Fix |
|---------|---------|-----|
| `docker cp` without removing the target first | New files nested inside `Koha/Koha/...` | Always `rm -rf` the target before `cp` |
| Skipping the Plack restart | Specs hit stale REST routes, 404s | `koha-plack --restart kohadev` + 3s sleep before invoking cypress |
| Calendar / AV change visible to specs but not live | Test passes / fails depending on cache age | Flush the relevant cache key after the SQL insert |
| Hardcoded borrowernumber | Test breaks on installs without that patron | Pin to a known-stable id (`SUPERLIBRARIAN_BORROWERNUMBER = 51` from the ktd seed) and document it |
| `cy.task("query", ...)` cross-spec leak | Parallel runs collide on the same row | Per-test fixture create + cleanup; never shared state |
| Spec glob picks up `_fixtures.ts` as empty suite | "Cannot find tests" warning per run | End the glob in `*_spec.ts` and prefix non-spec files with `_` |
| Importing types from `src/api.ts` | `cy run` fails to resolve | Inline the response shape inside the spec |

### Where native integration would help

- A first-class `koha-plugin add cypress` scaffolding step that drops a runner script + a fixture helper template.
- A documented `cy.task("flushCache", { module, key })` so plugins don't shell out via `cy.exec` for memcached invalidation.
- A standard plugin-install Cypress task so the runner doesn't need to invoke `perl -e ...` to call the lifecycle.
