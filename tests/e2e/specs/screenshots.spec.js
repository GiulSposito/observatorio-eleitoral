// Screenshots em 375, 768 e 1440 px para revisão visual (tests/e2e/screenshots/, gitignored)
// e verificação de que nenhuma página rola na horizontal.
import { test, expect } from "@playwright/test";
import { muniUrl, openTab } from "./helpers.js";

const WIDTHS = [375, 768, 1440];
const DIR = new URL("../screenshots/", import.meta.url).pathname;

async function noHorizontalScroll(page) {
  const over = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  expect(over, "a página não pode rolar na horizontal").toBeLessThanOrEqual(1);
}

for (const width of WIDTHS) {
  test.describe(`${width}px`, () => {
    test.use({ viewport: { width, height: 900 } });

    test("home", async ({ page }) => {
      await page.goto("index.html");
      await expect(page.getByRole("combobox", { name: "Buscar município" })).toBeVisible();
      await noHorizontalScroll(page);
      await page.screenshot({ path: `${DIR}home-${width}.png`, fullPage: true });
    });

    test("município: abas", async ({ page }) => {
      await page.goto(muniUrl("00000"));
      await expect(page.locator(".metric").first()).toBeVisible();
      await noHorizontalScroll(page);
      await page.screenshot({ path: `${DIR}resumo-${width}.png`, fullPage: true });
      for (const [tab, slug, ready] of [
        ["Seções", "secoes", "#panel-secoes table"],
        ["Transferências", "transferencias", "#panel-transferencias .js-plotly-plot"],
        ["Cenários", "cenarios", "#panel-cenarios table"],
        ["Qualidade", "qualidade", "#panel-qualidade table"],
      ]) {
        await openTab(page, tab);
        await expect(page.locator(ready).first()).toBeVisible({ timeout: 30_000 });
        await page.waitForTimeout(400);
        await noHorizontalScroll(page);
        await page.screenshot({ path: `${DIR}${slug}-${width}.png`, fullPage: true });
      }
    });

    test("metodologia", async ({ page }) => {
      await page.goto("metodologia.html");
      await expect(page.locator("#metodo-dinamico table")).toBeVisible();
      await noHorizontalScroll(page);
      await page.screenshot({ path: `${DIR}metodologia-${width}.png`, fullPage: true });
    });
  });
}
