## Matching Koha's staff UI conventions

Plugin pages render inside the staff intranet. Default Koha CSS, layout, and JavaScript helpers are already on the page; matching the conventions makes a plugin look native, lets DataTables / flatpickr / Bootstrap modals work without bundling, and gives admins consistent muscle memory across plugins. Drift from the conventions is the most common reason plugins feel like "tacked-on tools."

This is the boilerplate every staff-side template should share. None of it is documented in core; it is reverse-engineered from `koha-tmpl/intranet-tmpl/prog/en/modules/...` and the plugin runner.

### Page chrome

```html
[% USE raw %]
[% USE Koha %]
[% USE KohaDates %]
[% PROCESS 'i18n.inc' %]
[% SET footerjs = 1 %]
[% INCLUDE 'doc-head-open.inc' %]
<title>
    [% IF op == 'add_form' %]
        [% IF roster_type.id %]Modify roster type[% ELSE %]New roster type[% END %] &rsaquo;
    [% ELSIF op == 'delete_confirm' %]
        Confirm deletion &rsaquo;
    [% END %]
    Staff Roster | Plugins | Koha
</title>
[% INCLUDE 'doc-head-close.inc' %]
<link rel="stylesheet" href="/api/v1/contrib/<namespace>/static/<plugin>.css" />
</head>

<body id="plugins_<plugin>_admin" class="plugins">
[% WRAPPER 'header.inc' %]
    [% INCLUDE 'prefs-admin-search.inc' %]
[% END %]

[% WRAPPER 'sub-header.inc' %]
    [% WRAPPER breadcrumbs %]
        [% WRAPPER breadcrumb_item %]
            <a href="/cgi-bin/koha/plugins/plugins-home.pl">Plugins</a>
        [% END %]
        [% WRAPPER breadcrumb_item bc_active = 1 %]
            <span>Roster Types</span>
        [% END %]
    [% END %]
[% END %]
```

Required for the page to look native:

- **`USE raw`** — needed for any `[% ... | $raw %]` filter you reach for in i18n strings.
- **`SET footerjs = 1`** — Koha defers script loading. Without it, `[% MACRO jsinclude %]` content lands at the top, blocking render.
- **`doc-head-open.inc` + `doc-head-close.inc`** — they pull every Koha stylesheet, font, and the `intranet_head` plugin contributions. Skip them and your page loses every shared style.
- **Body id `plugins_<slug>_<view>`** — Koha's stylesheet has selectors keyed on `body[id^="plugins_"]`; the [permission label injector](plugin-permissions.md) and other `intranet_js` snippets gate on body id. Pick a unique slug per view.
- **`class="plugins"`** — adds the plugin chrome (top bar styling, etc.) without it the page looks orphaned.
- **`prefs-admin-search.inc`** — gives the standard search input on the staff header. Use it on admin-style pages, swap to `circ-search.inc` or `cat-search.inc` for tool / report views as appropriate.
- **Static CSS via the plugin's static API** — see [`plugin-rest-api.md`](plugin-rest-api.md) for the `static_routes` hook. Avoid inline `<style>` blocks; they fight Koha's theming.

### Sidebar layout

Koha's two-column layout puts navigation in a right rail. Wrap the main content in `<main>` inside a 10-column block, with the sidebar as a 2-column block ordered second on mobile:

```html
[% BLOCK staff_roster_aside %]
<aside>
    <div class="<plugin>-menu sidebar_menu">
        <h5>Staff Roster</h5>
        <ul>
            <li class="active"><a href="...&method=tool">Rosters</a></li>
            <li><a href="...&method=tool&op=add_roster">New roster</a></li>
        </ul>
        <h5>Administration</h5>
        <ul>
            <li><a href="...&method=admin">Roster types</a></li>
            <li><a href="...&method=configure">Configuration</a></li>
        </ul>
    </div>
</aside>
[% END %]

<div class="main container-fluid">
    <div class="row">
        <div class="col-md-10 order-sm-1 order-md-2">
            <main>
                <!-- page content -->
            </main>
        </div>
        <div class="col-md-2 order-sm-2 order-md-1">
            [% PROCESS staff_roster_aside %]
        </div>
    </div>
</div>
```

`sidebar_menu` is the canonical Koha class — picking another name means losing the typography rules that ship with the staff theme. Mark the current entry with `class="active"` so it visually anchors.

### Page sections

Wrap each logical block in `page-section` so it picks up the standard card chrome:

```html
<div class="page-section">
    <h2>Time slots</h2>
    <table class="table">...</table>
</div>
```

Stacked `page-section` divs render as separated cards with the right spacing, shadow, and inner padding. A bare `<div>` looks raw.

### Tables: DataTables, not custom JS

Koha ships DataTables. Always use it; skip the bespoke pagination / search code most prototypes start with.

```html
<table id="rosters_table" class="table">
    <thead>...</thead>
    <tbody>...</tbody>
</table>

[% MACRO jsinclude BLOCK %]
    [% INCLUDE 'datatables.inc' %]
    <script>
    $(document).ready(function() {
        if ($("#rosters_table").length) {
            $("#rosters_table").dataTable($.extend(true, {}, dataTablesDefaults, {
                columnDefs: [{ targets: -1, orderable: false, searchable: false }],
                order: [[0, "asc"]]
            }));
        }
    });
    </script>
[% END %]
```

`dataTablesDefaults` is provided by the staff theme. Extending it (vs replacing it) keeps the look consistent with every other table in Koha.

### Date inputs: `flatpickr`

```html
<input type="text" name="effective_from" class="flatpickr" />

[% INCLUDE 'calendar.inc' %]
<script>
$(document).ready(function() {
    $(".flatpickr").flatpickr({ dateFormat: "Y-m-d" });
});
</script>
```

`calendar.inc` brings in flatpickr. Locking `dateFormat: "Y-m-d"` keeps the saved value matching the database column. The visible format adjusts to the user's locale automatically.

### Bootstrap modals (not native `confirm()`)

Replace every `if (confirm('Delete?'))` with a Bootstrap modal. Native dialogs look out of place and are unreviewable for accessibility and i18n.

```html
<button type="button" class="btn btn-default btn-xs slot-delete-trigger"
        data-bs-toggle="modal"
        data-bs-target="#delete-slot-modal"
        data-slot-id="[% slot.id | html %]"
        data-slot-info="[% slot.label | html %]">
    <i class="fa fa-trash"></i> Delete
</button>

<div class="modal" id="delete-slot-modal" tabindex="-1"
     aria-labelledby="delete-slot-modal-label" aria-hidden="true">
    <div class="modal-dialog">
        <div class="modal-content">
            <form method="post" action="/cgi-bin/koha/plugins/run.pl">
                [% INCLUDE 'csrf-token.inc' %]
                <input type="hidden" name="class"  value="[% CLASS | html %]" />
                <input type="hidden" name="method" value="tool" />
                <input type="hidden" name="op"     value="cud-delete_slot" />
                <input type="hidden" name="slot_id" id="delete-slot-id" value="" />
                <div class="modal-header">
                    <h1 class="modal-title" id="delete-slot-modal-label">Delete time slot?</h1>
                    <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
                </div>
                <div class="modal-body">
                    <p>Delete <strong id="delete-slot-info"></strong>?</p>
                </div>
                <div class="modal-footer">
                    <button type="submit" class="btn btn-danger"><i class="fa fa-trash"></i> Delete</button>
                    <button type="button" class="btn btn-default" data-bs-dismiss="modal"><i class="fa fa-times"></i> Cancel</button>
                </div>
            </form>
        </div>
    </div>
</div>

<script>
$(document).on("click", ".slot-delete-trigger", function() {
    var $btn = $(this);
    $("#delete-slot-id").val($btn.data("slot-id"));
    $("#delete-slot-info").text($btn.data("slot-info") || "");
});
</script>
```

Notes:

- **Always include `csrf-token.inc`** in forms. Plugin endpoints inherit the same CSRF check as core.
- **`cud-` op prefix** for destructive forms — the convention Koha uses to gate them via the staff client policy.
- **Modal IDs and labels** must be unique per page; Bootstrap targets them by id.
- **Trigger via `data-bs-toggle="modal"`** — calling `$('#m').modal('show')` works too but conflicts with the staff theme's keyboard shortcuts.

### Forms: `class="validated"`

Adding `class="validated"` opts the form into Koha's HTML5 validation styling and `novalidate` handling. Combine with the `required` attribute and pattern hints; you get the standard error rendering for free.

```html
<form method="post" action="/cgi-bin/koha/plugins/run.pl" class="validated">
    [% INCLUDE 'csrf-token.inc' %]
    <input type="hidden" name="class"  value="[% CLASS | html %]" />
    <input type="hidden" name="method" value="admin" />
    <input type="hidden" name="op"     value="cud-save" />
    ...
</form>
```

### Light-DOM Lit components

Web components default to shadow DOM, which isolates them from Koha's stylesheets — the result looks unstyled and ignores the theme. Override `createRenderRoot` to render into the light DOM so Koha CSS applies:

```js
import { LitElement, html } from 'lit';

class RosterGrid extends LitElement {
    createRenderRoot() { return this; }   // light DOM, Koha CSS applies

    render() {
        return html`
            <div class="page-section">...</div>
        `;
    }
}
customElements.define('roster-grid', RosterGrid);
```

In the template, mount via the static API URL and pass props through attributes:

```html
<script type="module" src="/api/v1/contrib/<namespace>/static/<plugin>.js"></script>
<roster-grid roster-id="[% roster.id | html %]" week-start="[% week_start | html %]"></roster-grid>
```

This keeps the bundle small (no per-component shadow root, no scoped style copying) and makes the staff theme's typography, buttons, and spacing apply to your component without porting them.

### Shared TT includes for repeated chrome

Plugins with multiple entrypoints (`tool`, `admin`, `configure`, `report`) end up with near-duplicate sidebar markup, post-redirect-get guards, and modal skeletons across templates. Pull the shared markup into plugin-local includes referenced via `PLUGIN_DIR`:

```html
[% INCLUDE "${PLUGIN_DIR}/_aside.inc" aside_active = 'configure' %]
[% INCLUDE "${PLUGIN_DIR}/_prg_guard.inc" prg_method = 'admin' prg_op = 'list' %]
```

Koha sets `PLUGIN_DIR` on every plugin template render; combined with `C4::Templates`' `ABSOLUTE => 1` flag, the include path resolves cleanly. Convention: prefix shared partials with `_` so they sort first and read as private to the plugin.

Two examples worth shipping in every plugin:

- **`_aside.inc`** — sidebar navigation parametrised by `aside_active`. Each top-level template sets the field and includes the partial in one line. Adding a new sidebar entry is one edit, not three.
- **`_prg_guard.inc`** — Post-Redirect-Get script. After a successful `cud-` POST, replace the URL with the GET landing URL via `history.replaceState` so a browser refresh doesn't re-POST. Parametrise by `prg_method` (`tool`/`admin`/`configure`) and `prg_op`.

```html
<!-- _prg_guard.inc -->
[% IF post_redirect_op || prg_op %]
<script>
    if (window.history && window.history.replaceState) {
        var url = '/cgi-bin/koha/plugins/run.pl?class=[% CLASS | uri %]&method=[% prg_method | uri %]';
        [% IF prg_method != 'configure' %]
        url += '&op=[% (prg_op || post_redirect_op) | uri %]';
        [% END %]
        [% IF prg_roster_id || post_redirect_roster_id %]
        url += '&roster_id=[% (prg_roster_id || post_redirect_roster_id) | uri %]';
        [% END %]
        window.history.replaceState({}, '', url);
    }
</script>
[% END %]
```

The same dedup applies to JS: extract `renderModalShell`, `renderToasts`, `renderWeekToolbar`, `renderDayGroups` into `src/components/shared/` and reuse across components. Bundle drops measurably (~3KB after dedup in staff-roster) and three near-identical Bootstrap modals collapse to one parametrised render function.

### Lit modal Escape handling via `ReactiveController`

Multiple modals on the same component each register their own keydown listener — easy to leak, easy to forget the priority order. Use a small `ReactiveController` so every modal registers its own predicate + cancel and the controller wires the doc listener once:

```ts
import type { ReactiveController, ReactiveControllerHost } from "lit";

export class EscapeController implements ReactiveController {
  constructor(
    private host: ReactiveControllerHost,
    private isActive: () => boolean,
    private onEscape: () => void,
  ) {
    host.addController(this);
  }

  hostConnected(): void  { document.addEventListener("keydown", this.onKey); }
  hostDisconnected(): void { document.removeEventListener("keydown", this.onKey); }

  private onKey = (e: KeyboardEvent): void => {
    if (e.key !== "Escape") return;
    if (!this.isActive()) return;
    e.preventDefault();
    e.stopPropagation();
    this.onEscape();
  };
}
```

Usage — one controller per cancellable state, registration order is priority:

```ts
constructor() {
  super();
  new EscapeController(this, () => this.pendingDrop !== null, () => this.cancelDrop());
  new EscapeController(this, () => this.editing !== null,     () => this.cancelEdit());
  new EscapeController(this, () => this.dragging !== null,    () => this.cancelDrag());
}
```

`preventDefault` + `stopPropagation` ensure the keystroke doesn't leak past the cancel. `hostConnected` / `hostDisconnected` mean the listener auto-cleans when the component leaves the DOM — no per-modal teardown.

### One state machine, two input modes (drag + tap/keyboard)

A grid that supports both HTML5 drag-and-drop and keyboard / touch pickup will accumulate two parallel state machines: `dragging` for the DnD path, `pickedUp` for the keyboard / touch path. They drift in subtle ways — Esc cancels one but not the other, a user can start a drag while a keyboard pickup is still set, and dragend cleanup handlers leak state from the unrelated machine.

Unify both into a single `activeCargo` + `activeMode` pair, with derived getters that preserve the previous read-side API:

```ts
type Cargo = { kind: "staff"; id: number } | { kind: "assignment"; id: number };
type Mode  = "drag" | "pickup" | null;

@state() private activeCargo: Cargo | null = null;
@state() private activeMode: Mode = null;

private get dragging(): Cargo | null {
    return this.activeMode === "drag" ? this.activeCargo : null;
}
private get pickedUp(): Cargo | null {
    return this.activeMode === "pickup" ? this.activeCargo : null;
}

private setActiveCargo(cargo: Cargo, mode: "drag" | "pickup"): void {
    this.activeCargo = cargo;
    this.activeMode = mode;
}

private clearActiveCargo(): void {
    this.activeCargo = null;
    this.activeMode = null;
    // Drop visual indicator on any cell still flagged after dragend / Esc
    // (the pointer may have left a cell that previously took dragover).
    for (const el of this.querySelectorAll(".srg-dropping")) {
        el.classList.remove("srg-dropping");
    }
}
```

Three follow-on rules unblocked by the unified state:

- **`EscapeController` for `activeMode === "drag"`** — register a controller that cancels mid-flight drags, not just keyboard pickups. Same shape as the others; different predicate.
- **`@dragend` on staff pills + assignment chips** — call `clearActiveCargo()` so a browser-level drag aborted off-target doesn't leak state until the next pickup overrides it.
- **Pre-refresh clear** — clear cargo before the post-drop fetch so the [poll-race guard](#poll-race-guard-via-fetch-generation) doesn't swallow your own response.

Two-mode read API stays intact: every call site that asks "is the user dragging?" or "did the user pick something up?" works unchanged. The write side funnels through one entry point.

### Touch UX: piggy-back keyboard pickup, not HTML5 drag-and-drop

HTML5 drag-and-drop never fires touch events. A grid that relies on `dragstart`/`drop` is read-only on phones. The minimal fix: route taps through the same pickup-and-drop state machine you already wrote for keyboard accessibility (Space to pick, Enter to drop, Esc to cancel).

```ts
// Tap on a staff pill toggles the pickup; tap on a cell completes the drop.
private onPillClick(pill: Pill, e: Event) {
    e.preventDefault();
    if (this.pickedUp?.id === pill.id) {
        this.pickedUp = null;
        return;
    }
    this.pickedUp = pill;
}

private onCellClick(cell: Cell, e: Event) {
    if (!this.pickedUp) return;
    e.preventDefault();
    void this.dropFromKeyboard(cell);   // shared with Space+Enter path
    this.pickedUp = null;
}
```

iOS Safari needs `cursor: pointer` on the drop-target `<td>` for synthesized click events to fire on touch. Without it, taps register as scroll attempts. Adding it has no visual effect on desktop but unblocks touch.

### iOS Safari: force reflow after optimistic insert

`table-layout: fixed` plus a chip inserted into an existing cell sometimes skips the iOS Safari reflow — the chip exists in the DOM but isn't painted until the next user-triggered repaint (resize, scroll). Read `offsetWidth` after the update completes to kick the table:

```ts
private async refresh(): Promise<void> {
    const myGen = ++this.fetchGeneration;
    const forceReflow = () => {
        const tbl = this.querySelector(".srg-grid") as HTMLElement | null;
        if (tbl) void tbl.offsetWidth;        // layout read forces repaint
    };
    const next = await fetchWeek(this.rosterId, this.weekStart);
    if (this.dragging || myGen !== this.fetchGeneration) return;
    this.week = next;
    void this.updateComplete.then(forceReflow);
}
```

`void tbl.offsetWidth` discards the read; the side effect is what matters. Trigger after `updateComplete` so Lit has flushed the DOM.

### Poll-race guard via fetch generation

Long-lived components that both poll and react to user-driven mutations need to discard stale in-flight responses. A monotonic generation counter incremented per `refresh()` call makes the loser self-discard:

```ts
private fetchGeneration = 0;

private async refresh(): Promise<void> {
    const myGen = ++this.fetchGeneration;
    const next = await fetchWeek(this.rosterId, this.weekStart);
    // Drop the result if (a) a drag is still in flight, or
    // (b) a newer refresh started after us — applying our older
    // response would clobber the fresher state.
    if (this.dragging || myGen !== this.fetchGeneration) return;
    this.week = next;
}
```

The same pattern handles polling overlap: if a 30s timer fires while a user-driven refresh is in flight, the loser's response gets dropped.

### Responsive forms for translated copy

Koha's `fieldset.rows` layout has a fixed-width label column that runs off the right edge when localized strings stretch (German compound nouns are the typical victim). Three additions keep forms usable below 768px and tolerant of long labels:

```css
/* Hints flow under the input, capped to readable width. */
.rows li .hint {
    display: block;
    margin-left: 10rem;          /* matches Koha .rows label column */
    max-width: 60ch;
    color: #555;
    font-size: 0.875rem;
}

/* Long compound nouns wrap inside the label column. */
.rows li label {
    overflow-wrap: anywhere;
    hyphens: auto;
}

/* Below 768px: label-on-top, full-width input. */
@media (max-width: 768px) {
    .rows li {
        display: block;
    }
    .rows li label {
        display: block;
        width: auto;
        margin-bottom: 0.25rem;
        text-align: left;
    }
    .rows li input,
    .rows li select,
    .rows li textarea {
        width: 100%;
        max-width: none;
    }
    .rows li .hint {
        margin-left: 0;
    }
}
```

Mirrors Koha's newer `fg/fg-row` grid since `fieldset.rows` is too widespread to migrate wholesale.

### Sidebar filter tile alignment

A filter form rendered next to `_aside.inc` should match the sidebar's padding so both tiles dock to the same x. Koha's `.sidebar_menu` uses `padding: 1em` and pulls the `<aside>` left with a negative margin in this column. Mirror both:

```css
.staff-roster-filter {
    margin: 0 -10px;             /* match Koha's <aside> negative pull */
    padding: 1em;                /* match .sidebar_menu rhythm */
}
.staff-roster-filter .form-group {
    padding: 0 0.25rem;          /* symmetric, so equal left/right balances */
}
.staff-roster-filter .form-control {
    width: 100%;                 /* full-width input keeps tile balanced */
}
```

Without these, the filter heading lands a few pixels right of the menu items below it. Visible on every render but easy to miss until a designer points it out.

### Mobile: sticky anchor column + responsive grid

Wide grids (8 columns × tall slot rows) overflow phone viewports. Two patterns, applied together, keep the layout usable:

1. **Sticky anchor column.** Make the leftmost column (slot time, day name, whatever the row identifier is) `position: sticky; left: 0` so it stays visible while day cells scroll horizontally. Match its background to the page so cells beneath it don't bleed through, and add a 1px right shadow as a visual seam.
2. **`min-width` + horizontal scroll wrapper.** Force the table to a comfortable minimum width (`720px`) and wrap it in a `overflow-x: auto` div. Below the breakpoint the table scrolls instead of squishing weekday cells.

```css
.srg-grid-wrap   { overflow-x: auto; -webkit-overflow-scrolling: touch; }
.srg-grid        { min-width: 720px; }

.srg-slot-col,
.srg-slot-cell {
    position: sticky;
    left: 0;
    background: var(--bs-body-bg, #fff);
    box-shadow: 1px 0 0 0 rgba(0, 0, 0, 0.08);
    z-index: 1;
}

@media (max-width: 575px) {
    .srg-slot-col,
    .srg-slot-cell { min-width: 88px; }
    .srg-grid-cell { padding: 4px; height: 56px; }
    .srg-chip      { font-size: 0.75rem; }
}
```

Tighten cell density at the phone breakpoint — narrower slot column, shorter cell height, smaller chip font — so a typical week fits without nesting scrollbars vertically.

### Toasts for transient errors

Long-running components (a Lit grid, a drag-and-drop UI) need feedback that doesn't reflow the layout when an API call fails. Render a fixed-position toast container outside the document flow:

```html
<div id="rg-toast" class="rg-toast" role="status" aria-live="polite" hidden></div>

<style>
.rg-toast {
    position: fixed; top: 1rem; right: 1rem; z-index: 1080;
    background: #fdecea; border: 1px solid #f5c6cb; color: #842029;
    padding: 0.5rem 0.75rem; border-radius: 4px; box-shadow: 0 2px 8px rgba(0,0,0,0.08);
}
</style>

<script>
function showToast(msg) {
    var t = document.getElementById('rg-toast');
    t.textContent = msg; t.hidden = false;
    setTimeout(function () { t.hidden = true; }, 4000);
}
</script>
```

The point is `position: fixed` — inline alerts inside a grid component cause jumpy layouts during validation cycles.

### Pitfalls

| Pitfall | Symptom | Fix |
|---------|---------|-----|
| Skipping `doc-head-open.inc` | Page renders unstyled | Always `INCLUDE` it before `</head>` |
| Inline `<style>` block | Fights Koha theming, breaks dark mode | Bundle in static CSS via `static_routes` |
| Generic `body id` | `intranet_js` injectors can't gate on it | Use `plugins_<slug>_<view>` |
| Native `confirm()` | Inaccessible, untranslatable, looks foreign | Bootstrap modal with `data-bs-toggle` |
| Shadow-DOM Lit components | No Koha styles, looks unstyled | Override `createRenderRoot` to return `this` |
| Custom pagination JS | Inconsistent UX, more code to maintain | DataTables with `dataTablesDefaults` |
| Inline alerts inside grids | Layout jumps on every validation error | Fixed-position toast container |
| Skipping `csrf-token.inc` | Form gets rejected | Include it inside every `<form>` posting to `run.pl` |
| Mixed `cud-` and bare ops | Destructive forms fall through CSRF policy | Prefix every mutating op with `cud-` |

### Where native integration would help

- A `Koha::Plugin::View::Base` that emits the chrome + sidebar wrapper from a single hook so plugins don't copy this scaffold per template.
- Built-in helpers for breadcrumbs and active-link marking driven by route metadata.
- A documented contract for "plugin-rendered web component" — current best practice (light DOM, static API, Koha CSS) is undocumented.
- Standard toast / notification slot in the staff theme so plugins don't ship competing toast implementations.
