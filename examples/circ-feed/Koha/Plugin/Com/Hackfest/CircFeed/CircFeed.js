import { ref as p, onMounted as g, onUnmounted as k, openBlock as i, createElementBlock as o, createElementVNode as t, normalizeClass as w, toDisplayString as s, createCommentVNode as C, createVNode as E, TransitionGroup as b, withCtx as x, Fragment as L, renderList as N, normalizeStyle as S } from "vue";
const T = { class: "cf-feed" }, B = { class: "cf-feed__header" }, I = {
  key: 0,
  class: "cf-feed__empty"
}, V = { class: "cf-feed__title-text" }, F = { class: "cf-feed__patron" }, z = { class: "cf-feed__library" }, D = { class: "cf-feed__time" }, O = {
  __name: "CircFeed",
  props: {
    apiBase: {
      type: String,
      default: "/api/v1/contrib/CircFeed"
    },
    maxEvents: {
      type: Number,
      default: 20
    },
    pollInterval: {
      type: Number,
      default: 3e3
    }
  },
  setup(v) {
    const r = v, n = p([]), l = p(!1);
    let d = null, _ = 0;
    const h = {
      checkout: "Check out",
      checkin: "Check in",
      renewal: "Renewal"
    }, m = {
      checkout: "#1976d2",
      checkin: "#4caf50",
      renewal: "#ff9800"
    };
    function y(a) {
      return a ? new Date(a.replace(" ", "T")).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" }) : "";
    }
    async function u() {
      try {
        const a = await fetch(`${r.apiBase}/events/recent`);
        if (!a.ok) return;
        const c = await a.json();
        l.value = !0;
        const e = c.filter((f) => f.id > _);
        if (e.length > 0) {
          for (n.value.push(...e); n.value.length > r.maxEvents; )
            n.value.shift();
          _ = Math.max(...n.value.map((f) => f.id));
        }
      } catch {
        l.value = !1;
      }
    }
    return g(async () => {
      await u(), d = setInterval(u, r.pollInterval);
    }), k(() => {
      d && clearInterval(d);
    }), (a, c) => (i(), o("div", T, [
      t("div", B, [
        c[0] || (c[0] = t("h4", { class: "cf-feed__title" }, "Live Circulation Feed", -1)),
        t("span", {
          class: w(["cf-feed__status", l.value ? "cf-feed__status--on" : "cf-feed__status--off"])
        }, s(l.value ? "Live" : "Connecting..."), 3)
      ]),
      n.value.length === 0 ? (i(), o("div", I, " Waiting for circulation activity... ")) : C("", !0),
      E(b, {
        name: "cf-event",
        tag: "div",
        class: "cf-feed__list"
      }, {
        default: x(() => [
          (i(!0), o(L, null, N([...n.value].reverse(), (e) => (i(), o("div", {
            key: e.id,
            class: "cf-feed__event"
          }, [
            t("span", {
              class: "cf-feed__badge",
              style: S({ background: m[e.event_type] || "#999" })
            }, s(h[e.event_type] || e.event_type), 5),
            t("span", V, s(e.title), 1),
            t("span", F, s(e.patron_name), 1),
            t("span", z, s(e.library), 1),
            t("span", D, s(y(e.created_at)), 1)
          ]))), 128))
        ]),
        _: 1
      })
    ]));
  }
};
export {
  O as default
};
