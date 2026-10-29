// Checks de web/js/state.js (parse/serialização da URL). Rodar da raiz:  node tests/web/state.check.mjs
import assert from "node:assert/strict";
import { parse, toSearch, explorarHref, sameMunicipio, TABS, DEFAULT_TAB } from "../../web/js/state.js";

assert.deepEqual(parse("?e=2026-presidente&m=00000&aba=secoes"), { e: "2026-presidente", m: "00000", aba: "secoes" });
assert.deepEqual(parse(""), { e: null, m: null, aba: DEFAULT_TAB });

// valores fora do formato são descartados (a URL nunca chega crua a caminho ou SQL)
assert.equal(parse("?m=123").m, null, "código precisa de 5 dígitos");
assert.equal(parse("?m=00000'; DROP TABLE x;--").m, null);
assert.equal(parse("?m=../../etc").m, null);
assert.equal(parse("?e=2026 presidente").e, null);
assert.equal(parse("?e=../latest").e, null);
assert.equal(parse("?aba=horarios").aba, DEFAULT_TAB, "aba fora do escopo cai no resumo");
assert.equal(parse("?aba=transferencias").aba, "transferencias");

assert.equal(toSearch({ e: "2026-presidente", m: "00000", aba: "resumo" }), "?e=2026-presidente&m=00000");
assert.equal(toSearch({ e: "2026-presidente", m: "00001", aba: "qualidade" }), "?e=2026-presidente&m=00001&aba=qualidade");
assert.equal(toSearch({}), "");
assert.equal(explorarHref({ e: "2026-presidente", m: "00002" }), "explorar.html?e=2026-presidente&m=00002");

// ida e volta
for (const aba of TABS) {
  const s = { e: "2026-presidente", m: "12345", aba };
  assert.deepEqual(parse(toSearch(s)), s);
}

assert.equal(sameMunicipio({ e: "x", m: "00000" }, { e: "x", m: "00000" }), true);
assert.equal(sameMunicipio({ e: "x", m: "00000" }, { e: "x", m: "00001" }), false);
assert.equal(sameMunicipio(null, { e: "x", m: "00001" }), false);
assert.ok(!TABS.includes("horarios"), "aba Horários está fora do escopo");

console.log("state.check: ok");
