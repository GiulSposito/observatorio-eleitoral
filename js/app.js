// Shell: rodapé com a versão dos dados, faixa de demonstração e inicialização da página.
// Cada .qmd chama boot("<página>") uma vez.

import * as data from "./data.js";
import * as fmt from "./format.js";

const PAGES = {
  index: () => import("./pages/index.js"),
  explorar: () => import("./pages/explorar.js"),
  metodologia: () => import("./pages/metodologia.js"),
  dados: () => import("./pages/dados.js"),
};

async function shell() {
  // O Quarto insere o include-before-body depois do cabeçalho; o link de pular precisa ser o
  // primeiro foco da página.
  const skip = document.querySelector(".skip-link");
  if (skip && document.body.firstElementChild !== skip) document.body.prepend(skip);
  const version = document.getElementById("data-version");
  try {
    const latest = await data.loadLatest();
    if (version) version.textContent = `versão dos dados: ${latest.release_id} · publicada em ${fmt.datetime(latest.published_at)}`;
    if (/^DEMO-/.test(latest.release_id)) {
      const banner = document.getElementById("demo-banner");
      if (banner) {
        banner.textContent = "Dados fictícios · bundle de demonstração para desenvolvimento · não é resultado eleitoral";
        banner.hidden = false;
      }
    }
    return latest;
  } catch (e) {
    if (version) version.textContent = "versão dos dados indisponível";
    return null;
  }
}

export async function boot(page) {
  const latest = await shell();
  const loader = PAGES[page];
  if (!loader) return;
  const mod = await loader();
  await mod.render({ latest });
}
