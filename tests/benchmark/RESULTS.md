# Benchmark do método (05 §4–§5) — resultados

Data: 28/10/2026. Máquina: 8 núcleos, 16 GB. Dados: `data/gold/2026-presidente/units.parquet`
(495.844 unidades, 5.571 municípios). Scripts: `tests/benchmark/benchmark.R` (etapas `bounds`, `md`,
`pilot`, `ecolrxc`, `calib`, `dm`); números brutos em `tests/benchmark/results/*.csv`.

## Resumo

| Parte | Resultado | Custo nacional (1 núcleo) |
|---|---|---|
| Limites `base` (Fréchet, fórmula fechada) | ok | 11,5 s |
| Limites `sem-troca-finalistas` (Gale–Hall exato, vetorizado) | ok; 10 municípios com 1 unidade inviável → cenário `infeasible` | 113 s (LP por unidade com lpSolve: ~4 h) |
| `lphom` + validação cruzada (k = 5) | ok; acima de 800 unidades agrupa unidades de composição parecida (o LP denso estourava 16 GB no RJ) | ~1,8 h (≈ 13 min com 8 workers) |
| `md-bayes` (`eiPack::ei.MD.bayes`, config de produção) | **0 de 10 municípios convergem** (R-hat ≤ 1,01 e ESS ≥ 400) | ~67–94 h (≈ 8–12 h com 8 workers); SP previsto 3,5 h |
| `ecolRxC` | ok, mas ~0,7 s por unidade | ~94 h → desligado (`usar_ecolrxc: false`) |
| Calibração (05 §5.6) | **reprovada**: md-bayes convergiu em 0 de 12 ajustes simulados (inclusive G1 homogêneo) | reduzida: 254 s; completa (config atual): ~1 h |

Consequência no pipeline: com a calibração reprovada, `ec_calibrate()` devolve
`calibration_status = "failed"`, o runner copia isso para `params$estimacao` e `ec_estimate()` devolve
`unavailable` sem rodar MCMC ("só os limites são publicados", 05 §5.6). A release sai com limites e
cenários para todos os municípios e sem estimativas.

## md-bayes (eiPack) — convergência por porte

Configuração de produção (`config/metodo.yml`): `tuneMD` (5 × 2.000), 4 cadeias, burn-in 10.000,
1.000 amostras com thin 10, prior `lambda1 = 4`, `lambda2 = 2`; N e S fundidas com X quando < 1% do
total; R-hat e ESS calculados sobre as contagens municipais (`Cell.counts`).

| Município | UF | Unidades | R-hat máx. | ESS mín. | Célula pior | Tempo |
|---|---|---:|---:|---:|---|---:|
| 12580 | PI | 21 | 1,156 | 98 | A>B | 7 s |
| 90875 | MS | 23 | 1,093 | 25 | I>A | 8 s |
| 13714 | CE | 35 | 1,467 | 63 | A>X | 11 s |
| 34517 | BA | 52 | 1,430 | 51 | X>X | 16 s |
| 56154 | ES | 90 | 1,610 | 36 | I>A | 24 s |
| 04570 | PA | 124 | 1,410 | 34 | X>B | 34 s |
| 56979 | ES | 294 | 2,446 | 17 | O>I | 74 s |
| 77453 | PR | 321 | 3,592 | 10 | O>A | 85 s |
| 58777 | RJ | 800 | 2,761 | 7 | I>A | 214 s |
| 81051 | SC | 1.188 | 4,123 | 6 | I>A | 350 s |

Variantes testadas (amostra de 15 a 149 unidades):

| Variante | R-hat máx. (faixa) | ESS mín. (faixa) | Convergem |
|---|---|---|---|
| Produção (burn-in 10.000, thin 10) | 1,09–1,61 | 25–98 | 0/6 |
| Cadeias 5× mais longas (burn-in 50.000, thin 50), prior padrão | 1,05–1,39 | 92–259 | 0/6 |
| Cadeias 5× mais longas, prior difuso (`lambda1 = 1`, `lambda2 = 0,5`) | 1,14–2,22 | 45–102 | 0/6 |
| Priors concentrados (`lambda1 = 10–20`) em dados sintéticos | 3,6–16 | 6–10 | 0 |

O R-hat cai devagar com o comprimento das cadeias e piora com o porte: com 5× mais iterações ainda
fica acima de 1,01, e o custo nacional passaria de 40 h com 8 workers (SP estouraria o orçamento de 4 h).
Fundir N e S com X não mudou o quadro; as células piores são as grandes (A>A, X>X, I>A, X>B), não as
categorias quase vazias.

Outras observações do eiPack:
- `Cell.counts` fecha as margens de origem em cada amostra; as de destino não fecham exatamente
  (desvios de ~5–20 votos em 40 unidades sintéticas).
- Por ser contagem esperada, a média pode cair fora dos limites de Fréchet; `ec_estimate()` marca o
  município como `failed` se isso passar da tolerância (1 voto ou 0,5% da linha) e corta os extremos
  do intervalo nos limites.

## Calibração reduzida (com a configuração de produção)

3 municípios (23, 36 e 119 unidades) × G1–G4 = 12 ajustes; 254 s. R-hat entre 1,20 e 2,01; nenhum
ajuste convergiu, logo não há células `estimated` para medir cobertura e a decisão é
"publicar só limites". Custo da calibração completa (4 estratos × 3 municípios × 4 processos, até 499
unidades): ~1 h.

## Proposta (não implementada no método): substituir o motor do md-bayes

Experimento em `tests/benchmark/experimento_dm.R` (não é carregado pelo pipeline):
- taxas homogêneas no município com verossimilhança Dirichlet-multinomial nas margens de destino de
  cada unidade (sobredispersão `phi` limitada a 1e5 para estabilidade numérica), prior Dirichlet(2)
  nas linhas;
- MAP por L-BFGS-B (posterior unimodal: 6 inícios distintos chegam ao mesmo ótimo), piloto de passeio
  aleatório para a covariância da proposta e 4 cadeias de passeio aleatório estendidas até R-hat/ESS;
- contagens municipais por ajuste proporcional iterativo (IPF) das tabelas de cada unidade às duas
  margens, por amostra: fecham origem e destino e ficam dentro dos limites por construção.

| Município | Unidades | R-hat máx. | ESS mín. | Iterações/cadeia | Tempo |
|---|---:|---:|---:|---:|---:|
| 34517 (BA) | 52 | 1,006 | 662 | 75.000 | 51 s |
| 04570 (PA) | 124 | 1,011 | 551 | 100.000 | 89 s |

Custo por avaliação ~1,3 µs por unidade; com 100–400 mil avaliações por município, o custo nacional
fica na mesma ordem do eiPack (~8–12 h com 8 workers), mas convergindo. Para os maiores municípios
(SP, RJ) seria preciso HMC (por exemplo Stan/`cmdstanr`) ou cadeias em paralelo. Adotar exige mudar
05 §5.2 (definição do md-bayes), o enum `model_id`/`method_id` do contrato e recalibrar.
