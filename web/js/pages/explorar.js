// Página do município: explorar.html?e=<election_id>&m=<municipio_tse>&aba=<aba>.
// Resumo vem de resumo.json (sem Wasm); as outras abas consultam os Parquets da UF sob demanda.
// Trocar de município cancela tudo o que estava em andamento (sessão) e limpa a página.

import * as data from "../data.js";
import * as fmt from "../format.js";
import * as state from "../state.js";
import * as ev from "../evidence.js";
import * as charts from "../charts.js";
import { correlationSummary } from "../stats.js";
import { buildIndex, findByCode } from "../catalog.js";
import {
  el, mount, uid, stateBox, skeleton, errorState, methodTag, sectionHeading, chartFrame,
  metricStrip, dataTable, simpleTable, municipalityCombobox,
} from "../components.js";

const UF_NAMES = {
  AC: "Acre", AL: "Alagoas", AM: "Amazonas", AP: "Amapá", BA: "Bahia", CE: "Ceará", DF: "Distrito Federal",
  ES: "Espírito Santo", GO: "Goiás", MA: "Maranhão", MG: "Minas Gerais", MS: "Mato Grosso do Sul",
  MT: "Mato Grosso", PA: "Pará", PB: "Paraíba", PE: "Pernambuco", PI: "Piauí", PR: "Paraná",
  RJ: "Rio de Janeiro", RN: "Rio Grande do Norte", RO: "Rondônia", RR: "Roraima", RS: "Rio Grande do Sul",
  SC: "Santa Catarina", SE: "Sergipe", SP: "São Paulo", TO: "Tocantins",
};

const TAB_LABELS = {
  resumo: "Resumo", secoes: "Seções", transferencias: "Transferências", cenarios: "Cenários", qualidade: "Qualidade",
};

let root = null;
let catalog = null;
let index = null;
let ctx = null;   // { item, session, manifest, resumo, tab, panels, done, cache }

export async function render() {
  root = document.getElementById("app");
  if (!root) return;
  mount(root, skeleton(4, true));
  try {
    catalog = await data.loadCatalog();
    index = buildIndex(catalog);
  } catch (e) {
    mount(root, errorState(e, "Lista de municípios"));
    return;
  }
  window.addEventListener("popstate", () => route(false));
  route(true);
}

// ---- roteamento ------------------------------------------------------------

function route(initial) {
  const s = state.read();
  const electionId = catalog.election.election_id;
  const item = s.m ? findByCode(index, s.m) : null;
  if (!item || (s.e && s.e !== electionId)) {
    if (ctx) { ctx.session.cancel(); ctx = null; }
    renderChooser(s.m && !item ? "not_found" : s.e && s.e !== electionId ? "election" : null);
    if (initial && (s.m || s.e)) state.replace({});
    return;
  }
  if (!s.e) state.replace({ e: electionId, m: item.municipio_tse, aba: s.aba });
  if (ctx && ctx.item.municipio_tse === item.municipio_tse) {
    selectTab(s.aba, false);
    return;
  }
  openMunicipio(item, s.aba);
}

function goTo(item, aba = state.DEFAULT_TAB) {
  state.push({ e: catalog.election.election_id, m: item.municipio_tse, aba });
  openMunicipio(item, aba);
}

function renderChooser(reason) {
  document.title = "Explorar · Caderno Eleitoral";
  const msg = reason === "not_found"
    ? stateBox("alert", "Município não encontrado nesta publicação", "O endereço aponta para um código que não está no catálogo. Escolha o município abaixo.")
    : reason === "election"
      ? stateBox("alert", "Eleição não disponível", "Esta publicação cobre só a eleição presidencial de 2026. Escolha o município abaixo.")
      : null;
  mount(root,
    el("div", { class: "muni-intro" },
      el("div", {},
        el("div", { class: "ce-label" }, catalog.election.label),
        el("h1", {}, "Escolha um município"),
        el("p", { class: "lead" }, "Compare o 1º e o 2º turno seção por seção e veja o que os dados permitem concluir."))),
    msg,
    el("div", { class: "home-search" }, municipalityCombobox({
      index, labelText: "Buscar município", autofocus: true,
      hint: "Digite o nome, com ou sem acento. Para homônimos, a UF aparece ao lado.",
      onSelect: (m) => goTo(m),
    })));
}

// ---- município ---------------------------------------------------------------

async function openMunicipio(item, aba) {
  if (ctx) ctx.session.cancel();
  const session = data.newSession();
  ctx = { item, session, manifest: null, resumo: null, quality: null, tab: aba, panels: {}, done: new Set(), cache: {} };
  const my = ctx;
  document.title = `${item.display_name} (${item.uf}) · Caderno Eleitoral`;
  mount(root, header(item, null, null), el("div", { id: "muni-body" }, skeleton(4, true)));
  try {
    const manifest = await data.loadManifest(item, session.signal);
    if (my !== ctx) return;
    my.manifest = manifest;
    let resumo = null;
    let resumoError = null;
    if (ev.isUsable(manifest.features.summary)) {
      try {
        resumo = await data.loadJsonAsset(manifest, "summary", session.signal);
      } catch (e) {
        if (e.kind === "aborted") return;
        resumoError = e;
      }
    }
    if (my !== ctx) return;
    my.resumo = resumo;
    mount(root, header(item, manifest, resumo), body(manifest, resumoError));
    selectTab(aba, false, true);
    data.warmUp();
  } catch (e) {
    if (e.kind === "aborted" || my !== ctx) return;
    mount(root, header(item, null, null), errorState(e, "Dados do município"));
  }
}

function header(item, manifest, resumo) {
  const ufName = UF_NAMES[item.uf] || item.uf;
  const cov = resumo?.coverage;
  const copyBtn = el("button", {
    type: "button", class: "ce-button",
    onclick: async (e) => {
      const btn = e.currentTarget;
      try { await navigator.clipboard.writeText(window.location.href); btn.textContent = "Link copiado"; } catch { btn.textContent = "Copie o endereço da barra"; }
      setTimeout(() => { btn.textContent = "Copiar link desta página"; }, 2500);
    },
  }, "Copiar link desta página");
  const resumoUrl = manifest ? data.assetUrl(manifest, "summary") : null;
  return el("header", { class: "muni-header" },
    el("nav", { class: "breadcrumb-trail", "aria-label": "Você está em" },
      el("span", {}, "Brasil"), el("span", { class: "sep", "aria-hidden": "true" }, "/"),
      el("span", {}, ufName), el("span", { class: "sep", "aria-hidden": "true" }, "/"),
      el("span", { "aria-current": "page" }, item.display_name)),
    el("div", { class: "muni-intro" },
      el("div", {},
        el("div", { class: "ce-label" }, catalog.election.label),
        el("h1", { id: "muni-title" }, `${item.display_name}, ${ufName}`),
        el("p", { class: "lead" }, "O que mudou entre o 1º e o 2º turno, seção por seção, e o que os dados permitem concluir.")),
      el("div", { class: "muni-actions ce-no-print" },
        municipalityCombobox({ index, labelText: "Trocar município", onSelect: (m) => goTo(m) }),
        copyBtn,
        resumoUrl ? el("a", { class: "ce-button", href: resumoUrl, download: `resumo-${item.municipio_tse}.json` }, "Baixar resumo (JSON)") : null)),
    el("div", { class: "meta-row" },
      el("span", {}, `Rodadas: ${fmt.date(catalog.election.rounds[0].date)} e ${fmt.date(catalog.election.rounds[1].date)}`),
      cov ? el("span", {}, el("a", { href: "#", onclick: (e) => { e.preventDefault(); selectTab("qualidade", true); } },
        `${fmt.int(cov.units_in_transition_analysis)} de ${fmt.int(cov.sections_total)} seções na análise de transição`)) : null,
      el("span", {}, "Fonte: TSE, dados abertos"),
      el("span", {}, `Código TSE ${item.municipio_tse}`)));
}

function body(manifest, resumoError) {
  const tabs = el("div", { class: "tabs ce-no-print", role: "tablist", "aria-label": "Tipos de análise" });
  const panels = [];
  for (const key of state.TABS) {
    const tabId = `tab-${key}`;
    const panelId = `panel-${key}`;
    const btn = el("button", {
      id: tabId, class: "tab", type: "button", role: "tab", "aria-controls": panelId, "aria-selected": "false", tabindex: "-1",
      "data-tab": key, onclick: () => selectTab(key, true),
    }, TAB_LABELS[key]);
    btn.addEventListener("keydown", onTabKey);
    tabs.append(btn);
    const panel = el("section", { id: panelId, class: "tab-panel", role: "tabpanel", "aria-labelledby": tabId, tabindex: "0", hidden: true });
    ctx.panels[key] = panel;
    panels.push(panel);
  }
  const notice = ev.validationMessage(manifest.validation_status);
  return el("div", { id: "muni-body" },
    notice ? stateBox("alert", manifest.validation_status === "failed" ? "Dados com divergência não explicada" : "Verificações com ressalvas", notice) : null,
    resumoError ? errorState(resumoError, "Resumo") : null,
    tabs, panels);
}

function onTabKey(e) {
  const keys = state.TABS;
  const i = keys.indexOf(e.currentTarget.dataset.tab);
  let next = null;
  if (e.key === "ArrowRight") next = keys[(i + 1) % keys.length];
  else if (e.key === "ArrowLeft") next = keys[(i - 1 + keys.length) % keys.length];
  else if (e.key === "Home") next = keys[0];
  else if (e.key === "End") next = keys[keys.length - 1];
  if (!next) return;
  e.preventDefault();
  selectTab(next, true);
  document.getElementById(`tab-${next}`)?.focus();
}

function selectTab(key, userAction, initial = false) {
  if (!ctx || !ctx.manifest) return;
  const tab = state.TABS.includes(key) ? key : state.DEFAULT_TAB;
  ctx.tab = tab;
  for (const k of state.TABS) {
    const btn = document.getElementById(`tab-${k}`);
    const on = k === tab;
    if (btn) { btn.setAttribute("aria-selected", String(on)); btn.tabIndex = on ? 0 : -1; }
    if (ctx.panels[k]) ctx.panels[k].hidden = !on;
  }
  if (userAction) state.replace({ e: catalog.election.election_id, m: ctx.item.municipio_tse, aba: tab });
  if (!ctx.done.has(tab)) {
    ctx.done.add(tab);
    renderPanel(tab).catch((e) => {
      if (e.kind === "aborted") return;
      mount(ctx.panels[tab], errorState(e));
    });
  }
  if (initial) return;
}

async function renderPanel(tab) {
  const my = ctx;
  const panel = my.panels[tab];
  mount(panel, skeleton(3, tab !== "qualidade"));
  const out = await ({ resumo: panelResumo, secoes: panelSecoes, transferencias: panelTransferencias, cenarios: panelCenarios, qualidade: panelQualidade })[tab](my);
  if (my !== ctx || my.session.aborted) return;
  mount(panel, out);
}

// Erro de leitura dentro de uma aba vira estado visível; cancelamento sobe para ser ignorado.
async function guard(fn, what) {
  try { return { value: await fn() }; } catch (e) {
    if (e.kind === "aborted") throw e;
    return { error: errorState(e, what) };
  }
}

async function metodoOrNull() {
  try { return await data.loadMetodo(); } catch { return null; }
}

function finalists() { return catalog.election.finalists; }

// ---- aba Resumo --------------------------------------------------------------

async function panelResumo(my) {
  const r = my.resumo;
  if (!r) {
    return stateBox("info", "Resumo indisponível", `Situação publicada: ${ev.FEATURE_TEXT[my.manifest.features.summary] || "indisponível"}. Nenhum número é mostrado no lugar.`);
  }
  const [A, B] = ["A", "B"].map((s) => r.finalists.find((f) => f.slot === s));
  const t1 = r.totals.round_1;
  const t2 = r.totals.round_2;
  const acc = r.accounting;
  const metrics = metricStrip([
    { slot: "A", name: `${ev.finalistName(A)} · 2º turno`, value: fmt.int(A.round_2_votes), sub: `${fmt.signedVotes(A.delta_votes)} ante o 1º turno` },
    { slot: "B", name: `${ev.finalistName(B)} · 2º turno`, value: fmt.int(B.round_2_votes), sub: `${fmt.signedVotes(B.delta_votes)} ante o 1º turno` },
    { name: "Variação no comparecimento", value: fmt.signed(acc.delta_turnout), sub: "pessoas que votaram" },
    { name: "Variação de brancos e nulos", value: fmt.signed(acc.delta_invalid), sub: "votos inválidos" },
  ]);

  const slopeTitle = uid("slope");
  const slope = chartFrame({
    label: "Evolução", title: "Votos dos finalistas por turno", subtitle: "Votos absolutos. Escala a partir de zero.", evidence: "observed",
    body: el("div", {}, charts.slopeChart([A, B], slopeTitle),
      el("div", { class: "legend", "aria-hidden": "true" },
        el("span", {}, el("span", { class: "legend-swatch slot-A" }), `A · ${ev.titleCase(A.name)} (${A.number})`),
        el("span", {}, el("span", { class: "legend-swatch slot-B" }), `B · ${ev.titleCase(B.name)} (${B.number})`))),
    caption: "Comparação de totais agregados; não identifica quem mudou de voto.",
    table: simpleTable({
      caption: "Votos por finalista e turno",
      head: ["Finalista", "1º turno", "2º turno", "Variação"],
      rows: [A, B].map((f) => [`${f.slot} · ${ev.titleCase(f.name)}`, fmt.int(f.round_1_votes), fmt.int(f.round_2_votes), fmt.signed(f.delta_votes)]),
    }),
  });
  // o título do SVG aponta para o h3 do frame
  slope.querySelector("svg")?.setAttribute("aria-labelledby", `${slope.querySelector("h3").id} ${slopeTitle}-desc`);

  const note = el("div", { class: "editorial-note", role: "note" },
    el("div", { class: "ce-label" }, "Leitura dos dados"),
    el("h2", {}, "Os totais mudam. Os fluxos individuais não são observados."),
    el("p", {}, `Entre os turnos, o finalista A variou ${fmt.signedVotes(A.delta_votes)} e o finalista B, ${fmt.signedVotes(B.delta_votes)}. O comparecimento variou ${fmt.signed(acc.delta_turnout)} e os brancos e nulos, ${fmt.signed(acc.delta_invalid)}.`),
    el("p", {}, "Esses agregados não mostram como eleitores específicos mudaram de voto. Para estimar transferências são necessárias hipóteses adicionais, explicadas na aba Transferências."),
    el("a", { href: "metodologia.html" }, "Entenda a metodologia →"));

  const reduction = acc.delta_invalid == null ? null : -acc.delta_invalid;
  const accounting = el("section", { class: "accounting", "aria-labelledby": "acc-title" },
    sectionHeading({ label: "Conferência", title: "Como se fecha a variação dos votos", id: "acc-title", evidence: "observed" }),
    el("div", { class: "equation-grid", role: "group", "aria-label": "Identidade contábil" },
      el("div", { class: "equation-part" }, el("span", {}, "Outros candidatos, 1º turno"), el("strong", {}, fmt.int(acc.other_round_1))),
      el("div", { class: "equation-symbol", "aria-hidden": "true" }, "+"),
      el("div", { class: "equation-part" }, el("span", {}, "Variação de comparecimento"), el("strong", {}, fmt.signed(acc.delta_turnout))),
      el("div", { class: "equation-symbol", "aria-hidden": "true" }, "+"),
      el("div", { class: "equation-part" }, el("span", {}, "Redução de brancos e nulos"), el("strong", {}, fmt.signed(reduction))),
      el("div", { class: "equation-symbol", "aria-hidden": "true" }, "="),
      el("div", { class: "equation-part equation-result" }, el("span", {}, "Ganho total dos finalistas"), el("strong", {}, fmt.signed(acc.delta_finalists)))),
    el("p", { class: "ce-caption" }, "A conta fecha por aritmética: outros votos no 1º turno + variação de comparecimento + redução de brancos e nulos = ganho dos finalistas. Isso não mostra quem mudou de voto."),
    acc.identity_residual ? stateBox("alert", "A conta não fechou", `Resíduo de ${fmt.signed(acc.identity_residual)} votos; veja a aba Qualidade.`) : null);

  const totals = simpleTable({
    caption: "Totais do município por turno (todas as seções instaladas)",
    head: ["Indicador", "1º turno", "2º turno"],
    rows: [
      ["Eleitores aptos", fmt.int(t1.eligible), fmt.int(t2.eligible)],
      ["Comparecimento", fmt.int(t1.turnout), fmt.int(t2.turnout)],
      ["Abstenção", fmt.int(t1.abstention), fmt.int(t2.abstention)],
      ["Votos válidos", fmt.int(t1.valid), fmt.int(t2.valid)],
      [ev.finalistName(A), fmt.int(A.round_1_votes), fmt.int(A.round_2_votes)],
      [ev.finalistName(B), fmt.int(B.round_1_votes), fmt.int(B.round_2_votes)],
      ["Demais candidatos", fmt.int(t1.other), fmt.int(t2.other)],
      ["Brancos", fmt.int(t1.blank), fmt.int(t2.blank)],
      ["Nulos", fmt.int(t1.null), fmt.int(t2.null)],
    ],
  });

  const cov = r.coverage;
  const foot = el("section", { class: "methodology-note" },
    el("div", { class: "ce-label" }, "Fonte e método"),
    el("p", {}, `Fonte: Tribunal Superior Eleitoral, votação e detalhe da votação por seção (presidente, 2026). Totais somam as ${fmt.int(cov.sections_installed)} seções instaladas; ${fmt.int(cov.units_in_transition_analysis)} entram na análise de transição (${fmt.pct(cov.eligible_share_used)} dos aptos do 1º turno). Publicação ${r.release_id}.`),
    (r.display_notes || []).map((n) => el("p", {}, n)));

  return el("div", {},
    metrics,
    el("div", { class: "ce-split" }, slope, note),
    accounting,
    el("section", { "aria-label": "Totais por turno" }, el("h3", { class: "chart-title" }, "Totais por turno"), totals),
    foot);
}

// ---- aba Seções ----------------------------------------------------------------

async function panelSecoes(my) {
  if (!ev.isUsable(my.manifest.features.sections)) {
    return stateBox("info", "Dados por seção indisponíveis", ev.FEATURE_TEXT[my.manifest.features.sections]);
  }
  const [res, metodo] = await Promise.all([guard(() => data.getSections(my.manifest, my.session.signal), "Seções"), metodoOrNull()]);
  if (res.error) return el("div", {}, res.error, el("p", { class: "ce-caption" }, "O resumo e a metodologia continuam disponíveis."));
  const rows = res.value;
  if (!rows.length) return stateBox("info", "Nenhuma seção publicada para este município", null);
  const minN = metodo?.parameters?.estimacao?.n_secoes_min ?? 15;
  const [A, B] = ["A", "B"].map((s) => finalists().find((f) => f.slot === s));
  const zonas = [...new Set(rows.map((r) => r.zona))].sort();

  const ids = { zona: uid("f-zona"), norm: uid("f-norm"), slot: uid("f-slot") };
  const zonaSel = el("select", { id: ids.zona, class: "ce-input" }, el("option", { value: "" }, "Todas as zonas"), zonas.map((z) => el("option", { value: z }, `Zona ${z}`)));
  const normSel = el("select", { id: ids.norm, class: "ce-input" },
    el("option", { value: "per100" }, "Por 100 aptos do 1º turno"), el("option", { value: "abs" }, "Votos absolutos"));
  const slotSel = el("select", { id: ids.slot, class: "ce-input" },
    el("option", { value: "A" }, ev.finalistTag(A)), el("option", { value: "B" }, ev.finalistTag(B)));
  const filters = el("div", { class: "filters" },
    el("div", {}, el("label", { for: ids.zona }, "Zona"), zonaSel),
    el("div", {}, el("label", { for: ids.norm }, "Escala"), normSel),
    el("div", {}, el("label", { for: ids.slot }, "Finalista no eixo vertical"), slotSel));

  const chartHost = el("div", { class: "chart-host", role: "img", "aria-label": "Gráfico de dispersão das seções" });
  const statLine = el("p", { class: "stat-line", "aria-live": "polite" });
  const tableHost = el("div", {});
  const csvBtn = el("button", { type: "button", class: "ce-button" }, "Baixar CSV das seções filtradas");

  const scatterFrame = chartFrame({
    label: "Unidades de votação", title: "Variação por seção: comparecimento × votos do finalista",
    subtitle: "Cada ponto é uma seção na análise de transição. Linhas de referência no zero.", evidence: "observed",
    body: el("div", {}, chartHost, statLine),
    caption: "A correlação por seção não identifica o comportamento individual dos eleitores. Parte dela é aritmética (a conta do Resumo) e parte vem do tamanho das seções.",
  });

  const update = async () => {
    const zona = zonaSel.value;
    const norm = normSel.value;
    const slot = slotSel.value;
    const filtered = rows.filter((r) => !zona || r.zona === zona);
    const usable = filtered.filter((r) => r.in_transition_analysis && r.delta_turnout != null);
    const dCol = slot === "A" ? "delta_a" : "delta_b";
    const pts = usable.map((r) => ({
      x: norm === "per100" ? fmt.per100(r.delta_turnout, r.eligible_t1) : r.delta_turnout,
      y: norm === "per100" ? fmt.per100(r[dCol], r.eligible_t1) : r[dCol],
      label: `Zona ${r.zona}, seção ${r.secao}`,
    }));
    const unit = norm === "per100" ? " (por 100 aptos)" : " (votos)";
    const cs = correlationSummary(pts, minN);
    const excluded = filtered.length - usable.length;
    mount(statLine,
      cs.r == null
        ? el("span", {}, cs.reason === "few_sections"
          ? `Correlação não exibida: ${fmt.int(cs.n)} seções comparáveis, abaixo do mínimo de ${minN}.`
          : "Correlação não exibida: sem variação suficiente entre as seções.")
        : el("span", {}, `Correlação de Pearson: r = ${fmt.dec(cs.r, 2)} (intervalo de 95%: ${fmt.dec(cs.interval[0], 2)} a ${fmt.dec(cs.interval[1], 2)}) · ${fmt.int(cs.n)} seções. Isso não estabelece causalidade.`),
      excluded ? el("span", { class: "muted" }, ` ${fmt.int(excluded)} seção(ões) fora da análise de transição não entram no gráfico; veja a tabela.`) : null);
    try {
      await charts.sectionScatter(chartHost, pts, { xTitle: `Variação de comparecimento${unit}`, yTitle: `Variação de votos de ${slot}${unit}`, slot });
    } catch (e) {
      mount(chartHost, stateBox("alert", "Gráfico indisponível", `${e.message} A tabela abaixo traz os mesmos dados.`));
    }
    mount(tableHost, sectionsTable(filtered, A, B));
    csvBtn.onclick = () => downloadCsv(filtered, `secoes-${my.item.municipio_tse}${zona ? "-zona-" + zona : ""}.csv`);
  };
  for (const s of [zonaSel, normSel, slotSel]) s.addEventListener("change", () => { update(); });
  const out = el("div", {},
    sectionHeading({ label: "Unidades de votação", title: "Variação observada por seção", evidence: "observed",
      text: "Seções agregadas, de trânsito ou com mudança grande de aptos aparecem na tabela com o motivo e ficam fora do gráfico e da análise de transição." }),
    filters, scatterFrame,
    el("div", { class: "section-heading" }, el("h3", { class: "chart-title" }, "Tabela de seções"), csvBtn),
    tableHost);
  queueMicrotask(update);
  return out;
}

function sectionsTable(rows, A, B) {
  const status = (r) => (r.in_transition_analysis ? "Na análise" : ev.EXCLUSION_TEXT[r.exclusion_reason] || "Fora da análise");
  return dataTable({
    rows,
    caption: `${fmt.int(rows.length)} seções. Valores observados; “–” indica dado ausente, nunca zero.`,
    pageSize: 50,
    rowClass: (r) => (r.in_transition_analysis ? null : "excluded"),
    initialSort: { key: "zona", dir: "ascending" },
    columns: [
      { key: "zona", label: "Zona", sortValue: (r) => `${r.zona}-${r.secao}` },
      { key: "secao", label: "Seção" },
      { key: "eligible_t1", label: "Aptos 1º", num: true, format: fmt.int },
      { key: "eligible_t2", label: "Aptos 2º", num: true, format: fmt.int },
      { key: "candidate_a_t1", label: `A 1º`, num: true, format: fmt.int },
      { key: "candidate_a_t2", label: `A 2º`, num: true, format: fmt.int },
      { key: "candidate_b_t1", label: `B 1º`, num: true, format: fmt.int },
      { key: "candidate_b_t2", label: `B 2º`, num: true, format: fmt.int },
      { key: "others_t1", label: "Outros 1º", num: true, format: fmt.int },
      { key: "invalid_t1", label: "Inválidos 1º", num: true, format: fmt.int },
      { key: "invalid_t2", label: "Inválidos 2º", num: true, format: fmt.int },
      { key: "turnout_t1", label: "Comparec. 1º", num: true, format: fmt.int },
      { key: "turnout_t2", label: "Comparec. 2º", num: true, format: fmt.int },
      { key: "delta_a", label: "Δ A", num: true, format: (v) => fmt.signed(v) },
      { key: "delta_b", label: "Δ B", num: true, format: (v) => fmt.signed(v) },
      { key: "delta_turnout", label: "Δ comparec.", num: true, format: (v) => fmt.signed(v) },
      { key: "exclusion_reason", label: "Situação", flag: true, format: (_v, r) => status(r), sortValue: (r) => status(r) },
    ],
  });
}

const CSV_COLUMNS = ["zona", "secao", "section_type", "eligible_t1", "eligible_t2", "turnout_t1", "turnout_t2",
  "abstention_t1", "abstention_t2", "candidate_a_t1", "candidate_a_t2", "candidate_b_t1", "candidate_b_t2", "others_t1",
  "blank_t1", "null_t1", "blank_t2", "null_t2", "delta_turnout", "delta_a", "delta_b", "delta_invalid",
  "population_status", "in_transition_analysis", "exclusion_reason"];

function downloadCsv(rows, filename) {
  const esc = (v) => (v == null ? "" : /[",;\n]/.test(String(v)) ? `"${String(v).replace(/"/g, '""')}"` : String(v));
  const lines = [CSV_COLUMNS.join(","), ...rows.map((r) => CSV_COLUMNS.map((c) => esc(r[c])).join(","))];
  const blob = new Blob([lines.join("\n") + "\n"], { type: "text/csv;charset=utf-8" });
  const a = el("a", { href: URL.createObjectURL(blob), download: filename });
  document.body.append(a);
  a.click();
  setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1000);
}

// ---- aba Transferências -----------------------------------------------------

function matrixTable({ caption, labels, rowsKeys, colsKeys, cell }) {
  return el("div", { class: "data-table-wrap", tabindex: "0", role: "region", "aria-label": "Matriz de fluxos entre o 1º e o 2º turno" },
    el("p", { class: "scroll-hint", "aria-hidden": "true" }, "Deslize a tabela para o lado para ver todas as colunas."),
    el("table", { class: "ce-table flow-matrix" },
      el("caption", {}, caption),
      el("thead", {}, el("tr", {},
        el("th", { scope: "col" }, "1º turno ↓ · 2º turno →"),
        colsKeys.map((d) => el("th", { scope: "col" }, labels[2][d])))),
      el("tbody", {}, rowsKeys.map((o) => el("tr", {},
        el("th", { scope: "row" }, labels[1][o]),
        colsKeys.map((d) => {
          const v = cell(o, d);
          return el("td", { class: "flow-cell" },
            el("span", { class: "cell-main" }, v.main),
            v.sub ? el("span", { class: "cell-sub" }, v.sub) : null,
            v.badge ? el("span", { class: `cell-class class-${v.cls}` }, v.badge) : null);
        }))))));
}

function presentKeys(rows) {
  const o = ev.ORIGINS.filter((k) => rows.some((r) => r.origin === k));
  const d = ev.DESTINATIONS.filter((k) => rows.some((r) => r.destination === k));
  return { o, d };
}

async function panelTransferencias(my) {
  const intro = el("p", { class: "warning-line" }, "Não existem dados individuais sobre como cada pessoa mudou o voto; os fluxos abaixo dependem de hipóteses explícitas.");
  if (!ev.isUsable(my.manifest.features.bounds)) {
    return el("div", {}, intro, stateBox("info", "Limites indisponíveis", ev.FEATURE_TEXT[my.manifest.features.bounds]));
  }
  if (my.manifest.validation_status === "failed") {
    return el("div", {}, intro, stateBox("alert", "Análise de transição bloqueada", ev.validationMessage("failed")));
  }
  const modelStatus = my.manifest.features.ecological_model;
  const wantFlows = ev.isUsable(modelStatus) && my.manifest.assets.flows;
  const [b, f, q, metodo] = await Promise.all([
    guard(() => data.getBounds(my.manifest, my.session.signal), "Limites"),
    wantFlows ? guard(() => data.getFlows(my.manifest, my.session.signal), "Estimativas") : Promise.resolve({ value: [] }),
    guard(() => loadQuality(my), "Qualidade"),
    metodoOrNull(),
  ]);
  if (b.error) return el("div", {}, intro, b.error, el("p", { class: "ce-caption" }, "O resumo e a metodologia continuam disponíveis."));
  const labels = ev.categoryLabels(metodo, finalists());
  const base = b.value.filter((r) => r.scenario_id === "base");
  const flows = f.value || [];
  const bIdx = new Map(base.map((r) => [`${r.origin}>${r.destination}`, r]));
  const fIdx = new Map(flows.map((r) => [`${r.origin}>${r.destination}`, r]));
  const keys = presentKeys(base.length ? base : flows);

  const matrix = matrixTable({
    caption: flows.length
      ? "Linhas: categoria no 1º turno. Colunas: categoria no 2º turno. Em votos. Cada célula mostra a classe de identificação; células fracas ou não identificadas mostram só o limite."
      : "Linhas: categoria no 1º turno. Colunas: categoria no 2º turno. Em votos: mínimo e máximo possíveis de cada fluxo, somados seção a seção.",
    labels, rowsKeys: keys.o, colsKeys: keys.d,
    cell: (o, d) => {
      const v = ev.cellView(bIdx.get(`${o}>${d}`) || null, fIdx.get(`${o}>${d}`) || null);
      return { ...v, badge: flows.length && ev.ID_CLASS[v.cls] ? ev.ID_CLASS[v.cls].label : v.cls === "bound" ? "Limite" : null };
    },
  });

  const legend = flows.length ? el("ul", { class: "legend", "aria-label": "Classes de identificação" },
    Object.entries(ev.ID_CLASS).map(([k, v]) => el("li", {}, el("span", { class: `cell-class class-${k}` }, v.label), ` ${v.help}`))) : null;

  let sankey = null;
  if (ev.canShowSankey(my.manifest) && flows.length) {
    const host = el("div", { class: "chart-host", role: "img", "aria-label": "Diagrama de fluxos estimados entre o 1º e o 2º turno; os valores estão na tabela acima." });
    sankey = chartFrame({
      label: "Estimativa pontual", title: "Fluxos estimados entre os turnos",
      subtitle: "Média posterior do modelo. Só células determinadas ou estimadas; o restante aparece como “Não identificado”.",
      evidence: "model_estimate", body: host,
      caption: "Estimativa sob hipótese de taxas iguais nas seções do município; outras distribuições também são compatíveis com os totais. Não são transferências individuais observadas.",
    });
    queueMicrotask(() => charts.sankeyChart(host, ev.sankeyData(flows, labels))
      .catch((e) => mount(host, stateBox("alert", "Gráfico indisponível", `${e.message} A tabela acima traz os mesmos valores.`))));
  }

  const model = q.value?.model;
  const modelBox = el("section", { class: "methodology-note" },
    el("div", { class: "ce-label" }, "Situação da estimativa"),
    el("p", {}, el("strong", {}, `${ev.FEATURE_TEXT[modelStatus] || modelStatus}. `), ev.modelMessage(modelStatus)),
    model && model.methods?.length ? simpleTable({
      caption: "Métodos comparados",
      head: ["Método", "Situação", "Tempo (s)", "Diagnóstico"],
      rows: model.methods.map((m) => [m.method_id, m.status, fmt.dec(m.runtime_s, 1),
        Object.entries(m.diagnostics || {}).map(([k, v]) => `${k}: ${typeof v === "number" ? (Number.isInteger(v) ? fmt.int(v) : fmt.dec(v, 3)) : v}`).join(" · ") || "–"]),
    }) : null,
    model?.predictive_check ? el("p", {}, `Checagem preditiva (${model.predictive_check.k_folds} grupos): erro do modelo ${fmt.dec(model.predictive_check.model_error, 3)} contra ${fmt.dec(model.predictive_check.null_error, 3)} do modelo nulo — ${model.predictive_check.passed ? "passou" : "não passou"}.`) : null,
    model?.identified_change_share != null ? el("p", {}, `Massa de mudança em células determinadas ou estimadas: ${fmt.pct(model.identified_change_share)}.`) : null,
    q.error || null);

  return el("div", {},
    sectionHeading({ label: "Inferência ecológica", title: "O que os dados permitem — e o que não permitem", evidence: flows.length ? "model_estimate" : "conditional_bound",
      text: "Limites mostram o que as margens das seções permitem. A estimativa, quando publicada, depende da hipótese de taxas iguais nas seções do município." }),
    intro, matrix, legend,
    el("p", { class: "ce-caption" }, "Os limites de células diferentes não podem ser atingidos ao mesmo tempo; por isso nunca formam um gráfico de fluxos."),
    sankey, modelBox);
}

async function loadQuality(my) {
  if (my.quality) return my.quality;
  my.quality = await data.loadJsonAsset(my.manifest, "quality", my.session.signal);
  return my.quality;
}

// ---- aba Cenários ----------------------------------------------------------

async function panelCenarios(my) {
  if (!ev.isUsable(my.manifest.features.scenarios)) {
    return stateBox("info", "Cenários indisponíveis", ev.FEATURE_TEXT[my.manifest.features.scenarios]);
  }
  if (my.manifest.validation_status === "failed") return stateBox("alert", "Análise de transição bloqueada", ev.validationMessage("failed"));
  const [sc, b, metodo] = await Promise.all([
    guard(() => data.getScenarios(my.manifest, my.session.signal), "Cenários"),
    guard(() => data.getBounds(my.manifest, my.session.signal), "Limites"),
    metodoOrNull(),
  ]);
  if (sc.error || b.error) return el("div", {}, sc.error || b.error, el("p", { class: "ce-caption" }, "O resumo e a metodologia continuam disponíveis."));
  const labels = ev.categoryLabels(metodo, finalists());
  const meta = new Map((metodo?.scenarios || []).map((s) => [s.id, s]));
  const options = sc.value.filter((s) => s.scenario_id !== "base");
  if (!options.length) return stateBox("info", "Nenhum cenário publicado para este município", null);
  const selId = uid("f-cenario");
  const sel = el("select", { id: selId, class: "ce-input" }, options.map((s) => el("option", { value: s.scenario_id }, meta.get(s.scenario_id)?.label_ptbr || s.scenario_id)));
  const host = el("div", {});
  const base = new Map(b.value.filter((r) => r.scenario_id === "base").map((r) => [`${r.origin}>${r.destination}`, r]));
  const update = () => {
    const s = options.find((o) => o.scenario_id === sel.value);
    const m = meta.get(s.scenario_id);
    const rows = b.value.filter((r) => r.scenario_id === s.scenario_id);
    const idx = new Map(rows.map((r) => [`${r.origin}>${r.destination}`, r]));
    const keys = presentKeys(rows);
    const statusBox = s.status === "feasible"
      ? el("p", { class: "stat-line" }, `Cenário viável em todas as ${fmt.int(s.units_used)} seções usadas.`)
      : stateBox("alert", s.status === "infeasible" ? "Cenário não viável" : "Dados insuficientes",
        s.status === "infeasible" ? `A hipótese contradiz os totais observados em ${fmt.int(s.units_infeasible)} seção(ões). Nenhum dado foi alterado para acomodá-la.` : null);
    mount(host,
      m ? el("p", {}, el("strong", {}, `${m.label_ptbr}. `), m.description_ptbr) : null,
      statusBox,
      s.status === "feasible" ? matrixTable({
        caption: "Mínimo e máximo de cada fluxo sob a hipótese; abaixo, o limite sem hipótese adicional. Em votos.",
        labels, rowsKeys: keys.o, colsKeys: keys.d,
        cell: (o, d) => {
          const r = idx.get(`${o}>${d}`);
          const r0 = base.get(`${o}>${d}`);
          return { cls: "bound", main: r ? fmt.range(r.min_votes, r.max_votes) : fmt.MISSING, sub: r0 ? `sem hipótese: ${fmt.range(r0.min_votes, r0.max_votes)}` : null };
        },
      }) : null);
  };
  sel.addEventListener("change", update);
  update();
  return el("div", {},
    sectionHeading({ label: "Hipóteses", title: "Comparar explicações possíveis", evidence: "conditional_bound",
      text: "Cada cenário é uma restrição hipotética, não uma observação. Só aparecem cenários pré-calculados no pipeline; o navegador não resolve modelos." }),
    el("div", { class: "filters" }, el("div", {}, el("label", { for: selId }, "Cenário"), sel)),
    host);
}

// ---- aba Qualidade ---------------------------------------------------------

async function panelQualidade(my) {
  const q = await guard(() => loadQuality(my), "Qualidade");
  const man = my.manifest;
  const versions = simpleTable({
    caption: "Versões",
    head: ["Item", "Valor"],
    rows: [
      ["Publicação (release)", man.release_id],
      ["Versão do contrato de dados", man.schema_version],
      ["Commit do pipeline", man.pipeline_git_sha],
      ["Versão do método", man.method_version],
      ["Gerado em", fmt.datetime(man.generated_at)],
    ],
  });
  const sources = el("div", { class: "data-table-wrap" }, el("table", { class: "ce-table" },
    el("caption", {}, "Arquivos de origem"),
    el("thead", {}, el("tr", {}, ["Fonte", "Arquivo", "Coleta", "sha256"].map((h) => el("th", { scope: "col" }, h)))),
    el("tbody", {}, man.sources.map((s) => el("tr", {},
      el("th", { scope: "row" }, `${s.provider} · ${s.dataset}`),
      el("td", {}, s.source_url ? el("a", { href: s.source_url }, s.file) : s.file),
      el("td", {}, s.collected_at ? fmt.datetime(s.collected_at) : fmt.MISSING),
      el("td", { class: "hash" }, s.source_sha256 || fmt.MISSING))))));
  const mandatory = el("p", { class: "warning-line" }, "Resultados agregados não identificam transferências individuais de voto.");
  if (q.error) return el("div", {}, q.error, versions, sources, mandatory);
  const ql = q.value;
  const sc = ql.section_coverage;
  const grid = el("div", { class: "quality-grid" },
    el("div", {}, el("span", {}, "Verificações"), el("strong", {}, { passed: "Aprovadas", partial: "Com ressalvas", failed: "Divergência sem explicação" }[ql.validation_status])),
    el("div", {}, el("span", {}, "Seções instaladas"), el("strong", {}, `${fmt.int(sc.sections_installed)} de ${fmt.int(sc.sections_total)}`)),
    el("div", {}, el("span", {}, "Na análise de transição"), el("strong", {}, `${fmt.int(sc.units_in_transition_analysis)} (${fmt.pct(sc.eligible_share_used)} dos aptos)`)),
    el("div", {}, el("span", {}, "Estimativa ecológica"), el("strong", {}, ev.FEATURE_TEXT[ql.model.status] || ql.model.status)));
  const family = { integrity: "Integridade (V1)", harmonization: "Harmonização (V2)", official_totals: "Totais oficiais (V3)" };
  const checks = simpleTable({
    caption: "Verificações (docs/05 §2)",
    head: ["Verificação", "Família", "Resultado", "Falhas", "Explicação"],
    rows: ql.checks.map((c) => [c.id, family[c.family], c.passed ? "Passou" : "Falhou", fmt.int(c.count_failed), c.explanation_code || "–"]),
  });
  const excl = Object.entries(sc.excluded_by_reason || {});
  const exclTable = excl.length ? simpleTable({
    caption: "Seções fora da análise de transição (continuam nos totais)",
    head: ["Motivo", "Seções"], rows: excl.map(([k, v]) => [ev.EXCLUSION_TEXT[k] || k, fmt.int(v)]),
  }) : el("p", { class: "stat-line" }, "Nenhuma seção ficou fora da análise de transição.");
  const pop = simpleTable({
    caption: `Aptos entre os turnos (tolerância: ${sc.net_change_tolerance_rule})`,
    head: ["Classe", "Seções"],
    rows: Object.entries(ql.population).map(([k, v]) => [ev.POPULATION_TEXT[k] || k, fmt.int(v)]),
  });
  const m = ql.model;
  const modelRows = [
    ["Situação", ev.FEATURE_TEXT[m.status] || m.status],
    ["Motivo", m.reason_unavailable || "–"],
    ["Seções usadas", fmt.int(m.n_units_used)],
    ["Massa de mudança identificada", m.identified_change_share == null ? "–" : fmt.pct(m.identified_change_share)],
    ["Checagem preditiva", m.predictive_check ? `${m.predictive_check.passed ? "passou" : "não passou"} (erro ${fmt.dec(m.predictive_check.model_error, 3)} contra ${fmt.dec(m.predictive_check.null_error, 3)})` : "–"],
    ["Calibração", m.calibration_id || "–"],
  ];
  return el("div", {},
    sectionHeading({ label: "Transparência", title: "Qualidade, cobertura e proveniência", text: `Calculado em ${fmt.datetime(ql.computed_at)}.` }),
    grid, mandatory, checks, exclTable, pop,
    simpleTable({ caption: "Estimativa ecológica", head: ["Item", "Valor"], rows: modelRows }),
    sources, versions);
}
