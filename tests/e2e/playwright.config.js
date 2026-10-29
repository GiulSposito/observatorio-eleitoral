// Testes E2E contra o site renderizado (web/_site) com o bundle sintético DEMO-001.
// Antes: web/scripts/use-fixture.sh && quarto render web
// SITE_DIR permite apontar para outra pasta renderizada.

import { defineConfig, devices } from "@playwright/test";

const siteDir = process.env.SITE_DIR || "../../web/_site";
const port = Number(process.env.PORT || 4173);

export default defineConfig({
  testDir: "./specs",
  timeout: 60_000,
  expect: { timeout: 15_000 },
  fullyParallel: false,
  workers: 2,
  reporter: [["list"]],
  use: {
    baseURL: `http://localhost:${port}/`,
    locale: "pt-BR",
    timezoneId: "America/Sao_Paulo",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
  webServer: {
    command: `node server.mjs ${siteDir} ${port}`,
    url: `http://localhost:${port}/index.html`,
    reuseExistingServer: true,
    timeout: 30_000,
  },
});
