// Busca de município sobre catalogo.json, sem DuckDB. Normaliza acentos (NFD),
// caixa e pontuação; distingue homônimos pela UF; aceita código TSE. Sem DOM.

export const UFS = ["AC", "AL", "AM", "AP", "BA", "CE", "DF", "ES", "GO", "MA", "MG", "MS", "MT", "PA",
  "PB", "PE", "PI", "PR", "RJ", "RN", "RO", "RR", "RS", "SC", "SE", "SP", "TO"];

export function normalize(s) {
  return String(s || "")
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

export function buildIndex(catalog) {
  const items = (catalog?.municipalities || []).map((m) => ({
    ...m,
    _norm: normalize(m.display_name || m.name),
    _words: normalize(m.display_name || m.name).split(" "),
  }));
  items.sort((a, b) => a._norm.localeCompare(b._norm) || a.uf.localeCompare(b.uf));
  const byCode = new Map(items.map((m) => [m.municipio_tse, m]));
  return { items, byCode };
}

export function findByCode(index, code) {
  return index.byCode.get(String(code)) || null;
}

export function label(m) {
  return `${m.display_name || m.name} — ${m.uf}`;
}

// Separa uma UF no fim da consulta: "vale sereno mg", "vale sereno - MG", "vale sereno/mg".
function splitUf(qNorm) {
  const parts = qNorm.split(" ");
  if (parts.length > 1) {
    const last = parts[parts.length - 1].toUpperCase();
    if (UFS.includes(last)) return { text: parts.slice(0, -1).join(" "), uf: last };
  }
  return { text: qNorm, uf: null };
}

function score(item, text) {
  if (item._norm === text) return 0;
  if (item._norm.startsWith(text)) return 1;
  if (item._words.some((w) => w.startsWith(text))) return 2;
  if (item._norm.includes(text)) return 3;
  return -1;
}

// Retorna até `limit` municípios. Consultas:
//  - código TSE (2 a 5 dígitos): prefixo do código;
//  - sigla de UF sozinha ("sc"): municípios daquela UF;
//  - nome (mínimo 2 caracteres), opcionalmente seguido de UF.
export function search(index, query, { limit = 12 } = {}) {
  const raw = String(query || "").trim();
  if (/^[0-9]{2,5}$/.test(raw)) {
    return index.items.filter((m) => m.municipio_tse.startsWith(raw))
      .sort((a, b) => a.municipio_tse.localeCompare(b.municipio_tse))
      .slice(0, limit);
  }
  const qNorm = normalize(raw);
  if (qNorm.length < 2) return [];
  if (qNorm.length === 2 && UFS.includes(qNorm.toUpperCase())) {
    const uf = qNorm.toUpperCase();
    const named = rank(index.items, qNorm, null).filter((m) => m.uf !== uf);
    const inUf = index.items.filter((m) => m.uf === uf);
    return [...inUf, ...named].slice(0, limit);
  }
  const { text, uf } = splitUf(qNorm);
  if (text.length < 2) return [];
  return rank(index.items, text, uf).slice(0, limit);
}

function rank(items, text, uf) {
  const hits = [];
  for (const m of items) {
    if (uf && m.uf !== uf) continue;
    const s = score(m, text);
    if (s >= 0) hits.push([s, m]);
  }
  hits.sort((a, b) => a[0] - b[0] || a[1]._norm.localeCompare(b[1]._norm) || a[1].uf.localeCompare(b[1].uf));
  return hits.map((h) => h[1]);
}

// Nomes repetidos em UFs diferentes: o rótulo precisa da UF para desambiguar.
export function homonyms(index, item) {
  return index.items.filter((m) => m._norm === item._norm && m.municipio_tse !== item.municipio_tse);
}
