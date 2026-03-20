## Vue Islands in Koha Plugins

Koha's staff interface uses an islands architecture where Vue 3 components
are rendered as custom HTML elements and hydrated on demand. Plugins can
register their own islands using the `registerIsland()` function.

### How it works

1. `islands.esm.js` is loaded in `main-container.inc`
2. `hydrate()` is called, deferred via `requestIdleCallback`
3. Plugin JS from `intranet_js` hook runs (in `intranet-bottom.inc`)
4. Plugin calls `registerIsland()` to add a component to the registry
5. Plugin calls `hydrate()` to trigger a DOM scan for its custom element

### Minimal example

```perl
sub intranet_js {
    my $self = shift;

    return <<~'JS';
    <plugin-my-widget></plugin-my-widget>
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

        hydrate();
      }
    </script>
    JS
}
```

### Using Vue's h() function

Koha bundles the Vue runtime-only build (no template compiler). This means
you **cannot** use `template: '...'` strings in inline components. You have
two options:

#### Option 1: Render functions with h()

The `h()` function (short for "hyperscript") creates virtual DOM nodes.
It is re-exported from `islands.esm.js` for plugin convenience.

```javascript
// h(tag, props, children)
h("div", { class: "alert" }, [
  h("h3", null, "Title"),
  h("p", null, "Content"),
])
```

**Common patterns:**

```javascript
// Text content
h("p", null, "Hello")

// HTML attributes and styles
h("div", {
  class: "btn btn-primary",
  style: "margin: 1em",
  onClick: () => alert("clicked"),
}, "Click me")

// Conditional rendering
h("div", null, [
  isActive ? h("span", null, "Active") : h("span", null, "Inactive"),
])

// List rendering
h("ul", null,
  items.map(item => h("li", { key: item.id }, item.name))
)

// Reactive state with setup()
setup(props) {
  const count = ref(0);
  return () => h("div", null, [
    h("p", null, `Count: ${count.value}`),
    h("button", { onClick: () => count.value++ }, "Increment"),
  ]);
}
```

For `ref` and other Vue reactivity APIs, import them alongside `h`:

```javascript
// These are not currently re-exported from islands.esm.js
// For reactive state, pre-build your component (see Option 2)
```

#### Option 2: Pre-built SFCs (recommended for complex UIs)

For anything beyond simple widgets, build your Vue Single File Components
with vite or rspack and serve the output via `static_routes`.

```
my-plugin/
  src/
    MyWidget.vue         # Standard Vue SFC with <template>
    main.js              # Exports the component as default
  vite.config.js
  Koha/Plugin/.../
    static/dist/
      MyWidget.js        # Built ES module
```

`vite.config.js`:
```javascript
import { defineConfig } from "vite";
import vue from "@vitejs/plugin-vue";

export default defineConfig({
  plugins: [vue()],
  build: {
    lib: {
      entry: "src/main.js",
      formats: ["es"],
      fileName: "MyWidget",
    },
    outDir: "Koha/Plugin/.../static/dist",
    rollupOptions: {
      external: ["vue"],
    },
  },
});
```

`src/main.js`:
```javascript
import MyWidget from "./MyWidget.vue";
export default MyWidget;
```

Then in `intranet_js`:
```javascript
registerIsland("plugin-my-widget", {
  importFn: () => import("/api/v1/contrib/myplugin/static/dist/MyWidget.js"),
  config: { stores: [] },
});
```

This gives you full `<template>` support, `<style scoped>`, and all Vue features.

### Known limitations

**No shared stores with core islands.** Each call to `hydrate()` creates
a new Pinia instance. Plugin islands get their own store instances, separate
from the ones core islands use. Plugins that need `mainStore` or
`vendorStore` will get empty/fresh copies. This is a known limitation that
requires careful design before being enabled.

**Props are strings.** HTML attributes are always strings. To pass complex
data, use JSON in an attribute and parse it in `setup()`:

```javascript
// HTML: <plugin-widget config='{"items":[1,2,3]}'></plugin-widget>
setup(props) {
  const config = JSON.parse(props.config || "{}");
  // ...
}
```

**No CSS encapsulation.** Islands render with `shadowRoot: false`, so
plugin styles affect the whole page and Koha styles affect the plugin.
Use specific class prefixes to avoid collisions.

**Timing.** `requestIdleCallback` is a hint — the browser may fire it
before the plugin's module script finishes. The manual `hydrate()` call
at the end of the plugin script ensures the island is picked up. Calling
`hydrate()` multiple times is safe — components already registered with
`customElements.define()` are skipped.

**Custom element names must contain a hyphen.** This is a web component
spec requirement. Names like `mywidget` will fail; use `my-widget` or
`plugin-mywidget`.

**CSP nonces.** Inline `<script type="module">` tags injected via
`intranet_js` may trigger CSP violations. As of March 2026, Koha's CSP
is report-only, so scripts execute but violations are logged. A future
Koha release may require nonces on plugin scripts.

### References

- [Vue 3 Render Functions](https://vuejs.org/guide/extras/render-function.html)
- [Vue 3 defineCustomElement](https://vuejs.org/api/custom-elements.html)
- Koha islands source: `koha-tmpl/intranet-tmpl/prog/js/vue/modules/islands.ts`
- Koha island components: `koha-tmpl/intranet-tmpl/prog/js/vue/components/Islands/`
