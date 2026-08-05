import { defineConfig } from "astro/config";
import tailwindcss from "@tailwindcss/vite";

export default defineConfig({
  output: "static",
  site: "https://baros.fit",
  trailingSlash: "never",
  vite: {
    plugins: [tailwindcss()],
  },
});
