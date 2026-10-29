// Checks de web/js/format.js. Rodar da raiz:  node tests/web/format.check.mjs
import assert from "node:assert/strict";
import * as fmt from "../../web/js/format.js";

const M = "−";

assert.equal(fmt.int(1234), "1.234");
assert.equal(fmt.int(1234567), "1.234.567");
assert.equal(fmt.int(null), "–");
assert.equal(fmt.int(undefined), "–");
assert.equal(fmt.int(NaN), "–");
assert.equal(fmt.int(0), "0");

assert.equal(fmt.signed(604), "+604");
assert.equal(fmt.signed(-131), `${M}131`);
assert.equal(fmt.signed(0), "0");
assert.equal(fmt.signed(1500), "+1.500");
assert.equal(fmt.signed(null), "–");
assert.equal(fmt.signed(2.345, 1), "+2,3");

assert.equal(fmt.dec(0.8312, 2), "0,83");
assert.equal(fmt.dec(-0.19, 2), `${M}0,19`, "negativos usam o menos tipográfico");

assert.equal(fmt.pct(0.123), "12,3%");
assert.equal(fmt.pct(1), "100,0%");
assert.equal(fmt.pct(null), "–");

// pontos percentuais: diferença entre frações, com sinal e unidade explícita
assert.equal(fmt.pp(0.052), "+5,2 p.p.");
assert.equal(fmt.pp(-0.004), `${M}0,4 p.p.`);

assert.equal(fmt.votes(1), "1 voto");
assert.equal(fmt.votes(2899), "2.899 votos");
assert.equal(fmt.signedVotes(-1), `${M}1 voto`);
assert.equal(fmt.signedVotes(604), "+604 votos");

assert.equal(fmt.range(120, 410), "120 a 410");
assert.equal(fmt.range(5, 5), "5");
assert.equal(fmt.range(null, 4), "–");

assert.equal(fmt.per100(5, 250), 2);
assert.equal(fmt.per100(5, 0), null, "denominador zero não vira número");
assert.equal(fmt.per100(null, 100), null);

assert.equal(fmt.date("2026-10-04"), "4 de outubro de 2026");
assert.equal(fmt.date("2026-10-25"), "25 de outubro de 2026");
assert.equal(fmt.date(null), "–");
assert.match(fmt.datetime("2026-10-27T18:00:00Z"), /^27\/10\/2026,? 15:00 \(horário de Brasília\)$/);

assert.equal(fmt.bytes(512), "512 B");
assert.equal(fmt.bytes(2048), "2,0 KB");

console.log("format.check: ok");
