// Acessibilidade (axe, WCAG 2.2 AA): nenhuma violação séria ou crítica; crédito presente em todas as páginas.
import { test, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";
import { muniUrl, openTab } from "./helpers.js";

async function audit(page, label) {
  const result = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"])
    .exclude(".js-plotly-plot")
    .analyze();
  const bad = result.violations.filter((v) => ["serious", "critical"].includes(v.impact));
  const summary = bad.map((v) => `${v.id} (${v.impact}): ${v.nodes.slice(0, 3).map((n) => n.target.join(" ")).join(" | ")}`);
  expect(summary, `${label}: ${summary.join("\n")}`).toEqual([]);
}

for (const path of ["index.html", "metodologia.html", "dados-e-codigo.html", "sobre.html"]) {
  test(`axe: ${path}`, async ({ page }) => {
    await page.goto(path);
    await page.waitForLoadState("networkidle");
    await audit(page, path);
  });
}

test("axe: página do município, abas Resumo, Seções, Transferências e Qualidade", async ({ page }) => {
  await page.goto(muniUrl("00000"));
  await expect(page.locator(".metric").first()).toBeVisible();
  await audit(page, "resumo");
  for (const [tab, panel] of [["Seções", "#panel-secoes table"], ["Transferências", "#panel-transferencias table"], ["Qualidade", "#panel-qualidade table"]]) {
    await openTab(page, tab);
    await expect(page.locator(panel).first()).toBeVisible();
    await audit(page, tab);
  }
});

for (const path of ["index.html", "explorar.html", "metodologia.html", "dados-e-codigo.html", "sobre.html"]) {
  test(`crédito da ideia no rodapé: ${path}`, async ({ page }) => {
    await page.goto(path);
    const link = page.locator("footer").getByRole("link", { name: "thread de Rômulo Fiúza e Mello" });
    await expect(link).toHaveAttribute("href", "https://x.com/fiuzaemello/status/2114763737425211824");
    await expect(page.locator("footer")).toContainText("@fiuzaemello");
  });
}

test("página Sobre tem a seção Origem da análise", async ({ page }) => {
  await page.goto("sobre.html");
  await expect(page.getByRole("heading", { name: "Origem da análise" })).toBeVisible();
  await expect(page.locator("main")).toContainText("Rômulo Fiúza e Mello");
});

for (const path of ["index.html", "metodologia.html", "dados-e-codigo.html", "sobre.html"]) {
  test(`um único H1 visível: ${path}`, async ({ page }) => {
    await page.goto(path);
    await expect(page.locator("h1:visible")).toHaveCount(1);
  });
}

test("foco visível e link de pular para o conteúdo", async ({ page }) => {
  await page.goto("index.html");
  await page.keyboard.press("Tab");
  const skip = page.getByRole("link", { name: "Pular para o conteúdo" });
  await expect(skip).toBeFocused();
});
