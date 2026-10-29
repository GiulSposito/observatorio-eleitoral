// Metodologia: o texto é estático (metodologia.qmd); parâmetros, hipóteses, cenários e
// calibração vêm de metodo.json da publicação, para nunca divergirem do que foi calculado.

import * as data from "../data.js";
import * as fmt from "../format.js";
import { el, mount, simpleTable, errorState } from "../components.js";

function paramRows(p) {
  const e = p.estimacao || {};
  const pop = p.populacao || {};
  const ld = e.largura_determinada || {};
  return [
    ["Tolerância de mudança de aptos (τ)", `max(${fmt.int(pop.tau_minimo_eleitores)}, ${fmt.pct(pop.tau_fracao, 0)} dos aptos do 1º turno)`],
    ["Cobertura mínima para estimar", `${fmt.pct(p.cobertura_minima, 0)} dos aptos do 1º turno`],
    ["Mínimo de seções para estimar", fmt.int(e.n_secoes_min)],
    ["R-hat máximo / ESS mínimo", `${fmt.dec(e.rhat_max, 2)} / ${fmt.int(e.ess_min)}`],
    ["Célula determinada", `largura ≤ max(${fmt.int(ld.votos_minimo)} votos, ${fmt.pct(ld.fracao_linha, 0)} da linha)`],
    ["Célula estimada / fraca", `R ≤ ${fmt.dec(e.r_estimado, 2)} / R ≤ ${fmt.dec(e.r_fraco, 2)}`],
    ["Checagem preditiva", `${fmt.int(e.k_folds)} grupos; erro do modelo ≤ ${fmt.dec(e.ganho_preditivo_min, 2)} × erro do modelo nulo`],
    ["Massa de mudança identificada para o gráfico de fluxos", fmt.pct(e.massa_identificada_min, 0)],
    ["Nível do intervalo", fmt.pct(e.intervalo_nivel, 0)],
  ];
}

export async function render() {
  const slot = document.getElementById("metodo-dinamico");
  if (!slot) return;
  try {
    const m = await data.loadMetodo();
    const cal = m.calibration || {};
    const calText = {
      passed: "A calibração atingiu a cobertura-alvo; os limiares abaixo são os calibrados.",
      failed: "A calibração não atingiu a cobertura-alvo; a publicação mostra só limites, sem estimativas pontuais.",
      not_run: "A calibração ainda não foi executada nesta publicação; os limiares abaixo são os iniciais.",
    }[cal.status] || "";
    mount(slot,
      el("h2", {}, "Parâmetros desta publicação"),
      el("p", {}, `Versão do método ${m.method_version}, publicação ${m.release_id}.`),
      simpleTable({ caption: "Parâmetros do método (config/metodo.yml)", head: ["Parâmetro", "Valor"], rows: paramRows(m.parameters || {}) }),
      el("h2", {}, "Hipóteses"),
      el("dl", {}, (m.assumptions || []).flatMap((a) => [el("dt", {}, a.label_ptbr), el("dd", {}, a.description_ptbr)])),
      el("h2", {}, "Cenários"),
      el("dl", {}, (m.scenarios || []).flatMap((s) => [el("dt", {}, s.label_ptbr), el("dd", {}, s.description_ptbr)])),
      el("h2", {}, "Calibração"),
      el("p", {}, `${calText} Meta de cobertura: ${fmt.pct(cal.target_coverage, 0)}. Identificador: ${cal.calibration_id || "–"}.`),
      cal.decision ? el("p", {}, cal.decision) : null);
  } catch (e) {
    mount(slot, errorState(e, "Parâmetros da publicação"));
  }
}
