// URL compartilhável, Voltar/Avançar, abas por teclado e troca de município sem dados residuais.
import { test, expect } from "@playwright/test";
import { muniUrl, openTab, searchAndPick, collectErrors } from "./helpers.js";

test("URL direta abre o município na aba pedida e sobrevive ao recarregar", async ({ page }) => {
  const errors = collectErrors(page);
  await page.goto(muniUrl("00003", "qualidade"));
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Porto das Águas, Santa Catarina");
  await expect(page.getByRole("tab", { name: "Qualidade" })).toHaveAttribute("aria-selected", "true");
  await expect(page.locator("#panel-qualidade")).toContainText("Qualidade, cobertura e proveniência");
  await page.reload();
  await expect(page.getByRole("tab", { name: "Qualidade" })).toHaveAttribute("aria-selected", "true");
  expect(errors).toEqual([]);
});

test("Voltar e Avançar trocam de município", async ({ page }) => {
  await page.goto(muniUrl("00000"));
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Cidade Modelo, Goiás");
  await searchAndPick(page, "Trocar município", "vale sereno mg", /Vale Sereno — MG/);
  await expect(page).toHaveURL(/m=00001/);
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Vale Sereno, Minas Gerais");
  await page.goBack();
  await expect(page).toHaveURL(/m=00000/);
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Cidade Modelo, Goiás");
  await page.goForward();
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Vale Sereno, Minas Gerais");
});

test("abas respondem a setas, Home e End e atualizam a URL", async ({ page }) => {
  await page.goto(muniUrl("00000"));
  const resumo = page.getByRole("tab", { name: "Resumo" });
  await resumo.focus();
  await page.keyboard.press("ArrowRight");
  await expect(page.getByRole("tab", { name: "Seções" })).toBeFocused();
  await expect(page).toHaveURL(/aba=secoes/);
  await page.keyboard.press("End");
  await expect(page.getByRole("tab", { name: "Qualidade" })).toHaveAttribute("aria-selected", "true");
  await page.keyboard.press("Home");
  await expect(page.getByRole("tab", { name: "Resumo" })).toHaveAttribute("aria-selected", "true");
});

test("trocar de município durante o carregamento não deixa dados do anterior", async ({ page }) => {
  // o resumo do primeiro município chega atrasado, depois que o usuário já trocou
  await page.route("**/municipios/GO/00000/resumo.json", async (route) => {
    await new Promise((r) => setTimeout(r, 2500));
    await route.continue();
  });
  await page.goto(muniUrl("00000"));
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Cidade Modelo, Goiás");
  await searchAndPick(page, "Trocar município", "porto", /Porto das Águas — SC/);
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Porto das Águas, Santa Catarina");
  await page.waitForTimeout(3500);
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Porto das Águas, Santa Catarina");
  const resumo = await (await page.request.get("data/releases/DEMO-001/2026-presidente/municipios/SC/00003/resumo.json")).json();
  const a2 = resumo.finalists.find((f) => f.slot === "A").round_2_votes.toLocaleString("pt-BR");
  await expect(page.locator(".metric.slot-A strong")).toHaveText(a2);
  await expect(page.locator("main")).not.toContainText("Cidade Modelo, Goiás");
});

test("URL com município inexistente mostra a escolha, nunca outro município", async ({ page }) => {
  await page.goto(muniUrl("99999"));
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Escolha um município");
  await expect(page.getByText("Município não encontrado nesta publicação")).toBeVisible();
  await expect(page.locator(".metric")).toHaveCount(0);
});

test("trocar de aba carrega o conteúdo de cada uma", async ({ page }) => {
  await page.goto(muniUrl("00000"));
  await openTab(page, "Seções");
  await expect(page.locator("#panel-secoes")).toContainText("Tabela de seções");
  await expect(page.locator("#panel-secoes table")).toBeVisible();
  await openTab(page, "Cenários");
  await expect(page.locator("#panel-cenarios")).toContainText("Sem troca direta entre os finalistas");
});
