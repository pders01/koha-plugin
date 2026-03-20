import { defineConfig } from "vite";
import vue from "@vitejs/plugin-vue";

export default defineConfig({
  plugins: [vue()],
  define: {
    "process.env.NODE_ENV": JSON.stringify("production"),
  },
  build: {
    lib: {
      entry: "src/main.js",
      formats: ["es"],
      fileName: "CircFeed",
    },
    outDir: "Koha/Plugin/Com/Hackfest/CircFeed",
    emptyOutDir: false,
    rollupOptions: {
      external: ["vue"],
    },
  },
});
