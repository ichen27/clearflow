import { cloudflareTest } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";
// Only this test process receives the dummy credential; real AI is disabled below.
process.env.AUTH_TOKEN = "test-only-token";
export default defineConfig({
  plugins: [cloudflareTest({
    remoteBindings: false,
    wrangler: { configPath: "./wrangler.jsonc" },
    miniflare: { bindings: { AUTH_TOKEN: "test-only-token" } },
  })],
});
