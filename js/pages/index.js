// Home: o conteúdo editorial é estático (index.qmd); aqui só entra a busca.

import * as data from "../data.js";
import { buildIndex } from "../catalog.js";
import { explorarHref } from "../state.js";
import { el, mount, municipalityCombobox, stateBox, errorState } from "../components.js";

export async function render() {
  const slot = document.getElementById("search-slot");
  if (!slot) return;
  mount(slot, stateBox("info", "Carregando a lista de municípios…", null));
  try {
    const catalog = await data.loadCatalog();
    const index = buildIndex(catalog);
    const box = municipalityCombobox({
      index,
      labelText: "Buscar município",
      hint: "Digite o nome, com ou sem acento. Para homônimos, a UF aparece ao lado. Também aceita o código TSE.",
      onSelect: (m) => { window.location.href = explorarHref({ e: catalog.election.election_id, m: m.municipio_tse }); },
    });
    mount(slot, box, el("p", { class: "trust-line" },
      `${catalog.municipalities.length.toLocaleString("pt-BR")} municípios · ${catalog.election.label}`));
  } catch (e) {
    mount(slot, errorState(e, "Lista de municípios"));
  }
}
