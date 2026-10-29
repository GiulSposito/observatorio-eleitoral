// Classes de evidência e de identificação (docs/03 §14, docs/05 §5.4, §5.7, §7).
// Decide o que cada célula, aba e status mostra. Puro: sem DOM, testável em node.

import * as fmt from "./format.js";

export const EVIDENCE = {
  observed: { tag: "Observado", cls: "tag-observed" },
  conditional_bound: { tag: "Limite condicional", cls: "tag-bound" },
  model_estimate: { tag: "Estimado pelo modelo", cls: "tag-estimate" },
  unavailable: { tag: "Indisponível", cls: "tag-unavailable" },
};

export const ID_CLASS = {
  determined: { label: "Determinada", help: "As margens bastam para fixar este fluxo." },
  estimated: { label: "Estimada", help: "Os dados distinguem este fluxo sob a hipótese do modelo." },
  weak: { label: "Fraca", help: "A estimativa é pouco informativa; vale mais o limite." },
  not_identified: { label: "Não identificada", help: "Os dados não distinguem os fluxos possíveis nesta célula." },
};

export const ORIGINS = ["A", "B", "O", "I", "X", "N"];
export const DESTINATIONS = ["A", "B", "I", "X", "S"];
export const RETENTION = new Set(["A>A", "B>B", "I>I", "X>X"]);

const DEFAULT_LABELS = {
  1: { A: "Finalista A", B: "Finalista B", O: "Demais candidatos", I: "Brancos e nulos", X: "Abstenção", N: "Entrada líquida de aptos" },
  2: { A: "Finalista A", B: "Finalista B", I: "Brancos e nulos", X: "Abstenção", S: "Saída líquida de aptos" },
};

// Rótulos de categoria: metodo.json (categories) com o nome dos finalistas do catálogo.
export function categoryLabels(metodo, finalists) {
  const out = { 1: { ...DEFAULT_LABELS[1] }, 2: { ...DEFAULT_LABELS[2] } };
  for (const c of metodo?.categories || []) out[c.round][c.code] = c.label_ptbr;
  for (const f of finalists || []) {
    for (const r of [1, 2]) out[r][f.slot] = finalistTag(f);
  }
  return out;
}

// "Finalista A (13)": rótulo curto e neutro para matrizes, eixos e seletores.
export function finalistTag(f) {
  return `Finalista ${f.slot} (${f.number})`;
}

// "A · Luiz Inácio Lula da Silva": nome completo do TSE em caixa mista, com o slot.
export function finalistName(f) {
  return `${f.slot} · ${titleCase(f.name)}`;
}

export function titleCase(s) {
  const lower = new Set(["de", "da", "do", "das", "dos", "e"]);
  return String(s || "").toLowerCase().split(" ")
    .map((w, i) => (i > 0 && lower.has(w) ? w : w.charAt(0).toUpperCase() + w.slice(1)))
    .join(" ");
}

// ---- status ---------------------------------------------------------------

export const FEATURE_TEXT = {
  ready: "Disponível",
  partial: "Parcial",
  insufficient_data: "Dados insuficientes",
  failed: "Falhou",
  unavailable: "Indisponível",
};

export function isUsable(status) {
  return status === "ready" || status === "partial";
}

export function canShowSankey(manifest) {
  return manifest?.features?.ecological_model === "ready";
}

export function modelMessage(status) {
  switch (status) {
    case "ready":
      return "Supondo que as taxas de mudança sejam iguais em todas as seções do município, o modelo estima os fluxos abaixo. Outras distribuições também são compatíveis com os totais; células fracas ou não identificadas mostram só os limites.";
    case "partial":
      return "O modelo não passou em todos os critérios de publicação neste município. Mostramos a tabela com a classe de cada célula, sem o gráfico de fluxos.";
    case "insufficient_data":
      return "Este município tem poucas seções comparáveis para estimar fluxos; mostramos só o que as margens permitem.";
    case "failed":
      return "A estimação falhou neste município (cálculo sem convergência ou erro). Mostramos só o que as margens permitem, nunca um número não validado.";
    default:
      return "Estimativa indisponível; mostramos só o que as margens permitem.";
  }
}

export function validationMessage(status) {
  if (status === "passed") return null;
  if (status === "partial") {
    return "Parte das verificações deste município teve falha ou divergência explicada. Os números observados continuam válidos para as seções usadas; veja a aba Qualidade.";
  }
  return "Os totais deste município divergem do oficial sem explicação registrada. Mostramos só os dados observados por seção; análises de transição ficam bloqueadas.";
}

export const EXCLUSION_TEXT = {
  not_installed: "Seção não instalada",
  integrity_failed: "Falha de integridade (V1)",
  unmatched: "Sem par no outro turno",
  transit_section: "Seção de voto em trânsito",
  special_section: "Seção especial",
  population_change_above_tau: "Mudança de aptos acima da tolerância",
  possible_aggregation: "Possível agregação de seções",
};

export const POPULATION_TEXT = {
  closed: "Aptos iguais",
  net_change: "Mudança pequena de aptos",
  excluded_population: "Mudança grande de aptos",
};

// ---- células da matriz ----------------------------------------------------

// bound: linha de limites.parquet (ou null); flow: linha de fluxos_estimados.parquet (ou null).
// Devolve { cls, main, sub, evidence } para a célula — o que mostrar depende da classe.
export function cellView(bound, flow) {
  if (!bound && !flow) return { cls: "unavailable", main: fmt.MISSING, sub: "sem dados", evidence: "unavailable" };
  if (bound && bound.status && bound.status !== "feasible") {
    return { cls: "unavailable", main: fmt.MISSING, sub: bound.status === "infeasible" ? "cenário inviável" : "dados insuficientes", evidence: "unavailable" };
  }
  const lo = flow ? flow.bounds_min : bound.min_votes;
  const hi = flow ? flow.bounds_max : bound.max_votes;
  const limit = fmt.range(lo, hi);
  if (!flow) return { cls: "bound", main: limit, sub: "limite (mín. a máx.)", evidence: "conditional_bound" };
  const methods = flow.method_range_low != null && flow.method_range_high != null
    ? `métodos: ${fmt.range(flow.method_range_low, flow.method_range_high)}` : null;
  switch (flow.identification_class) {
    case "determined":
      return { cls: "determined", main: limit, sub: "as margens determinam", evidence: "conditional_bound" };
    case "estimated":
      return {
        cls: "estimated",
        main: fmt.int(flow.estimate_votes),
        sub: [`intervalo de 95%: ${fmt.range(flow.interval_low, flow.interval_high)}`, methods, `limite: ${limit}`].filter(Boolean).join(" · "),
        evidence: "model_estimate",
      };
    case "weak":
      return {
        cls: "weak",
        main: limit,
        sub: [`estimativa fraca: ${fmt.int(flow.estimate_votes)}`, methods].filter(Boolean).join(" · "),
        evidence: "conditional_bound",
      };
    default:
      return { cls: "not_identified", main: limit, sub: "não identificado", evidence: "conditional_bound" };
  }
}

// ---- Sankey ---------------------------------------------------------------

// Só com ecological_model = ready. Entram células determined/estimated; o resto vira um
// fluxo por origem para o nó "Não identificado" (05 §5.7). Retenção também é desenhada.
export function sankeyData(flows, labels) {
  const origins = ORIGINS.filter((o) => flows.some((f) => f.origin === o));
  const dests = DESTINATIONS.filter((d) => flows.some((f) => f.destination === d));
  const nodes = [
    ...origins.map((o) => ({ id: `1:${o}`, label: `${labels[1][o]} · 1º turno`, code: o, round: 1 })),
    ...dests.map((d) => ({ id: `2:${d}`, label: `${labels[2][d]} · 2º turno`, code: d, round: 2 })),
  ];
  const unknownId = "2:?";
  const links = [];
  const unknownByOrigin = new Map();
  for (const f of flows) {
    const v = Number(f.estimate_votes);
    if (!(v > 0)) continue;
    if (f.identification_class === "determined" || f.identification_class === "estimated") {
      links.push({ source: `1:${f.origin}`, target: `2:${f.destination}`, value: v, kind: f.identification_class, origin: f.origin, destination: f.destination });
    } else {
      unknownByOrigin.set(f.origin, (unknownByOrigin.get(f.origin) || 0) + v);
    }
  }
  if (unknownByOrigin.size) {
    nodes.push({ id: unknownId, label: "Não identificado", code: "?", round: 2 });
    for (const [o, v] of unknownByOrigin) links.push({ source: `1:${o}`, target: unknownId, value: v, kind: "not_identified", origin: o, destination: "?" });
  }
  return { nodes, links };
}

// Massa de mudança identificada (05 §5.7): fora da retenção, em células determined/estimated.
export function identifiedChangeShare(flows) {
  let total = 0;
  let ok = 0;
  for (const f of flows) {
    if (RETENTION.has(`${f.origin}>${f.destination}`)) continue;
    const v = Number(f.estimate_votes) || 0;
    total += v;
    if (f.identification_class === "determined" || f.identification_class === "estimated") ok += v;
  }
  return total > 0 ? ok / total : null;
}
