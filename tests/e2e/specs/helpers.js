// Utilitários comuns dos testes E2E (bundle sintético DEMO-001).
import { expect } from "@playwright/test";

export const E = "2026-presidente";
export const muniUrl = (m, aba) => `explorar.html?e=${E}&m=${m}${aba ? `&aba=${aba}` : ""}`;

// Erros de console da página, para afirmar que não houve nenhum.
export function collectErrors(page) {
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.message));
  page.on("console", (m) => { if (m.type() === "error") errors.push(m.text()); });
  return errors;
}

export async function openTab(page, name) {
  await page.getByRole("tab", { name }).click();
  await expect(page.getByRole("tab", { name })).toHaveAttribute("aria-selected", "true");
}

export async function searchAndPick(page, label, query, optionName) {
  const box = page.getByRole("combobox", { name: label });
  await box.fill(query);
  await page.getByRole("option", { name: optionName }).first().click();
}
