// Checks de web/js/catalog.js contra o catálogo da fixture DEMO-001.
// Rodar da raiz:  node tests/web/catalog.check.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { buildIndex, search, normalize, findByCode, label, homonyms } from "../../web/js/catalog.js";

const catalog = JSON.parse(readFileSync(new URL("../fixtures/bundle/releases/DEMO-001/catalogo.json", import.meta.url), "utf8"));
const index = buildIndex(catalog);
const codes = (rs) => rs.map((m) => m.municipio_tse);

assert.equal(normalize("Porto das Águas"), "porto das aguas");
assert.equal(normalize("  SÃO   JOÃO D'ALIANÇA "), "sao joao d alianca");

// acento e caixa não importam
assert.deepEqual(codes(search(index, "porto das águas")), ["00003"]);
assert.deepEqual(codes(search(index, "PORTO DAS AGUAS")), ["00003"]);
assert.deepEqual(codes(search(index, "aguas")), ["00003"], "início de palavra no meio do nome");

// homônimos: os dois aparecem, ordenados por UF, e a UF desambigua
const vs = search(index, "vale sereno");
assert.deepEqual(codes(vs), ["00002", "00001"], "GO antes de MG");
assert.deepEqual(vs.map(label), ["Vale Sereno — GO", "Vale Sereno — MG"]);
assert.deepEqual(codes(search(index, "vale sereno mg")), ["00001"]);
assert.deepEqual(codes(search(index, "vale sereno - GO")), ["00002"]);
assert.equal(homonyms(index, findByCode(index, "00001")).length, 1);

// prefixo vem antes de "contém"
assert.equal(search(index, "cid")[0].municipio_tse, "00000");

// código TSE
assert.deepEqual(codes(search(index, "00003")), ["00003"]);
assert.deepEqual(codes(search(index, "0000")), ["00000", "00001", "00002", "00003"], "por código, em ordem de código");

// sigla de UF sozinha lista os municípios da UF primeiro
assert.deepEqual(codes(search(index, "go")).slice(0, 2).sort(), ["00000", "00002"]);

// consultas curtas ou vazias não listam nada
assert.deepEqual(search(index, ""), []);
assert.deepEqual(search(index, "c"), []);
assert.deepEqual(search(index, "zzzz"), []);

assert.equal(findByCode(index, "99999"), null);
assert.equal(findByCode(index, "00000").display_name, "Cidade Modelo");

console.log("catalog.check: ok");
