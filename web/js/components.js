// Blocos de interface. Recebem dados prontos; não buscam arquivos nem montam SQL ou URLs de dados.

import * as fmt from "./format.js";
import { EVIDENCE } from "./evidence.js";
import { search, label as muniLabel } from "./catalog.js";

// ---- DOM ----------------------------------------------------------------

export function el(tag, attrs = {}, ...kids) {
  const n = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v == null || v === false) continue;
    if (k === "class") n.className = v;
    else if (k === "html") n.innerHTML = v;
    else if (k === "text") n.textContent = v;
    else if (k.startsWith("on") && typeof v === "function") n.addEventListener(k.slice(2), v);
    else n.setAttribute(k, v === true ? "" : v);
  }
  for (const kid of kids.flat(Infinity)) {
    if (kid == null || kid === false) continue;
    n.append(kid.nodeType ? kid : document.createTextNode(String(kid)));
  }
  return n;
}

export function mount(root, ...kids) {
  root.replaceChildren(...kids.flat(Infinity).filter((k) => k != null && k !== false));
}

let _uid = 0;
export function uid(prefix = "ce") { _uid += 1; return `${prefix}-${_uid}`; }

// ---- estados --------------------------------------------------------------

// kind: info | alert
export function stateBox(kind, title, text, ...extra) {
  return el("div", { class: `ce-state ${kind === "alert" ? "alert" : ""}`, role: kind === "alert" ? "alert" : "status" },
    el("strong", {}, title), text ? el("span", {}, text) : null, ...extra);
}

export function skeleton(lines = 3, tall = false) {
  return el("div", { "aria-busy": "true", "aria-label": "Carregando" },
    tall ? el("div", { class: "ce-skeleton tall" }) : null,
    Array.from({ length: lines }, () => el("div", { class: "ce-skeleton" })));
}

export function errorState(err, what) {
  const title = err?.kind === "wasm" ? "Consulta por seção indisponível neste navegador"
    : err?.kind === "network" ? "Falha de rede"
    : err?.kind === "not_found" ? "Dados não publicados"
    : "Não foi possível carregar";
  return stateBox("alert", title, `${what ? what + ": " : ""}${err?.message || "erro desconhecido."}`);
}

export function methodTag(evidenceKey) {
  const e = EVIDENCE[evidenceKey] || EVIDENCE.unavailable;
  return el("span", { class: `ce-method-tag ${e.cls}` }, e.tag);
}

export function sectionHeading({ label, title, text, evidence, id }) {
  return el("div", { class: "section-heading" },
    el("div", {},
      label ? el("div", { class: "ce-label" }, label) : null,
      el("h2", { id }, title),
      text ? el("p", {}, text) : null),
    evidence ? methodTag(evidence) : null);
}

// Bloco de gráfico na ordem do guia (01 §5.5): título → subtítulo → gráfico → leitura → fonte → tabela.
export function chartFrame({ label, title, subtitle, evidence, body, caption, table, source }) {
  const titleId = uid("chart-title");
  return el("article", { class: "chart-frame", "aria-labelledby": titleId },
    el("div", { class: "section-heading" },
      el("div", {},
        label ? el("div", { class: "ce-label" }, label) : null,
        el("h3", { class: "chart-title", id: titleId }, title),
        subtitle ? el("p", { class: "chart-subtitle" }, subtitle) : null),
      evidence ? methodTag(evidence) : null),
    el("figure", {}, body,
      caption ? el("figcaption", { class: "ce-caption" }, caption) : null),
    source ? el("p", { class: "ce-caption" }, source) : null,
    table ? el("details", { class: "chart-table-toggle" }, el("summary", {}, "Ver tabela com os valores"), table) : null);
}

// ---- faixa de indicadores -------------------------------------------------

export function metricStrip(items) {
  return el("div", { class: "metric-grid", role: "list", "aria-label": "Indicadores do município" },
    items.map((m) => el("div", { class: `metric ${m.slot ? "slot-" + m.slot : ""}`, role: "listitem" },
      el("span", { class: "metric-name" }, m.name),
      el("strong", { class: "ce-numeric" }, m.value),
      m.sub ? el("span", { class: "metric-sub" }, m.sub) : null)));
}

// ---- tabela ordenável e paginada -----------------------------------------

// columns: [{key, label, num?, format?(v,row), sortValue?(row)}]
export function dataTable({ caption, columns, rows, pageSize = 0, rowClass, initialSort }) {
  const wrap = el("div", { class: "data-table-wrap", tabindex: "0", role: "region", "aria-label": caption || "Tabela" });
  let sortKey = initialSort?.key || null;
  let sortDir = initialSort?.dir || "ascending";
  let page = 0;

  const sorted = () => {
    if (!sortKey) return rows;
    const col = columns.find((c) => c.key === sortKey);
    const val = (r) => (col.sortValue ? col.sortValue(r) : r[col.key]);
    const dir = sortDir === "ascending" ? 1 : -1;
    return [...rows].sort((a, b) => {
      const va = val(a);
      const vb = val(b);
      if (va == null && vb == null) return 0;
      if (va == null) return 1;
      if (vb == null) return -1;
      return (va < vb ? -1 : va > vb ? 1 : 0) * dir;
    });
  };

  const render = () => {
    const all = sorted();
    const pages = pageSize ? Math.max(1, Math.ceil(all.length / pageSize)) : 1;
    page = Math.min(page, pages - 1);
    const shown = pageSize ? all.slice(page * pageSize, (page + 1) * pageSize) : all;
    const thead = el("thead", {}, el("tr", {}, columns.map((c) => {
      const isSorted = c.key === sortKey;
      return el("th", { scope: "col", class: c.num ? "num" : null, "aria-sort": isSorted ? sortDir : "none" },
        el("button", {
          type: "button",
          onclick: () => {
            if (sortKey === c.key) sortDir = sortDir === "ascending" ? "descending" : "ascending";
            else { sortKey = c.key; sortDir = "ascending"; }
            render();
          },
        }, c.label, el("span", { "aria-hidden": "true" }, isSorted ? (sortDir === "ascending" ? " ↑" : " ↓") : "")));
    })));
    const tbody = el("tbody", {}, shown.map((r) => el("tr", { class: rowClass ? rowClass(r) : null },
      columns.map((c, i) => {
        const v = c.format ? c.format(r[c.key], r) : r[c.key];
        const attrs = { class: c.num ? "num" : c.flag ? "flag" : null };
        return i === 0 ? el("th", { ...attrs, scope: "row" }, v ?? fmt.MISSING) : el("td", attrs, v ?? fmt.MISSING);
      }))));
    const table = el("table", { class: "ce-table" }, caption ? el("caption", {}, caption) : null, thead, tbody);
    const pager = pageSize && pages > 1 ? el("div", { class: "table-pager" },
      el("button", { type: "button", class: "ce-button", disabled: page === 0, onclick: () => { page -= 1; render(); } }, "Anteriores"),
      el("span", { "aria-live": "polite" }, `Página ${page + 1} de ${pages} · ${fmt.int(all.length)} linhas`),
      el("button", { type: "button", class: "ce-button", disabled: page >= pages - 1, onclick: () => { page += 1; render(); } }, "Próximas")) : null;
    mount(wrap, table, pager);
  };
  render();
  return wrap;
}

// Tabela simples (sem ordenação) para equivalentes de gráfico.
export function simpleTable({ caption, head, rows }) {
  return el("div", { class: "data-table-wrap", tabindex: "0", role: "region", "aria-label": caption || "Tabela" },
    el("table", { class: "ce-table" },
      caption ? el("caption", {}, caption) : null,
      el("thead", {}, el("tr", {}, head.map((h, i) => el("th", { scope: "col", class: i > 0 ? "num" : null }, h)))),
      el("tbody", {}, rows.map((r) => el("tr", {}, r.map((v, i) => (i === 0 ? el("th", { scope: "row" }, v) : el("td", { class: "num" }, v))))))));
}

// ---- combobox de município (WAI-ARIA 1.2) --------------------------------

export function municipalityCombobox({ index, onSelect, labelText = "Município", hint, autofocus = false }) {
  const inputId = uid("muni-input");
  const listId = uid("muni-list");
  const statusId = uid("muni-status");
  let results = [];
  let active = -1;

  const input = el("input", {
    id: inputId, class: "ce-input", type: "text", role: "combobox", autocomplete: "off", spellcheck: "false",
    "aria-autocomplete": "list", "aria-expanded": "false", "aria-controls": listId,
    placeholder: "Digite o nome do município", "aria-describedby": hint ? `${inputId}-hint` : null,
  });
  const list = el("ul", { id: listId, class: "combobox-list", role: "listbox", "aria-label": "Municípios encontrados", hidden: true });
  const status = el("div", { id: statusId, class: "sr-only", role: "status", "aria-live": "polite" });

  const close = () => {
    list.hidden = true;
    input.setAttribute("aria-expanded", "false");
    input.removeAttribute("aria-activedescendant");
    active = -1;
  };
  const setActive = (i) => {
    active = i;
    [...list.children].forEach((li, k) => li.setAttribute("aria-selected", String(k === i)));
    const li = list.children[i];
    if (li && li.id) {
      input.setAttribute("aria-activedescendant", li.id);
      li.scrollIntoView({ block: "nearest" });
    }
  };
  const choose = (m) => {
    if (!m) return;
    input.value = muniLabel(m);
    close();
    onSelect(m);
  };
  const update = () => {
    results = search(index, input.value, { limit: 12 });
    const q = input.value.trim();
    if (!q) { close(); status.textContent = ""; return; }
    if (!results.length) {
      mount(list, el("li", { class: "combobox-empty", role: "option", "aria-disabled": "true", "aria-selected": "false" },
        q.length < 2 ? "Digite pelo menos duas letras." : "Nenhum município encontrado. Tente sem abreviações ou só parte do nome."));
    } else {
      mount(list, results.map((m, k) => el("li", {
        id: `${listId}-opt-${k}`, class: "combobox-option", role: "option", "aria-selected": "false",
        onmousedown: (e) => { e.preventDefault(); choose(m); },
      }, el("span", { class: "opt-main" }, muniLabel(m)), el("span", { class: "opt-sub" }, `Código TSE ${m.municipio_tse}`))));
    }
    list.hidden = false;
    input.setAttribute("aria-expanded", "true");
    active = -1;
    input.removeAttribute("aria-activedescendant");
    status.textContent = results.length ? `${results.length} município${results.length > 1 ? "s" : ""} encontrado${results.length > 1 ? "s" : ""}.` : "Nenhum município encontrado.";
  };

  input.addEventListener("input", update);
  input.addEventListener("focus", () => { if (input.value.trim()) update(); });
  input.addEventListener("blur", () => setTimeout(close, 120));
  input.addEventListener("keydown", (e) => {
    if (e.key === "ArrowDown") {
      e.preventDefault();
      if (list.hidden) update();
      if (results.length) setActive(Math.min(active + 1, results.length - 1));
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      if (results.length) setActive(Math.max(active - 1, 0));
    } else if (e.key === "Enter") {
      if (!list.hidden && results.length) {
        e.preventDefault();
        choose(results[active >= 0 ? active : 0]);
      }
    } else if (e.key === "Escape") {
      if (!list.hidden) { e.preventDefault(); close(); } else { input.value = ""; }
    }
  });
  if (autofocus) setTimeout(() => input.focus(), 0);

  return el("div", { class: "combobox" },
    el("label", { for: inputId }, labelText),
    input, list, status,
    hint ? el("div", { id: `${inputId}-hint`, class: "combobox-hint" }, hint) : null);
}
