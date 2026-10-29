// Checks de web/js/evidence.js e web/js/stats.js. Rodar da raiz:  node tests/web/evidence.check.mjs
import assert from "node:assert/strict";
import * as ev from "../../web/js/evidence.js";
import { pearson, fisherInterval, correlationSummary } from "../../web/js/stats.js";

const M = "−";

// ---- Sankey só com ecological_model = ready
assert.equal(ev.canShowSankey({ features: { ecological_model: "ready" } }), true);
for (const s of ["partial", "insufficient_data", "failed", "unavailable"]) {
  assert.equal(ev.canShowSankey({ features: { ecological_model: s } }), false, s);
}
assert.equal(ev.canShowSankey(null), false);

// ---- células: a classe decide o que aparece
const bound = { origin: "O", destination: "A", min_votes: 120, max_votes: 410, status: "feasible" };
const flow = (cls) => ({
  origin: "O", destination: "A", estimate_votes: 250.4, interval_low: 230, interval_high: 270,
  method_range_low: 240, method_range_high: 262, bounds_min: 120, bounds_max: 410, identification_class: cls,
});

let v = ev.cellView(bound, null);
assert.equal(v.cls, "bound");
assert.equal(v.main, "120 a 410");
assert.equal(v.evidence, "conditional_bound", "sem modelo, só limite");

v = ev.cellView(bound, flow("estimated"));
assert.equal(v.cls, "estimated");
assert.equal(v.main, "250");
assert.equal(v.evidence, "model_estimate");
assert.match(v.sub, /intervalo de 95%: 230 a 270/);
assert.match(v.sub, /métodos: 240 a 262/);
assert.match(v.sub, /limite: 120 a 410/, "estimativa nunca aparece sem o limite ao lado");

v = ev.cellView(bound, flow("weak"));
assert.equal(v.main, "120 a 410", "célula fraca mostra o limite como valor principal");
assert.equal(v.evidence, "conditional_bound");
assert.match(v.sub, /estimativa fraca: 250/);

v = ev.cellView(bound, flow("not_identified"));
assert.equal(v.main, "120 a 410");
assert.doesNotMatch(v.sub, /250/, "não identificada não mostra número central");

v = ev.cellView(bound, flow("determined"));
assert.equal(v.cls, "determined");

v = ev.cellView({ ...bound, status: "infeasible" }, null);
assert.equal(v.cls, "unavailable");
assert.equal(v.main, "–", "cenário inviável não vira zero");
assert.equal(ev.cellView(null, null).main, "–");

// ---- dados do Sankey: só determined/estimated; o resto vai para "Não identificado"
const labels = ev.categoryLabels(null, [{ slot: "A", number: "13", name: "X" }, { slot: "B", number: "22", name: "Y" }]);
assert.equal(labels[1].A, "Finalista A (13)");
assert.equal(labels[2].B, "Finalista B (22)");
const flows = [
  { origin: "A", destination: "A", estimate_votes: 100, identification_class: "determined" },
  { origin: "O", destination: "A", estimate_votes: 30, identification_class: "estimated" },
  { origin: "O", destination: "B", estimate_votes: 20, identification_class: "weak" },
  { origin: "X", destination: "A", estimate_votes: 10, identification_class: "not_identified" },
  { origin: "X", destination: "X", estimate_votes: 0, identification_class: "estimated" },
];
const sk = ev.sankeyData(flows, labels);
const unknown = sk.links.filter((l) => l.target === "2:?");
assert.equal(unknown.length, 2);
assert.deepEqual(unknown.map((l) => [l.origin, l.value]).sort(), [["O", 20], ["X", 10]]);
assert.ok(!sk.links.some((l) => l.kind === "weak"), "células fracas nunca viram fluxo próprio");
assert.ok(sk.nodes.some((n) => n.id === "2:?"));
assert.ok(!sk.links.some((l) => l.value <= 0), "fluxo zero não é desenhado");

// massa de mudança identificada: fora da retenção (A>A, X>X)
assert.equal(ev.identifiedChangeShare(flows), 30 / 60);
assert.equal(ev.identifiedChangeShare([]), null);

// ---- mensagens
assert.match(ev.modelMessage("insufficient_data"), /poucas seções/);
assert.match(ev.modelMessage("failed"), /nunca um número não validado/);
assert.equal(ev.validationMessage("passed"), null);
assert.ok(ev.validationMessage("failed"));
assert.equal(ev.isUsable("partial"), true);
assert.equal(ev.isUsable("insufficient_data"), false);
assert.equal(ev.titleCase("PORTO DAS ÁGUAS"), "Porto das Águas");
assert.equal(ev.finalistTag({ slot: "B", number: "22" }), "Finalista B (22)");

// ---- estatística das seções
assert.ok(Math.abs(pearson([1, 2, 3, 4], [2, 4, 6, 8]) - 1) < 1e-12);
assert.ok(Math.abs(pearson([1, 2, 3, 4], [8, 6, 4, 2]) + 1) < 1e-12);
assert.equal(pearson([1, 1, 1], [1, 2, 3]), null, "sem variação, sem coeficiente");
const iv = fisherInterval(0.5, 40);
assert.ok(iv[0] < 0.5 && iv[1] > 0.5 && iv[0] > 0.2 && iv[1] < 0.75);
const few = correlationSummary(Array.from({ length: 10 }, (_, i) => ({ x: i, y: i })), 15);
assert.equal(few.r, null);
assert.equal(few.reason, "few_sections");
const many = correlationSummary(Array.from({ length: 20 }, (_, i) => ({ x: i, y: i % 3 })), 15);
assert.equal(many.n, 20);
assert.ok(many.r != null && many.interval.length === 2);
assert.equal(correlationSummary([{ x: NaN, y: 1 }, ...Array.from({ length: 15 }, (_, i) => ({ x: i, y: -i }))], 15).n, 15, "pontos inválidos são descartados");
void M;

console.log("evidence.check: ok");
