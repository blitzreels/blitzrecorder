import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

export default defineConfig({
  base: "./",
  build: {
    rollupOptions: {
      input: {
        hub: "brand-guidelines.html",
        ios: "ios-app-store.html",
        macos: "macos-app-store.html",
      },
    },
  },
  plugins: [react(), tailwindcss()],
});
