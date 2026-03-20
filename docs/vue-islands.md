## Vue Islands in Koha Plugins

Koha's staff interface uses an islands architecture where Vue 3 components
are rendered as custom HTML elements and hydrated on demand. Plugins can
register their own islands using the `registerIsland()` function.

### Prerequisites

This feature requires a Koha patch that has not yet been merged upstream.
The patch (Bug 42150) adds:

- `registerIsland()` — public API for plugin island registration
- `export * from "vue"` — re-exports Vue APIs from `islands.esm.js`
- Import map in `main-container.inc` — maps bare `"vue"` imports to Koha's
  bundled Vue so plugins share the same reactive runtime
- Frozen module handling — clones frozen ES module exports before passing
  to `defineCustomElement`

Without this patch, plugins cannot register islands or share Vue's runtime.
Track the patch status on [Koha Bugzilla](https://bugs.koha-community.org).

### How it works

1. `main-container.inc` loads `islands.esm.js` and declares an import map
   that resolves `"vue"` to the same module
2. `hydrate()` is called, deferred via `requestIdleCallback`
3. Plugin JS from `intranet_js` hook runs (in `intranet-bottom.inc`)
4. Plugin calls `registerIsland()` to add a component to the registry
5. Plugin calls `hydrate()` to trigger a DOM scan for its custom element
6. The plugin's pre-built SFC resolves `import { ref } from "vue"` via the
   import map, ensuring it uses Koha's Vue instance — not its own copy

### Quick start

```bash
koha-plugin add vue --name NotesPanel --tag plugin-notes-panel
npm install
npm run build
```

Then wire it up in your `intranet_js` hook (see examples below).

### Minimal inline example (h function)

For simple widgets that don't need a build step:

```perl
sub intranet_js {
    my $self = shift;

    return <<~'JS';
    <script type="module">
      const src = document.querySelector("script[src*='islands.esm']")?.src;
      if (src) {
        const { registerIsland, hydrate, h } = await import(src);

        registerIsland("plugin-my-widget", {
          importFn: async () => ({
            props: ["title"],
            setup(props) {
              return () => h("div", null, [
                h("strong", null, props.title || "My Widget"),
                h("p", null, "Hello from a plugin island!"),
              ]);
            },
          }),
          config: { stores: [] },
        });

        const main = document.querySelector(".main.container-fluid");
        if (main) {
          const el = document.createElement("plugin-my-widget");
          main.prepend(el);
        }

        hydrate();
      }
    </script>
    JS
}
```

`h()` and all Vue APIs are re-exported from `islands.esm.js`.

### Pre-built SFCs (recommended)

For anything beyond trivial widgets, use `add vue` to scaffold a full
build pipeline:

```bash
koha-plugin add vue --name NotesPanel --tag plugin-notes-panel
npm install
npm run build
```

This creates:

```
my-plugin/
  src/
    components/
      NotesPanel.vue       # Vue SFC with <template>, <script setup>, <style>
    main.js                # Entry point, exports the component
  vite.config.js           # Builds as ES module, externalizes Vue
  package.json             # Vue + vite deps, build/dev scripts
  Koha/Plugin/.../
    dist/
      NotesPanel.js        # Built ES module (served via static_routes)
      NotesPanel.css       # Extracted styles
```

**Important:** Built files go to `<plugin_dir>/dist/`, not `<plugin_dir>/static/dist/`.
Koha's `Static#get` controller resolves files relative to the plugin directory and
automatically prepends `/static/` to the URL path.

Then in your `intranet_js` hook:

```perl
sub intranet_js {
    my $self = shift;

    return <<~'JS';
    <link rel="stylesheet" href="/api/v1/contrib/myplugin/static/dist/NotesPanel.css">
    <script type="module">
      const islandsSrc = document.querySelector("script[src*='islands.esm']")?.src;
      if (islandsSrc) {
        const { registerIsland, hydrate } = await import(islandsSrc);

        registerIsland("plugin-notes-panel", {
          importFn: async () => {
            const mod = await import("/api/v1/contrib/myplugin/static/dist/NotesPanel.js");
            return mod.default;
          },
          config: { stores: [] },
        });

        const main = document.querySelector(".main.container-fluid");
        if (main) {
          const el = document.createElement("plugin-notes-panel");
          el.setAttribute("greeting", "Hello!");
          main.prepend(el);
        }

        hydrate();
      }
    </script>
    JS
}
```

After editing your `.vue` file, run `npm run build` and `koha-plugin ktd`
to see changes. Use `npm run dev` for watch mode during development.

### Styling

**Do not use `<style scoped>`.** Koha's islands use `shadowRoot: false`,
which means Vue cannot inject scoped styles (it logs a warning and ignores
them). Instead, use class-prefixed (BEM-style) selectors:

```vue
<template>
  <div class="pi-notes-panel">
    <h4 class="pi-notes-panel__title">{{ title }}</h4>
  </div>
</template>

<style>
.pi-notes-panel {
  padding: 1em;
  border-left: 4px solid #4caf50;
}
.pi-notes-panel__title {
  color: #2e7d32;
}
</style>
```

Use a plugin-specific prefix (e.g., `pi-notes-panel`) to avoid collisions
with Koha's own styles.

### Vue externalization

The generated `vite.config.js` externalizes Vue by default:

```javascript
rollupOptions: {
  external: ["vue"],
}
```

This works because Koha provides an import map that resolves `"vue"` to
`islands.esm.js`. The plugin's built component uses Koha's Vue instance,
which means:

- **Reactivity works** — `ref()`, `reactive()`, `computed()` all share
  the same reactive system as Koha's core islands
- **Tiny bundles** — the component JS is typically 1-2 KB (Vue itself is
  not duplicated)
- **`defineCustomElement` compatibility** — Koha wraps the component using
  its own `defineCustomElement`, which requires the same Vue instance

If you need to bundle Vue (e.g., for use without the Koha patch), comment
out the `external` option in `vite.config.js` and add:

```javascript
define: {
  "process.env.NODE_ENV": JSON.stringify("production"),
},
```

This produces a larger bundle (~10 KB gzipped) but is self-contained.
Note that reactivity will NOT work when Vue is bundled separately, because
Koha's `defineCustomElement` uses a different Vue instance.

### Static file serving

Plugin static files are served via the `/api/v1/contrib/<namespace>/static/`
URL prefix. This requires:

1. The `api_namespace` hook (returns your plugin's namespace string)
2. The `static_routes` hook (reads `staticapi.json`)
3. A `staticapi.json` with entries for each file

The scaffolder handles all of this when you select the `static` hook during
`init`. After building new files, regenerate the spec:

```bash
koha-plugin staticapi
```

File paths in `staticapi.json` should NOT include `/static/` — Koha
prepends it automatically. For example, a file at `<plugin_dir>/dist/App.js`
should have the key `/dist/App.js` in the spec, which produces the URL
`/api/v1/contrib/<namespace>/static/dist/App.js`.

### Known limitations

**Requires upstream Koha patch.** The `registerIsland()` function, import
map, and frozen module handling are not yet in mainline Koha. See Bug 42150.

**No shared Pinia stores.** Each call to `hydrate()` creates a new Pinia
instance. Plugin islands cannot access `mainStore`, `navigationStore`, or
`vendorStore` from core islands. This is by design — enabling shared stores
requires careful security consideration.

**No `<style scoped>`.** Vue's scoped style injection is not supported with
`shadowRoot: false`. Use BEM-prefixed class names instead.

**Props are strings.** HTML attributes are always strings. Parse complex
data in `setup()`:

```javascript
setup(props) {
  const config = JSON.parse(props.config || "{}");
}
```

**CSP nonces.** Inline `<script type="module">` tags from `intranet_js`
trigger CSP violations. As of March 2026, Koha's CSP is report-only, so
scripts execute but violations are logged.

**Custom element names must contain a hyphen.** This is a web component
spec requirement. Use names like `plugin-my-widget`.

### References

- [Vue 3 Render Functions](https://vuejs.org/guide/extras/render-function.html)
- [Vue 3 defineCustomElement](https://vuejs.org/api/custom-elements.html)
- [Import Maps (MDN)](https://developer.mozilla.org/en-US/docs/Web/HTML/Element/script/type/importmap)
- Koha islands source: `koha-tmpl/intranet-tmpl/prog/js/vue/modules/islands.ts`
- Koha island components: `koha-tmpl/intranet-tmpl/prog/js/vue/components/Islands/`
