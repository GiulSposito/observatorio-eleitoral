// Busca de município: acentos, homônimos por UF, teclado (Enter, Escape, setas).
import { test, expect } from "@playwright/test";
import { collectErrors } from "./helpers.js";

test.beforeEach(async ({ page }) => {
  await page.goto("index.html");
  await expect(page.getByRole("combobox", { name: "Buscar município" })).toBeVisible();
});

test("acha município com e sem acento", async ({ page }) => {
  const box = page.getByRole("combobox", { name: "Buscar município" });
  await box.fill("porto das águas");
  await expect(page.getByRole("option", { name: /Porto das Águas — SC/ })).toBeVisible();
  await box.fill("PORTO DAS AGUAS");
  await expect(page.getByRole("option", { name: /Porto das Águas — SC/ })).toBeVisible();
});

test("homônimos aparecem separados pela UF", async ({ page }) => {
  const box = page.getByRole("combobox", { name: "Buscar município" });
  await box.fill("vale sereno");
  const options = page.getByRole("option");
  await expect(options).toHaveCount(2);
  await expect(options.nth(0)).toContainText("Vale Sereno — GO");
  await expect(options.nth(1)).toContainText("Vale Sereno — MG");
});

test("Enter escolhe a opção ativa e abre o município", async ({ page }) => {
  const errors = collectErrors(page);
  const box = page.getByRole("combobox", { name: "Buscar município" });
  await box.fill("vale sereno");
  await box.press("ArrowDown");
  await box.press("ArrowDown");
  await expect(box).toHaveAttribute("aria-activedescendant", /opt-1$/);
  await box.press("Enter");
  await expect(page).toHaveURL(/explorar\.html\?e=2026-presidente&m=00001$/);
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Vale Sereno, Minas Gerais");
  expect(errors).toEqual([]);
});

test("Escape fecha a lista e busca vazia não sugere nada", async ({ page }) => {
  const box = page.getByRole("combobox", { name: "Buscar município" });
  await box.fill("cidade");
  await expect(box).toHaveAttribute("aria-expanded", "true");
  await box.press("Escape");
  await expect(box).toHaveAttribute("aria-expanded", "false");
  await box.fill("zzzz");
  await expect(page.getByRole("option", { name: /Nenhum município encontrado/ })).toBeVisible();
});

test("busca por código TSE", async ({ page }) => {
  await page.getByRole("combobox", { name: "Buscar município" }).fill("00003");
  await expect(page.getByRole("option", { name: /Porto das Águas — SC/ })).toBeVisible();
});
