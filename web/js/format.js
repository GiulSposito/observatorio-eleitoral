// Formatação pt-BR num lugar só: votos, variações com sinal, percentuais, pontos
// percentuais, intervalos e datas. Ausente vira "–", nunca zero. Sem DOM.

const LOCALE = "pt-BR";
const MINUS = "−";
export const MISSING = "–";

function isMissing(x) {
  return x === null || x === undefined || (typeof x === "number" && !Number.isFinite(x));
}

function fixed(x, dp) {
  // sinal de menos tipográfico também nos negativos sem sinal explícito
  return Number(x).toLocaleString(LOCALE, { minimumFractionDigits: dp, maximumFractionDigits: dp }).replace("-", MINUS);
}

// 1234 -> "1.234"
export function int(x) {
  if (isMissing(x)) return MISSING;
  return fixed(Math.round(Number(x)), 0);
}

// Número com casas decimais fixas: dec(0.8312, 2) -> "0,83"
export function dec(x, dp = 1) {
  if (isMissing(x)) return MISSING;
  return fixed(x, dp);
}

// Variação com sinal explícito e menos tipográfico: +604, −131, 0
export function signed(x, dp = 0) {
  if (isMissing(x)) return MISSING;
  const v = Number(x);
  const r = dp === 0 ? Math.round(v) : v;
  if (r === 0) return fixed(0, dp);
  return (r > 0 ? "+" : MINUS) + fixed(Math.abs(r), dp);
}

// Fração -> percentual: pct(0.123) -> "12,3%"
export function pct(x, dp = 1) {
  if (isMissing(x)) return MISSING;
  return fixed(Number(x) * 100, dp) + "%";
}

// Diferença entre duas frações, em pontos percentuais: pp(0.052) -> "+5,2 p.p."
export function pp(x, dp = 1) {
  if (isMissing(x)) return MISSING;
  return signed(Number(x) * 100, dp) + " p.p.";
}

export function votes(x) {
  if (isMissing(x)) return MISSING;
  const n = Math.round(Number(x));
  return int(n) + (Math.abs(n) === 1 ? " voto" : " votos");
}

export function signedVotes(x) {
  if (isMissing(x)) return MISSING;
  const n = Math.round(Number(x));
  return signed(n) + (Math.abs(n) === 1 ? " voto" : " votos");
}

// Intervalo de contagens: range(120, 410) -> "120 a 410"
export function range(lo, hi) {
  if (isMissing(lo) || isMissing(hi)) return MISSING;
  const a = Math.round(Number(lo));
  const b = Math.round(Number(hi));
  return a === b ? int(a) : `${int(a)} a ${int(b)}`;
}

// Taxa por 100 aptos
export function per100(x, base, dp = 1) {
  if (isMissing(x) || isMissing(base) || Number(base) === 0) return null;
  return (Number(x) * 100) / Number(base);
}

const MONTHS = ["janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto",
  "setembro", "outubro", "novembro", "dezembro"];

// "2026-10-04" -> "4 de outubro de 2026" (data civil, sem fuso)
export function date(iso) {
  if (!iso) return MISSING;
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(iso));
  if (!m) return MISSING;
  return `${Number(m[3])} de ${MONTHS[Number(m[2]) - 1]} de ${m[1]}`;
}

// "2026-10-27T18:00:00Z" -> "27/10/2026, 15:00 (horário de Brasília)"
export function datetime(iso) {
  if (!iso) return MISSING;
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return MISSING;
  const s = d.toLocaleString(LOCALE, {
    timeZone: "America/Sao_Paulo", day: "2-digit", month: "2-digit", year: "numeric",
    hour: "2-digit", minute: "2-digit",
  });
  return `${s} (horário de Brasília)`;
}

// Abreviação de hash/sha para exibição; o valor completo vai no title/tabela.
export function shortHash(h, n = 12) {
  if (!h) return MISSING;
  return String(h).slice(0, n) + (String(h).length > n ? "…" : "");
}

export function bytes(n) {
  if (isMissing(n)) return MISSING;
  const v = Number(n);
  if (v < 1024) return `${int(v)} B`;
  if (v < 1024 * 1024) return `${dec(v / 1024, 1)} KB`;
  return `${dec(v / (1024 * 1024), 1)} MB`;
}
