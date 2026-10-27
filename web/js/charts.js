// Gráficos. O slope do Resumo é SVG próprio (primeiro paint sem bibliotecas); os gráficos das
// abas de detalhe usam Plotly, carregado sob demanda. Recebem dados prontos; não buscam nada.

import * as fmt from "./format.js";
import { PLOTLY_URL } from "./vendor.js";

const SVG_NS = "http://www.w3.org/2000/svg";

function token(name, fallback) {
  const v = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
  return v || fallback;
}

export function colors() {
  return {
    A: token("--color-candidate-a", "#315D68"),
    B: token("--color-candidate-b", "#9B5C34"),
    other: token("--color-other", "#6B7370"),
    invalid: token("--color-invalid", "#737874"),
    turnout: token("--color-turnout", "#5F6C4B"),
    ink: token("--color-ink", "#202927"),
    muted: token("--color-muted", "#57645F"),
    border: token("--color-border", "#D8DDD7"),
    surface: token("--color-surface", "#FFFFFF"),
  };
}

function svg(tag, attrs = {}, text) {
  const n = document.createElementNS(SVG_NS, tag);
  for (const [k, v] of Object.entries(attrs)) n.setAttribute(k, String(v));
  if (text != null) n.textContent = String(text);
  return n;
}

function niceMax(v) {
  if (!(v > 0)) return 1;
  const p = 10 ** Math.floor(Math.log10(v));
  const m = v / p;
  const step = m <= 1 ? 1 : m <= 2 ? 2 : m <= 2.5 ? 2.5 : m <= 5 ? 5 : 10;
  return step * p;
}

// Votos dos dois finalistas no 1º e no 2º turno, escala a partir de zero.
export function slopeChart(finalists, titleId) {
  const c = colors();
  const W = 720; const H = 310;
  const left = 70; const right = 640; const top = 36; const bottom = 258;
  const x1 = 190; const x2 = 530;
  const max = niceMax(Math.max(...finalists.flatMap((f) => [f.round_1_votes || 0, f.round_2_votes || 0])) * 1.08);
  const y = (v) => bottom - (v / max) * (bottom - top);
  const descId = `${titleId}-desc`;
  const root = svg("svg", { class: "svg-chart", viewBox: `0 0 ${W} ${H}`, role: "img", "aria-labelledby": `${titleId} ${descId}`, preserveAspectRatio: "xMidYMid meet" });
  root.append(svg("desc", { id: descId }, finalists.map((f) =>
    `${f.slot}: ${fmt.int(f.round_1_votes)} votos no 1º turno e ${fmt.int(f.round_2_votes)} no 2º turno`).join("; ")));
  for (const t of [0, max / 2, max]) {
    root.append(svg("line", { x1: left, x2: right, y1: y(t), y2: y(t), stroke: c.border, "stroke-width": 1 }));
    root.append(svg("text", { x: left - 10, y: y(t) + 4, fill: c.muted, "font-size": 13, "text-anchor": "end" }, fmt.int(t)));
  }
  for (const [x, lab] of [[x1, "1º turno"], [x2, "2º turno"]]) {
    root.append(svg("text", { x, y: H - 18, fill: c.muted, "font-size": 13, "text-anchor": "middle" }, lab));
  }
  const ends = finalists.map((f) => ({ f, y2: y(f.round_2_votes || 0) }));
  const close = ends.length === 2 && Math.abs(ends[0].y2 - ends[1].y2) < 24;
  ends.forEach(({ f, y2 }, i) => {
    const col = c[f.slot] || c.ink;
    const y1 = y(f.round_1_votes || 0);
    root.append(svg("line", { x1, y1, x2, y2, stroke: col, "stroke-width": 3.5, "stroke-linecap": "round" }));
    for (const [xx, yy] of [[x1, y1], [x2, y2]]) {
      root.append(svg("circle", { cx: xx, cy: yy, r: 5, fill: col, stroke: c.surface, "stroke-width": 1.5 }));
    }
    const dy = close ? (ends[0].y2 <= ends[1].y2 ? (i === 0 ? -12 : 20) : (i === 0 ? 20 : -12)) : 5;
    root.append(svg("text", { x: x2 + 14, y: y2 + dy, fill: col, "font-size": 14, "font-weight": 600 }, `${f.slot} · ${fmt.int(f.round_2_votes)}`));
    root.append(svg("text", { x: x1 - 14, y: y1 + 5, fill: col, "font-size": 13, "text-anchor": "end" }, fmt.int(f.round_1_votes)));
  });
  return root;
}

// ---- Plotly sob demanda ------------------------------------------------------

let _plotly = null;
export function loadPlotly() {
  if (window.Plotly) return Promise.resolve(window.Plotly);
  if (_plotly) return _plotly;
  _plotly = new Promise((resolve, reject) => {
    const s = document.createElement("script");
    s.src = PLOTLY_URL;
    s.async = true;
    s.charset = "utf-8";
    s.onload = () => resolve(window.Plotly);
    s.onerror = () => { _plotly = null; reject(new Error("Não foi possível carregar a biblioteca de gráficos.")); };
    document.head.append(s);
  });
  return _plotly;
}

const CONFIG = {
  displaylogo: false,
  responsive: true,
  modeBarButtonsToRemove: ["select2d", "lasso2d", "autoScale2d", "toggleSpikelines", "hoverClosestCartesian", "hoverCompareCartesian"],
};

function baseLayout(extra = {}) {
  const c = colors();
  return {
    separators: ",.",
    font: { family: "IBM Plex Sans, system-ui, sans-serif", size: 13, color: c.ink },
    paper_bgcolor: "rgba(0,0,0,0)",
    plot_bgcolor: "rgba(0,0,0,0)",
    margin: { l: 64, r: 16, t: 12, b: 56 },
    hoverlabel: { bgcolor: c.surface, bordercolor: c.border, font: { color: c.ink } },
    ...extra,
  };
}

// Pontos: [{x, y, label}] já normalizados. Linha de referência no zero.
export async function sectionScatter(host, points, { xTitle, yTitle, slot }) {
  const Plotly = await loadPlotly();
  const c = colors();
  const trace = {
    type: "scatter", mode: "markers",
    x: points.map((p) => p.x), y: points.map((p) => p.y), text: points.map((p) => p.label),
    hovertemplate: "%{text}<br>" + xTitle + ": %{x:.1f}<br>" + yTitle + ": %{y:.1f}<extra></extra>",
    marker: { size: 8, color: c[slot] || c.ink, opacity: 0.75, line: { width: 1, color: c.surface } },
  };
  const axis = (title) => ({ title: { text: title, standoff: 8 }, zeroline: true, zerolinecolor: c.muted, zerolinewidth: 1, gridcolor: c.border, linecolor: c.border, tickformat: ",.0f" });
  await Plotly.react(host, [trace], baseLayout({ xaxis: axis(xTitle), yaxis: axis(yTitle), height: 380 }), CONFIG);
  return host;
}

// Sankey da estimativa pontual (só com ecological_model = ready). data = evidence.sankeyData().
export async function sankeyChart(host, data) {
  const Plotly = await loadPlotly();
  const c = colors();
  const nodeColor = (n) => (n.code === "A" ? c.A : n.code === "B" ? c.B : n.code === "?" ? "#C9CFCB" : n.code === "X" ? "#8E9692" : c.other);
  const idx = new Map(data.nodes.map((n, i) => [n.id, i]));
  const linkColor = (l) => (l.kind === "not_identified" ? "rgba(160,170,164,0.35)"
    : l.kind === "determined" ? "rgba(49,93,104,0.32)" : "rgba(155,92,52,0.30)");
  const trace = {
    type: "sankey", arrangement: "snap", valueformat: ",.0f", valuesuffix: " votos",
    node: { label: data.nodes.map((n) => n.label), color: data.nodes.map(nodeColor), pad: 18, thickness: 16, line: { width: 0 } },
    link: {
      source: data.links.map((l) => idx.get(l.source)), target: data.links.map((l) => idx.get(l.target)),
      value: data.links.map((l) => l.value), color: data.links.map(linkColor),
      customdata: data.links.map((l) => (l.kind === "not_identified" ? "não identificado" : l.kind === "determined" ? "determinado pelas margens" : "estimado pelo modelo")),
      hovertemplate: "%{source.label} → %{target.label}<br>%{value} (%{customdata})<extra></extra>",
    },
  };
  await Plotly.react(host, [trace], baseLayout({ height: 460, margin: { l: 8, r: 8, t: 8, b: 8 } }), { ...CONFIG, modeBarButtonsToRemove: undefined, displayModeBar: false });
  return host;
}

export function purge(host) {
  if (window.Plotly && host) window.Plotly.purge(host);
}
