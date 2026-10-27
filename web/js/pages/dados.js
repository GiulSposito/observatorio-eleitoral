// Dados e código: identifica a publicação carregada (latest.json).

import * as fmt from "../format.js";
import { mount, simpleTable, stateBox } from "../components.js";

export async function render({ latest }) {
  const slot = document.getElementById("release-info");
  if (!slot) return;
  if (!latest) {
    mount(slot, stateBox("alert", "Publicação indisponível", "Não foi possível ler latest.json."));
    return;
  }
  mount(slot, simpleTable({
    caption: "Publicação carregada",
    head: ["Item", "Valor"],
    rows: [
      ["Release", latest.release_id],
      ["Publicada em", fmt.datetime(latest.published_at)],
      ["Commit do pipeline", latest.pipeline_git_sha],
      ["Versão do método", latest.method_version],
      ["Versão do contrato de dados", latest.schema_version],
    ],
  }));
}
