# Caderno Eleitoral — Método analítico

**Versão do método:** `metodo-1.0.0` (rascunho, parâmetros a calibrar) · **Data:** 27 de outubro de 2026
**Papel:** fonte de verdade para **como** os números são verificados, limitados e estimados.
Schema dos arquivos: `03-contratos-de-dados.md`. Telas: `02-especificacao-funcional-tecnica.md`.
Este documento responde aos achados críticos C1–C4 (e ao A1) de `analise-critica-metodologia.md`.

---

## 0. Escopo

- **Eleição:** Presidente da República, 2026. 1º turno em 4 de outubro e 2º turno em 25 de outubro
  de 2026.
- **Unidade de análise publicada:** município. A eleição presidencial teve 2º turno em todos os
  municípios. **A primeira versão publicada cobre só o Estado de São Paulo (645 municípios)**
  (`incluir_ufs` em `config/eleicoes/2026-presidente.yml`); a calibração usa margens de SP.
- **Fora do escopo:** outros cargos e outras eleições; votos no exterior (UF `ZZ`), que não
  pertencem a município.
- **Nenhuma outra eleição** é usada, nem para desenvolvimento ou calibração. A calibração
  (§3.4 e §5.6) usa só dados de 2026 que não envolvem o resultado do 2º turno: aptos por seção e
  margens do 1º turno. Enquanto o TSE não publicar o 2º turno por seção, o desenvolvimento começa
  pelos arquivos do 1º turno.
- O motor continua genérico (eleição definida por configuração), mas a especificação, os testes de
  aceite e os textos da interface tratam só do caso acima.

**Pergunta do produto:** como mudou o comportamento do eleitorado de cada município entre o 1º e o
2º turno, separando o que se observa, o que as margens permitem e o que um modelo estima sob
hipóteses declaradas.

---

## 1. Unidades e categorias

**Unidade de comparação:** a seção eleitoral pareada entre os dois turnos. Quando a agregação de
seções difere entre turnos, a unidade é o conjunto agregado (§2.2). Cada unidade tem aptos `E₁` e
`E₂` (1º e 2º turno).

**Categorias da matriz de transição:**

| Origem (1º turno) | Destino (2º turno) |
|---|---|
| `A` — finalista A | `A` — finalista A |
| `B` — finalista B | `B` — finalista B |
| `O` — demais candidatos | — |
| `I` — brancos + nulos | `I` — brancos + nulos |
| `X` — abstenção (`E₁` − comparecimento) | `X` — abstenção (`E₂` − comparecimento) |
| `N` — entrada líquida, só quando `E₂ > E₁` | `S` — saída líquida, só quando `E₁ > E₂` |

`N` e `S` são pseudo-categorias de população (§3). Com elas, as somas de linhas e colunas fecham:
`E₁ + max(0, E₂ − E₁) = E₂ + max(0, E₁ − E₂)`.

Votos com tratamento especial: no arquivo de detalhe de 2026 (gerado em 26/10/2026), presidente não
tem votos de legenda nem votos anulados apurados em separado, e nenhuma seção está anulada. As 41
seções não instaladas ficam fora (`not_installed`). Boletins recuperados (RED), urna de contingência e
sistema de apuração são contagens normais da seção. Votos em candidato sem destinação válida na
totalização oficial (nulos técnicos; em 2026, 5.123 votos no número 28) entram em `I`, como faz o TSE.
Se uma nova versão do arquivo trouxer anulados apurados em separado, eles entram como verificação
pendente.

---

## 2. Verificações (resposta a C2)

A identidade ΔA + ΔB = O₁ + ΔC − ΔI é **aritmética dentro de cada turno**: decorre de
"comparecimento = soma dos votos" em cada turno. Ela aparece na interface como explicação, mas
**não é verificação** e não comprova nada sobre o pareamento entre turnos. As verificações são
três famílias independentes:

### 2.1 V1 — Integridade dentro de cada turno (por seção e turno)

| ID | Regra |
|---|---|
| V1.1 | comparecimento = votos nominais + brancos + nulos (+ categorias especiais, conforme §1) |
| V1.2 | aptos = comparecimento + abstenção |
| V1.3 | nenhuma contagem negativa; votos ≤ aptos |
| V1.4 | quando houver boletim de urna e arquivo de votação por seção, os dois coincidem |

Falha em V1: a seção fica com `integrity_status = failed` e sai de toda análise além da listagem
na aba Qualidade.

### 2.2 V2 — Harmonização entre turnos (por unidade pareada)

| ID | Regra | Falha |
|---|---|---|
| V2.1 | a chave (`municipio_tse`, `zona`, `secao`) existe nos dois turnos | `unmatched` |
| V2.2 | o conjunto de seções agregadas é o mesmo nos dois turnos; se não for, as seções são fundidas numa unidade de comparação | `aggregated` (não é falha) |
| V2.3 | pareamento 1:1 depois da fusão | erro de pipeline, bloqueia a release |
| V2.4 | o tipo de seção é o mesmo nos dois turnos (`regular`, `transit`, `special`) | fora da análise de transição |
| V2.5 | o local de votação é o mesmo | só sinaliza (`location_changed`); não exclui |
| V2.6 | classificação de população (§3) | conforme §3 |

Cada unidade fora da análise de transição recebe `exclusion_reason` com código, publicado na aba
Qualidade.

### 2.3 V3 — Totais oficiais (por município e turno)

A soma das seções de cada turno é igual ao total oficial do município para cada candidato, brancos,
nulos e comparecimento. Divergências só são aceitas com código de explicação registrado em
`qualidade.json` (achado M3); divergência sem explicação deixa o município com
`validation_status = failed` e só os dados observados por seção são publicados, com aviso.

---

## 3. População entre turnos (resposta a C3)

O cadastro eleitoral fecha antes da eleição, então não há eleitores novos entre turnos. Mas o voto
em trânsito é pedido **por turno** e pode ser para cidades diferentes em cada turno; ele só
funciona em capitais e em municípios com mais de 100 mil eleitores. Seções especiais (por exemplo,
em estabelecimentos prisionais) têm dinâmica própria. Por isso os aptos de uma seção podem mudar
entre turnos.

### 3.1 Tipos de seção

- `transit` e `special` ficam **fora da análise de transição** nos dois turnos. Entram nos totais
  observados e na cobertura.
- A identificação vem dos metadados de seção ou de local do TSE, ou da lista de seções de trânsito
  dos TREs. O teste exploratório com os arquivos de 2026 confirma qual fonte usar. Se o tipo não puder ser
  identificado num município com trânsito, a análise de transição desse município fica
  `insufficient_data`, com motivo.

### 3.2 Classes de população (unidades `regular` pareadas)

Com `D = E₂ − E₁` e tolerância `τ` (§6):

| Classe | Condição | Tratamento |
|---|---|---|
| `closed` | `D = 0` | matriz fechada, sem pseudo-categoria |
| `net_change` | `0 < \|D\| ≤ τ` | inclui `N` (se `D > 0`) ou `S` (se `D < 0`) com tamanho `\|D\|`, sob a hipótese `pop-liquida-minima` |
| `excluded_population` | `\|D\| > τ` | fora da análise de transição; continua nos dados observados |

**Hipótese `pop-liquida-minima`:** a rotatividade bruta é igual à líquida (ninguém sai e outro
entra na mesma seção). É uma hipótese declarada, publicada com `assumption_id`. A sensibilidade a
ela é medida na Fase 2: limites recalculados com rotatividade bruta de até `3·|D|`, informando quanto
os limites se alargam.

### 3.3 Cobertura

- `eligible_share_used` = aptos do 1º turno nas unidades da análise de transição ÷ aptos do 1º turno
  do município.
- Abaixo de `cobertura_minima` (§6), o município não recebe estimativa ecológica; os limites são
  publicados com o escopo explícito.

### 3.4 Calibração de `τ`

Antes de fixar `τ`, medir em 2026 a distribuição de `D` por seção, separando municípios com e sem
voto em trânsito. `D` depende só dos aptos, não dos votos, então medir e publicar na mesma eleição
não contamina a análise. A distribuição é publicada na página de metodologia.

Medição preliminar (arquivo de detalhe de 26/10/2026, 499.248 seções pareadas): 88,8% com `D = 0`,
10,6% com `|D| ≤ 2`, 0,5% com `|D|` entre 3 e 10 e 237 seções com `|D| > 10`.

---

## 4. Limites determinísticos

### 4.1 Sem restrições adicionais

Em cada unidade, com totais de origem `rᵢ`, de destino `cⱼ` e total `T`:

    max(0, rᵢ + cⱼ − T)  ≤  xᵢⱼ  ≤  min(rᵢ, cⱼ)

São os limites de Fréchet (Duncan-Davis), em fórmula fechada. Como as unidades são independentes,
**o limite municipal de cada fluxo é a soma dos limites das unidades**. Os limites de células
diferentes não são atingíveis ao mesmo tempo; por isso nunca alimentam um Sankey.

### 4.2 Cenários

Cenários adicionam restrições **por unidade**, por exemplo `sem-troca-finalistas`
(`x_AB = x_BA = 0`). Restrições por unidade mantêm o problema separável: um LP pequeno por unidade,
somado. Restrições que ligam unidades (mesma taxa em todas as seções) pertencem à estimação (§5),
não aos limites. Cada cenário tem `assumption_id` em `config/assumptions.yml` e status
`feasible` ou `infeasible`; o cenário é inviável no município se for inviável em qualquer unidade,
com a contagem de unidades inviáveis.

A fórmula fechada de §4.1 é o oráculo dos testes do solver.

---

## 5. Estimação ecológica (resposta a C1 e A1)

Nenhum diagnóstico interno prova que uma estimativa ecológica municipal está correta: não existe
verdade de campo. O método então afirma apenas que a estimativa é **compatível com os dados sob
hipóteses declaradas** e mede o quanto ela depende dessas hipóteses. Uma célula ou um município que
não passa vira "não identificado", não um número.

### 5.1 Dados e pooling

- Unidades: as da análise de transição (§2–3), do próprio município.
- **Sem pooling entre municípios** na estimativa municipal. A hipótese de trabalho é homogeneidade
  das taxas de transição entre as seções do município. Um contexto por UF, se existir, é outro
  produto, rotulado como tal.

### 5.2 Métodos (pelo menos dois de famílias diferentes)

| ID | Família | Saída |
|---|---|---|
| `dm-homog` | Bayesiano com taxas homogêneas no município e sobredispersão Dirichlet-multinomial | média posterior das contagens e intervalo de credibilidade de 95% |
| `lphom` | Programação linear sob homogeneidade (`lphom`) | matriz pontual |
| `ecolrxc` (desligado) | Estrutura latente de Thomsen (`ecolRxC`) | matriz pontual; custo de ~0,7 s por unidade, fora do orçamento |

**Modelo `dm-homog`.** Uma matriz de taxas `P` (uma linha por origem) vale para todas as unidades do
município. As margens de destino de cada unidade seguem uma Dirichlet-multinomial com média
(composição de origem da unidade) × `P` e sobredispersão `φ`, limitada a [0,5; 10⁵]. Prior
Dirichlet(2) em cada linha de `P` (cerca de 2 pseudo-votos por célula) e log `φ` ~ Normal(log 50, 3).
`N → S` é zero estrutural.

**Contagens publicadas.** Para cada amostra de `P`, a tabela interna de cada unidade é obtida por
ajuste proporcional iterativo (IPF) às duas margens da unidade, a partir da semente
`o_ir × P[r, c]`; a contagem municipal é a soma dessas tabelas. Assim, cada amostra fecha as margens de
origem e de destino do município e fica dentro dos limites de Fréchet (§4.1) por construção. A
**estimativa publicada** é a média posterior dessas contagens. A mediana posterior nunca forma
matriz pontual (achado A1) e só aparece como coluna de uma célula. Os outros métodos formam a
**faixa entre métodos** de cada célula.

O `md-bayes` hierárquico de Rosen et al. (`eiPack::ei.MD.bayes`), previsto na versão anterior deste
documento, não convergiu nos dados de 2026 (R-hat entre 1,05 e 4,1 em todos os municípios testados,
inclusive com cadeias 5× mais longas) e foi substituído; o estudo está em `tests/benchmark/RESULTS.md`.

### 5.3 Validade computacional

- `dm-homog`: máximo a posteriori por L-BFGS-B a partir de 3 inícios; piloto de passeio aleatório
  que estima a covariância da proposta; pelo menos 4 cadeias iniciadas em torno do máximo e estendidas
  por rodadas até atingir os limiares ou o orçamento por município. R-hat ≤ `rhat_max` e ESS ≥
  `ess_min` nas contagens municipais de todas as células **não determinadas** (§5.4): nas células
  determinadas a interface mostra o próprio limite e a estimativa não pesa em nenhuma decisão.
- **Escala.** Acima de `max_unidades_ajuste` unidades (400), a verossimilhança é avaliada em grupos de
  unidades de composição parecida: as unidades são ordenadas pela participação do finalista A no 1º
  turno (arredondada a 1 ponto percentual) e depois pela de abstenção, e somadas em blocos
  consecutivos de tamanho igual. Sob a hipótese de homogeneidade, somar unidades preserva `P`; a
  perda é de informação, não de validade. As contagens publicadas continuam calculadas nas unidades
  originais (IPF). O `lphom` usa a mesma regra acima de 800 unidades.
- `lphom` e `ecolrxc`: solução ótima ou convergida, reportada.
- Custo previsto acima do orçamento por município: `failed`, com motivo.

Falha computacional: `model_status = failed`.

### 5.4 Grau de identificação por célula

Para cada célula `i → j` do município:

- `W` = largura do limite determinístico municipal (§4.1, sem cenários);
- `P` = largura do intervalo de credibilidade de 95% do `dm-homog`;
- `F` = faixa entre os métodos (maior estimativa pontual menos a menor);
- `R = max(P, F) ÷ W`.

O intervalo publicado é cortado nos limites determinísticos da célula. Com as contagens por IPF ele já
fica dentro deles; o corte só garante a regra para qualquer motor.

| Classe | Condição | O que a interface mostra |
|---|---|---|
| `determined` | `W ≤ largura_determinada` | o próprio limite: as margens bastam |
| `estimated` | `R ≤ r_estimado` | estimativa + intervalo + faixa entre métodos |
| `weak` | `r_estimado < R ≤ r_fraco` | limites e faixa entre métodos; estimativa só na tabela, sinalizada |
| `not_identified` | `R > r_fraco` | apenas limites; "os dados não distinguem os fluxos possíveis" |

### 5.5 Checagem preditiva

Para municípios com pelo menos `n_secoes_min` unidades: validação cruzada em `k_folds` grupos de
unidades. Ajustar as taxas sem um grupo e prever a distribuição do 2º turno de cada unidade
deixada de fora a partir da sua composição no 1º turno. O erro é o índice de dissimilaridade
ponderado por aptos (`Σⱼ |previsto − observado| ÷ 2E`). O **modelo nulo** prevê para toda unidade a
distribuição municipal do 2º turno. A checagem passa se `erro_modelo ≤ ganho_preditivo_min ×
erro_nulo`.

O ajuste dentro da validação cruzada usa o `lphom`, que é rápido: a checagem testa a hipótese de
homogeneidade, não um estimador específico.

A checagem testa se a hipótese de homogeneidade explica a variação entre seções. Não testa os
fluxos cruzados diretamente, por isso existe a calibração de §5.6.

### 5.6 Calibração por simulação (global, offline)

Antes da primeira publicação de estimativas, uma simulação calibra os limiares da §6:

1. Usar as margens reais do 1º turno de 2026 dos municípios, estratificados por número de seções.
   O resultado real do 2º turno não entra na calibração.
2. Gerar o 2º turno com matrizes conhecidas sob quatro processos:
   - G1, taxas homogêneas;
   - G2, taxas que variam com a composição da seção;
   - G3, taxas que variam por zona ou local;
   - G4, G2 mais mudança líquida de aptos.
3. Rodar o pipeline completo e medir, por classe de identificação e estrato, a cobertura dos
   intervalos e o erro absoluto.
4. Fixar `r_estimado` como o maior limiar da grade com **cobertura empírica ≥ 90% nos processos
   G2–G4** nas células com `R` até ele (e pelo menos 30 células); `r_fraco` como o maior limiar, a
   partir de `r_estimado`, com cobertura ≥ 75% no mesmo conjunto; `n_secoes_min` como o menor limite
   de estrato a partir do qual todos os estratos atingem 90%. `ganho_preditivo_min` não é recalibrado
   nesta versão: o relatório mostra a taxa de aprovação da checagem preditiva por processo.

A amostra da calibração vem dos municípios publicados na release (na primeira versão, os de São
Paulo), estratificados por número de unidades e limitados a 499 unidades por custo.

Se nenhum conjunto de limiares atingir a meta, o produto publica **apenas limites**, e isso é
comunicado como resultado metodológico. O relatório de calibração tem `calibration_id`, é
versionado com `method_version` e aparece na página de metodologia.

### 5.7 Regras de publicação por município

| `features.ecological_model` | Condição | Publica |
|---|---|---|
| `ready` | §5.3 ok; `eligible_share_used ≥ cobertura_minima`; unidades ≥ `n_secoes_min`; §5.5 passa; ≥ `massa_identificada_min` da **massa de mudança** em células `determined` ou `estimated` | tabela completa com classes **e Sankey** |
| `partial` | §5.3 ok, mas falha algum dos demais critérios de `ready` | tabela com classes; sem Sankey |
| `insufficient_data` | unidades < `n_secoes_min`, cobertura insuficiente ou tipo de seção não identificável | só limites |
| `failed` | falha computacional | só limites, com o motivo |

**Massa de mudança:** a soma das estimativas fora da retenção (todas as células, exceto `A→A`,
`B→B`, `I→I` e `X→X`).

No Sankey, só entram células `determined` e `estimated`; o restante aparece agregado como "não
identificado", com a largura proporcional à massa estimada e marcação visual distinta.

---

## 6. Parâmetros iniciais

Ficam em `config/metodo.yml`, versionados com `method_version`. Os valores abaixo são o ponto de
partida e os marcados com "simulação" são substituídos pelos da calibração (§5.6).

| Parâmetro | Valor inicial | Origem do valor final |
|---|---|---|
| `tau_populacao` | `max(2, 1% de E₁)` | distribuição de `D` em 2026 (§3.4) |
| `cobertura_minima` | 0,90 dos aptos do 1º turno | fixo |
| `n_secoes_min` | 15 | simulação |
| `rhat_max` | 1,01 | fixo |
| `ess_min` | 400 | fixo |
| `largura_determinada` | `max(5 votos, 1% da linha)` | fixo |
| `r_estimado` | 0,25 | simulação |
| `r_fraco` | 0,50 | simulação |
| `k_folds` | 5 | fixo |
| `ganho_preditivo_min` | 0,90 | simulação |
| `massa_identificada_min` | 0,80 | fixo |

---

## 7. Como o produto fala

| Situação | Texto |
|---|---|
| Identidade contábil | "A conta fecha por aritmética: outros votos no 1º turno + variação de comparecimento + redução de brancos e nulos = ganho dos finalistas. Isso não mostra quem mudou de voto." |
| Limite | "Sob as margens observadas, entre X e Y eleitores podem ter ido de O para A." |
| Célula `estimated` | "Supondo que as taxas de mudança sejam iguais em todas as seções do município, o modelo estima Z (intervalo de 95%: X a Y). Outros métodos dão entre U e V." |
| Célula `not_identified` | "Os dados deste município não distinguem os fluxos possíveis nesta célula." |
| `insufficient_data` | "Este município tem poucas seções comparáveis para estimar fluxos; mostramos só o que as margens permitem." |
| Unidades excluídas | "N seções ficaram fora da análise de transição (voto em trânsito, seções especiais ou mudança de eleitorado acima de τ). Elas continuam nos totais." |

---

## 8. Estado dos achados críticos

| Achado | Resposta | Seção |
|---|---|---|
| C1 — critério de qualidade mede só o cálculo | dois ou mais métodos, grau de identificação por célula, checagem preditiva, calibração por simulação, regras de publicação | §5 |
| C2 — identidade usada como verificação entre turnos | identidade só como explicação; verificações V1, V2, V3 | §2 |
| C3 — população não fechada | tipos de seção, classes de população, pseudo-categorias, cobertura, calibração de `τ` | §1, §3 |
| C4 — "qualquer município" | escopo restrito a presidente 2026, com 2º turno em todos os municípios | §0 |
| A1 — mediana posterior | só média posterior forma matriz | §5.2 |

Pendências que dependem do teste exploratório com os arquivos de 2026: fonte do tipo de seção (§3.1), categorias
especiais de voto (§1), códigos de divergência explicada (§2.3) e distribuição de `D` (§3.4).
