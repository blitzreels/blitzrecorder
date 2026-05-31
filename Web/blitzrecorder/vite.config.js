import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

export default defineConfig({
  base: "./",
  build: {
    rollupOptions: {
      input: {
        landing: "index.html",
        hub: "brand-guidelines.html",
        ios: "ios-app-store.html",
        macos: "macos-app-store.html",
        privacy: "privacy.html",
        support: "support.html",
        terms: "terms.html",
      },
    },
  },
  plugins: [react(), tailwindcss()],
});
