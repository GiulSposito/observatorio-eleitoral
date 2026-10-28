// Estados por município da fixture: ready (Sankey), partial, insufficient_data, validação parcial,
// e WebAssembly indisponível (o resumo continua visível).
import { test, expect } from "@playwright/test";
import { muniUrl, openTab, collectErrors } from "./helpers.js";

test("00000 (ready): matriz com classes e Sankey", async ({ page }) => {
  const errors = collectErrors(page);
  await page.goto(muniUrl("00000", "transferencias"));
  const panel = page.locator("#panel-transferencias");
  await expect(panel.locator("table.flow-matrix")).toBeVisible();
  await expect(panel.locator(".cell-class.class-estimated").first()).toBeVisible();
  await expect(panel.getByText("Fluxos estimados entre os turnos")).toBeVisible();
  await expect(panel.locator(".js-plotly-plot .sankey")).toHaveCount(1, { timeout: 30_000 });
  expect(errors).toEqual([]);
});

test("00001 (partial): tabela com classes, sem Sankey", async ({ page }) => {
  await page.goto(muniUrl("00001", "transferencias"));
  const panel = page.locator("#panel-transferencias");
  await expect(panel.locator("table.flow-matrix")).toBeVisible();
  await expect(panel).toContainText("sem o gráfico de fluxos");
  await expect(panel.getByText("Fluxos estimados entre os turnos")).toHaveCount(0);
  await expect(panel.locator(".js-plotly-plot")).toHaveCount(0);
});

test("00002 (insufficient_data): só limites, nenhum número estimado", async ({ page }) => {
  await page.goto(muniUrl("00002", "transferencias"));
  const panel = page.locator("#panel-transferencias");
  await expect(panel).toContainText("poucas seções comparáveis");
  await expect(panel.locator("table.flow-matrix")).toBeVisible();
  await expect(panel.locator(".cell-class.class-estimated")).toHaveCount(0);
  await expect(panel).not.toContainText("intervalo de 95%");
});

test("00003 (validação parcial): aviso antes das abas e exclusões na Qualidade", async ({ page }) => {
  await page.goto(muniUrl("00003"));
  await expect(page.getByText("Verificações com ressalvas")).toBeVisible();
  await openTab(page, "Qualidade");
  const panel = page.locator("#panel-qualidade");
  await expect(panel).toContainText("Seção de voto em trânsito");
  await expect(panel).toContainText("Mudança de aptos acima da tolerância");
  await expect(panel).toContainText("Seção não instalada");
  await expect(panel).toContainText("Resultados agregados não identificam transferências individuais de voto.");
});

test("sem WebAssembly: resumo visível e aba Seções explica a indisponibilidade", async ({ page }) => {
  await page.addInitScript(() => { delete window.WebAssembly; });
  await page.goto(muniUrl("00000"));
  await expect(page.locator(".metric.slot-A strong")).toBeVisible();
  await openTab(page, "Seções");
  await expect(page.locator("#panel-secoes")).toContainText("Consulta por seção indisponível neste navegador");
  await expect(page.locator("#panel-secoes")).toContainText("O resumo e a metodologia continuam disponíveis.");
  await openTab(page, "Resumo");
  await expect(page.locator(".equation-result strong")).toBeVisible();
});

test("falha de rede no manifesto vira estado de erro, sem números", async ({ page }) => {
  await page.route("**/municipios/MG/00001/manifest.json", (route) => route.abort());
  await page.goto(muniUrl("00001"));
  await expect(page.getByText("Falha de rede")).toBeVisible();
  await expect(page.locator(".metric")).toHaveCount(0);
});

test("seções: correlação, tabela e exclusões", async ({ page }) => {
  await page.goto(muniUrl("00003", "secoes"));
  const panel = page.locator("#panel-secoes");
  await expect(panel.locator(".stat-line")).toContainText(/Correlação de Pearson: r = /);
  await expect(panel.locator(".stat-line")).toContainText("fora da análise de transição");
  await expect(panel.locator("table")).toContainText("Seção de voto em trânsito");
  await page.selectOption("#panel-secoes select >> nth=0", { index: 1 });
  await expect(panel.locator("table caption")).toContainText("seções");
});

test("seções com poucas unidades não mostram coeficiente", async ({ page }) => {
  await page.goto(muniUrl("00002", "secoes"));
  await expect(page.locator("#panel-secoes .stat-line")).toContainText("Correlação não exibida");
});
