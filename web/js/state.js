// Recorte selecionado, sempre na URL: explorar.html?e=<election_id>&m=<municipio_tse>&aba=<aba>.
// parse()/toSearch() são puros (testáveis em node); push()/replace() mexem no history.
// Valores fora do formato esperado são descartados aqui; a validação contra o catálogo
// acontece na página (um código bem formado pode não existir).

export const TABS = ["resumo", "secoes", "transferencias", "cenarios", "qualidade"];
export const DEFAULT_TAB = "resumo";

const RE_ELECTION = /^[0-9a-z][0-9a-z-]{0,40}$/;
const RE_MUNICIPIO = /^[0-9]{5}$/;

export function parse(search) {
  const p = new URLSearchParams(search || "");
  const e = p.get("e");
  const m = p.get("m");
  const aba = p.get("aba");
  return {
    e: e && RE_ELECTION.test(e) ? e : null,
    m: m && RE_MUNICIPIO.test(m) ? m : null,
    aba: aba && TABS.includes(aba) ? aba : DEFAULT_TAB,
  };
}

export function toSearch(s) {
  const p = new URLSearchParams();
  if (s.e) p.set("e", s.e);
  if (s.m) p.set("m", s.m);
  if (s.aba && s.aba !== DEFAULT_TAB) p.set("aba", s.aba);
  const q = p.toString();
  return q ? `?${q}` : "";
}

export function explorarHref(s) {
  return `explorar.html${toSearch(s)}`;
}

export function sameMunicipio(a, b) {
  return Boolean(a && b && a.e === b.e && a.m === b.m);
}

// ---- browser --------------------------------------------------------------

export function read() {
  return parse(window.location.search);
}

function write(s, mode) {
  const url = new URL(window.location.href);
  url.search = toSearch(s);
  if (mode === "push") history.pushState(null, "", url);
  else history.replaceState(null, "", url);
}

// Troca de município ou de aba que deve entrar no Voltar/Avançar.
export function push(s) { write(s, "push"); }
// Correção de URL inválida, sem criar entrada no histórico.
export function replace(s) { write(s, "replace"); }
