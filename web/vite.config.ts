import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

// Pure-static viewer. Baked traces live under public/traces/.
// `BASE_PATH` overrides the public base for GH-Pages-style deploys; default '/'.
export default defineConfig({
  base: process.env.BASE_PATH ?? "/",
  plugins: [react(), tailwindcss()],
  server: { port: 5173, strictPort: true },
});
