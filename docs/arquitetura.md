# Arquitetura intencional — Caderno Eleitoral

> **Status:** proposta v0.2 · 2026-10-27
> **Base:** [`visao_inicial.md`](visao_inicial.md) (origem e metodologia) + a arquitetura
> já em produção no projeto DudesApp (`docs/app_arch.md`, `docs/app_web_data_contract.md`,
> `R/web/`, `web/`), adaptada para escala nacional.
> **Papel:** fonte de verdade para stack, camadas e módulos. Schema publicado:
> [`03-contratos-de-dados.md`](03-contratos-de-dados.md). Funcionalidade e telas:
> [`02-especificacao-funcional-tecnica.md`](02-especificacao-funcional-tecnica.md). Fases:
> [`04-roteiro-implementacao-claude-code.md`](04-roteiro-implementacao-claude-code.md). Método analítico:
> [`05-metodo-analitico.md`](05-metodo-analitico.md).

Este documento descreve a arquitetura **que queremos ter**, não a que existe hoje (o repositório
ainda não tem código). Ele fixa as fronteiras entre camadas, as invariantes que todo código deve
respeitar e as decisões já tomadas, com o motivo de cada uma e o sinal que justificaria revê-la.
Código novo deve convergir para o que está aqui; uma divergência intencional entra primeiro como
alteração deste documento, na seção [Registro de decisões](#12-registro-de-decisões).

---

## 1. Objetivo

Publicar, para cada município brasileiro, uma análise reproduzível da dinâmica de votos entre os
dois turnos de uma eleição, separando de forma explícita:

1. **o que foi observado** — contabilidade exata por seção, reconciliada com os totais oficiais;
2. **o que é matematicamente possível** — limites dos fluxos dadas as margens;
3. **o que é estimado** — inferência ecológica com incerteza, hipóteses e diagnósticos.

Restrição de infraestrutura: **site estático**. Não há banco de dados, API, servidor R ou Node em
produção. Toda computação científica roda em lote, em R, e o resultado é publicado como um produto de
dados versionado que o navegador consulta com DuckDB-Wasm.

---

## 2. Princípios e invariantes

### 2.1 Princípios

1. **R é o único motor analítico.** Ingestão, harmonização, reconciliação, limites, modelos,
   cenários e diagnósticos rodam em R. O navegador não recalcula nada que tenha significado
   estatístico.
2. **Batch-first, publicação imutável.** Cada publicação (`release`) é um conjunto fechado de
   arquivos gerado por um único build. Uma release publicada nunca é alterada; correções geram
   outra release.
3. **O bundle web representa conceitos da interface, não o modelo interno.** O frontend nunca refaz
   joins entre tabelas canônicas; recebe *presentation marts* já no formato das telas (herdado do
   DudesApp).
4. **A classe do resultado faz parte do dado.** Todo número publicado carrega `evidence_type ∈
   {observed, conditional_bound, model_estimate}` (03, §10), e a interface renderiza cada classe de
   um jeito diferente. Não existe um "número" sem classe; falta de dado é `unavailable`, nunca zero.
5. **Incompleto é um estado, não um erro silencioso.** Município sem dados completos, sem
   reconciliação ou com baixa identificabilidade aparece com `status` explícito e **sem estimativa
   fabricada**.
6. **Proveniência ponta a ponta.** Qualquer número na tela leva até a release, o modelo, as
   hipóteses e os arquivos do TSE (URL + hash) que o produziram.
7. **O motor é genérico; a eleição é configuração.** Nada no código conhece "Lula", "Flávio",
   "2026" ou "presidente". Candidatos são mapeados para categorias (`finalist_a`, `finalist_b`,
   `other`, `invalid`, `abstention`) por arquivo de configuração. O escopo do produto é a eleição
   presidencial de 2026 (1º × 2º turno); 2022 é base interna de desenvolvimento e calibração.
8. **Infraestrutura mínima.** `git clone` + dados de entrada + build = aplicação completa.

Em uma frase (adaptada do DudesApp):

> **R calcula; Parquet transporta; DuckDB-Wasm seleciona; JavaScript apresenta.**

### 2.2 Invariantes verificáveis

São regras de revisão: um PR que viole uma delas está errado, mesmo que funcione.

| # | Invariante | Onde é verificada |
|---|------------|-------------------|
| I1 | Todo arquivo do TSE usado tem URL, `sha256`, tamanho e data de coleta registrados em `source_files` | teste da camada Bronze |
| I2 | Toda seção, em cada turno, satisfaz comparecimento = soma dos votos e aptos = comparecimento + abstenção (V1). A identidade ΔA + ΔB = O₁ + ΔC − ΔI é consequência disso e não verifica o pareamento entre turnos | `reconcile/`, gate de integridade |
| I3 | Somas por município e UF batem com os totais oficiais do TSE | `reconcile/` |
| I4 | Todo valor numérico publicado tem `evidence_type`; `conditional_bound` sempre traz `assumption_id` e status de viabilidade; `model_estimate` sempre traz `model_id`, `model_version`, `assumption_id` e intervalo com tipo | `validate_web_bundle()` |
| I5 | Município com `validation_status != "passed"` não publica `model_estimate` | `validate_web_bundle()` |
| I6 | Todos os marts de uma release vêm do mesmo `release_id`, da mesma versão Silver e da mesma `model_version` | `validate_web_bundle()` |
| I7 | Identificadores são `string` no bundle; não há list-columns; `NA` vira `NULL` no Parquet | `write_mart()` |
| I8 | O frontend só conhece caminhos de dados via `latest.json` → catálogo → manifesto; nenhum caminho fixo no JS | revisão + teste de fumaça |
| I9 | Nenhuma entrada do usuário chega a SQL ou a um caminho sem antes ser validada contra o catálogo | `web/js/data.js` |
| I10 | Draws de MCMC/bootstrap não são publicados; publicam-se quantis, intervalos e histogramas agregados | contrato de dados |
| I11 | Só entram em limites e estimação unidades pareadas 1:1, do tipo `regular`, com `population_status` `closed` ou `net_change` (V2; `05-metodo-analitico.md` §2–3) | `validate_web_bundle()` |

---

## 3. Visão geral

São dois planos separados: o **plano de computação** (máquina local ou CI, em R) e o **plano de
publicação** (arquivos estáticos em CDN).

```text
┌──────────────────────────────────────────────────────────────────────────┐
│ PLANO DE COMPUTAÇÃO — R  (targets + renv, roda em lote)                  │
│                                                                          │
│  TSE dados abertos ─► BRONZE ─────► SILVER ─────────► GOLD               │
│  resultados/seção     arquivos       modelo canônico   resultados        │
│  boletins de urna     originais,     harmonizado,      analíticos        │
│  eleitorado/locais    hashes,        Parquet por UF,   completos:        │
│  logs de urna         proveniência   chaves validadas  reconciliação,    │
│                                                        limites, modelos, │
│                                                        cenários,         │
│                                                        diagnósticos      │
│                                                             │            │
│                                        R/web: build_web_bundle()         │
│                                        presentation marts + manifest     │
│                                        validate_web_bundle()  (gate)     │
└─────────────────────────────────────────────────────────────┬────────────┘
                                                              │ publish
┌─────────────────────────────────────────────────────────────▼────────────┐
│ PLANO DE PUBLICAÇÃO — estático                                           │
│                                                                          │
│  APP (Quarto _site/)                  DADOS (object storage + CDN)       │
│  HTML · CSS · ES modules              latest.json        (no-cache)      │
│  Plotly · DuckDB-Wasm                 releases/<release_id>/  (imutável) │
│        │                                catalogo.json                    │
│        │  fetch JSON ─────────────────► manifest · resumo · qualidade    │
│        │  HTTP Range + CORS ──────────► Parquet de detalhe               │
│        ▼                                                                 │
│  navegador: busca → município → abas (Resumo · Seções · Transferências · │
│             Cenários · Qualidade) · metodologia · sobre                  │
└──────────────────────────────────────────────────────────────────────────┘
```

O que **não** existe em produção: banco transacional, API REST, servidor R/Shiny, servidor Node,
cache server, autenticação.

---

## 4. Camadas

### 4.1 Bronze — ingestão

**Responsabilidade:** obter os arquivos do TSE exatamente como foram publicados e registrar a
proveniência deles. Nenhuma transformação de conteúdo.

- **Adaptadores por tipo de fonte**, com interface comum `descobrir_fontes(config) →
  baixar_verificar(fonte) → arquivo`:
  - download em lote por UF/turno (resultados por seção, BUs, eleitorado, locais, logs);
  - coleta individual de BUs quando o lote ainda não foi publicado (caso do 2º turno de 2026
    citado na visão).
- **`source_files`** (tabela de proveniência): `file_id`, `election_id`, `uf`, `turno`, `kind`,
  `url`, `sha256`, `bytes`, `downloaded_at`, `tse_published_at` (quando houver), `adapter`.
- Downloads são **idempotentes**: um arquivo com o mesmo hash não é baixado de novo; um hash
  diferente para a mesma URL é registrado como nova versão, nunca sobrescrito em silêncio.
- Layout: `data/bronze/<election_id>/<kind>/uf=<UF>/turno=<n>/<arquivo original>`.
- Stack: `httr2` (retry, rate limit, user agent identificado), `curl` para arquivos grandes,
  `digest`/`openssl` para hashes.

### 4.2 Silver — modelo canônico

**Responsabilidade:** transformar formatos heterogêneos do TSE em um modelo relacional único,
harmonizado entre turnos, com chaves declaradas e verificadas.

Entidades (granularidade → chave lógica):

| Tabela | Grão | Chave lógica |
|--------|------|--------------|
| `dim_municipio` | município | `municipio_tse` (+ `municipio_ibge`, `uf`, `nome`) |
| `dim_secao` | seção × turno | `election_id, turno, municipio_tse, zona, secao` |
| `dim_candidato` | candidato × turno | `election_id, turno, numero` (+ `categoria` vinda da config) |
| `vote_facts` | seção × turno × votável | `election_id, turno, municipio_tse, zona, secao, votavel` |
| `section_turnout` | seção × turno | `election_id, turno, municipio_tse, zona, secao` |
| `section_comparison` | seção × par de turnos | `election_id, municipio_tse, zona, secao` |
| `section_harmonization` | seção | idem; registra seção agregada, alterada, criada ou extinta entre turnos |

Regras específicas do domínio, tratadas aqui e em nenhum outro lugar:

- **TSE ≠ IBGE**: a correspondência `municipio_tse ↔ municipio_ibge` vem de uma tabela oficial,
  versionada em `data/reference/`.
- **Seções agregadas, tipo de seção (trânsito, especial), mudança de aptos e local de votação**
  seguem as verificações V2 e as classes de população de `05-metodo-analitico.md` §2–3, gravadas
  por unidade (`section_type`, `population_status`, `in_transition_analysis`, `exclusion_reason`).
- **Exterior (UF `ZZ`)** é uma pseudo-UF e fica fora do escopo (não é município).

Armazenamento: Parquet/ZSTD particionado por `uf`, escrito pelo DuckDB em R
(`COPY ... TO ... (FORMAT parquet, COMPRESSION zstd, PARTITION_BY (uf))`). As chaves e as FKs são
declaradas com `{dm}` sobre a conexão DuckDB; `dm_examine_constraints()` é **gate** (falha o
target), não relatório impresso.

### 4.3 Gold — motor analítico

**Responsabilidade:** produzir todos os resultados analíticos em fidelidade total. A Gold é o
"produto de dados" do projeto: além de alimentar o site, pode ser publicada como dataset aberto
para quem quiser reproduzir ou auditar.

Módulos, cada um com entrada e saída tabulares:

| Módulo | Entrada | Saída (Gold) | `evidence_type` |
|--------|---------|--------------|----------------|
| `reconcile/` | Silver | `reconciliation` — município × verificação: esperado, observado, resíduo, `pass` | observed |
| `accounting/` | `section_comparison` | `municipal_indicators` — deltas, terceiros, inválidos, participação, normalizados por 100 aptos | observed |
| `ecological/bounds` | margens por seção | `section_bounds`, `municipal_bounds` — mín/máx de cada célula origem→destino por conjunto de hipóteses (LP) | conditional_bound |
| `ecological/model` | `section_comparison` (unidades do próprio município, sem pooling entre municípios) | `transition_estimates` — média posterior das contagens, intervalo, faixa entre métodos, classe de identificação, `model_version`, `status` | model_estimate |
| `ecological/scenarios` | margens + hipóteses | `scenarios` — resultado sob cada contrafactual explícito | conditional_bound ou model_estimate, declarado por cenário |
| `ecological/uncertainty` | modelo | quantis, histogramas agregados (sem draws) | model_estimate |
| `ecological/calibration` | margens reais do 1º turno + processos G1–G4 | `calibration_report` — cobertura e erro por classe de identificação e porte; fixa os limiares de `config/metodo.yml` | — |
| `diagnostics/` | modelo + Silver | `model_diagnostics` — R-hat, ESS, unidades usadas, cobertura, checagem preditiva, classe de identificação por célula | — |
| `context/` | `municipal_indicators` | `municipal_context` — posição do município entre comparáveis (UF, porte, perfil) | observed |
| `logs/` (posterior) | logs de urna | `vote_time_profile` — distribuição temporal agregada, só onde a cobertura é confiável | observed |

Regras do motor:

- **Limites, estimação e cenários** conforme `05-metodo-analitico.md` §4–5: limites de Fréchet
  somados por unidade; estimação com pelo menos dois métodos de famílias diferentes (`md-bayes` via
  `eiPack::ei.MD.bayes`, `lphom`, opcionalmente `ecolRxC`); cenários com restrições por unidade. A
  interface mostra limites e estimativa na mesma tabela, com a classe de identificação de cada célula.
- **Sem pooling entre municípios** na estimativa municipal. Um contexto por UF, se existir, é outro
  produto, rotulado como tal.
- **Hipóteses são dados.** Cada conjunto de restrições tem um `assumption_id` documentado em
  `assumptions.yml` (descrição legível, restrições formais). O ID é publicado junto com o número.
- **Determinismo.** Seeds fixos por `(release_id, municipio_tse, method_id)`; múltiplas cadeias e
  pontos iniciais; a `model_version` muda sempre que código, priors ou restrições mudam.

### 4.4 Camada de apresentação web — `R/web/`

Mesmo desenho do DudesApp, que já se provou:

```text
R/web/
├── build_web_bundle.R      orquestrador: resolve a release, lê Gold, laço de escrita, manifest
├── validate_web_bundle.R   gate: relê o bundle do disco e faz stop() na primeira violação
├── bundle/                 um build_<mart>() por mart: tibble entra, tibble sai, sem I/O
└── utils/
    ├── schema.R            ids → string, sem list-columns, coerção de tipos, NA → NULL
    ├── parquet.R           write_mart(): ponto único de escrita (DuckDB COPY, ZSTD, ordenação)
    └── contract.R          lê contract/ (versão legível por máquina do 03: grão, PK, tipos)
```

- **Não analisa nada.** Seleciona, renomeia, junta dimensões para leitura humana, ordena e escreve.
  Se um mart precisa de um cálculo novo, esse cálculo vai para a Gold.
- **Contrato legível por máquina.** Diferente do DudesApp, onde o mapa de PKs está duplicado entre
  `validate_web_bundle.R` e `tests/web/test_pk_unique.R`, aqui grão, PK, partição, colunas
  obrigatórias e tipos de cada arquivo ficam em **um** lugar, `contract/` (JSON Schema + `marts.yml`),
  lido pelo validador e pelos testes. É a tradução executável de `03-contratos-de-dados.md`: mudança
  de schema altera os dois na mesma alteração, com nova `schema_version`.
- **Ordenação física é contrato.** Marts particionados por UF são escritos ordenados por
  `municipio_tse, zona, secao`, com row groups pequenos, para que o DuckDB-Wasm leia só o trecho do
  município (ver §6).

### 4.5 Frontend estático — `web/`

Mesmo stack do DudesApp: **Quarto website + ES modules sem etapa de build + DuckDB-Wasm + Plotly**.

- **Por que Quarto, e não SvelteKit/React** (cogitados na visão inicial e na primeira versão do
  pacote 01–04): a página de metodologia
  é parte central do produto, com matemática (identidades, matrizes, graus de liberdade); o Quarto
  renderiza LaTeX nativamente, é escrito em R/Markdown pelo mesmo autor do pipeline e dispensa Node.
  O DudesApp mostra que o padrão "`.qmd` com `<div id="app">` + `boot("<página>")`" escala bem para
  uma aplicação interativa.
- **Por que Plotly**, e não Observable Plot + d3-sankey: o Plotly tem trace `sankey` nativo,
  choropleth com GeoJSON e reaproveita os componentes e a experiência do DudesApp. Uma biblioteca
  só.
- Módulos JS (espelhando `web/js/` do DudesApp):

```text
web/js/
├── head.html        import map com versões fixas (DuckDB-Wasm, Plotly) — CDN ou vendor/
├── data.js          ÚNICO módulo que busca latest/catálogo/manifesto/resumo e fala com DuckDB-Wasm
├── catalog.js       busca de município sobre catalogo.json (sem DuckDB; acentos, homônimos por UF)
├── state.js         seleção canônica na URL (e, m, aba); invalida respostas de recortes anteriores
├── format.js        pt-BR: números, sinais, percentuais, pontos percentuais, intervalos, datas
├── evidence.js      rótulos e estilos por evidence_type (observed / conditional_bound / model_estimate)
├── components.js    blocos de UI: MetricStrip, ChartFrame, tabelas, DataQualityNotice, estados
├── charts.js        wrappers Plotly: slope, waterfall, scatter por seção, intervalos, Sankey
├── app.js           shell: cabeçalho (eleição, município, release), banners de status
└── pages/           index · explorar · dados-e-codigo
```

- **Páginas Quarto** (nomes de `02-especificacao-funcional-tecnica.md` §3): `index.qmd` (busca),
  `explorar.qmd` (uma página para todos os municípios, com abas renderizadas no cliente),
  `metodologia.qmd` (estática, com fórmulas), `dados-e-codigo.qmd` (fontes, downloads,
  proveniência, como reproduzir) e `sobre.qmd` (independência e origem da análise).
  `comparar.qmd` fica para depois do MVP.
- **Crédito da ideia** no `page-footer` de `web/_quarto.yml`, presente em todas as páginas: análise
  inspirada na [thread de Rômulo Fiúza e Mello](https://x.com/fiuzaemello/status/2114763737425211824)
  (@fiuzaemello). `sobre.qmd` detalha a origem.
- **Estado em URL**, compartilhável: `explorar.html?e=<election_id>&m=<municipio_tse>&aba=<aba>`.
- **Estilo:** `web/css/design-tokens.css` (tokens canônicos de `01-guia-identidade-visual.md`) é
  incluído via `_quarto.yml`; o tema Quarto não pode introduzir cores, sombras ou componentes fora
  do guia.

---

## 5. Contrato de dados web

O schema canônico — campos, tipos, enums e invariantes — está em
[`03-contratos-de-dados.md`](03-contratos-de-dados.md). Esta seção só descreve como a arquitetura
o materializa; em caso de divergência, vale o 03.

### 5.1 Cadeia de carregamento

```text
latest.json                                   único arquivo mutável (Cache-Control: no-cache)
└── releases/<release_id>/catalogo.json       busca de município, sem DuckDB
    └── …/<municipio_tse>/manifest.json       features, assets (path + sha256), fontes, versões
        ├── resumo.json · qualidade.json      first paint e aba Qualidade, sem Wasm
        └── secoes · limites · cenarios · fluxos_estimados · horarios (.parquet)
                                              via DuckDB-Wasm, só ao abrir a aba que usa
```

Regras herdadas do DudesApp: o frontend checa o *major* de `schema_version` e recusa versões que
não conhece; caminhos vêm só do manifesto (I8); `uf` e `municipio_tse` são validados contra o
catálogo antes de virar caminho ou parâmetro SQL (I9).

### 5.2 Empacotamento físico

O 03 deixa o empacotamento a cargo do produtor, desde que o manifesto o abstraia. Proposta
(ADR-04): JSON leves por município; Parquet de detalhe agrupado por UF (`uf=<UF>/secoes.parquet`
etc.), ordenado por `municipio_tse, zona, secao`, com row groups pequenos. O manifesto do município
aponta o arquivo da UF e o `data.js` filtra por `municipio_tse`; o DuckDB-Wasm usa as estatísticas
min/max dos row groups e HTTP Range para baixar só o trecho necessário. São cerca de 27 arquivos por
tipo de Parquet, contra mais de 16 mil no layout por município.

### 5.3 Regras de tipo e forma (herdadas do DudesApp)

- Identificadores (`municipio_tse`, `municipio_ibge`, `zona`, `secao`, `*_id`) são **string**.
  Evita perda de zeros à esquerda e o `BigInt` do Arrow no JS.
- Contagens: `integer`. Medidas, proporções, limites e quantis: `double`. Flags: `boolean`.
- Ausente = `NULL` no Parquet; nunca `"NA"`, `""` ou `0`.
- Nada de list-columns; estruturas aninhadas viram formato longo.

### 5.4 Arquivos por tela

| Tela / aba | Arquivos | `evidence_type` |
|------------|----------|-----------------|
| Busca | `catalogo.json` | — |
| Resumo | `resumo.json` | observed |
| Seções | `secoes.parquet` | observed |
| Transferências | `limites.parquet`; `fluxos_estimados.parquet` só com modelo `ready` | conditional_bound; model_estimate |
| Cenários | `cenarios.parquet` | declarado por cenário |
| Qualidade | `qualidade.json`, manifesto | — |
| Horários | `horarios.parquet`, só com logs válidos | observed |

---

## 6. Consulta no navegador

Padrão de `web/js/data.js` do DudesApp, com quatro ajustes para a escala nacional.

1. **Inicialização lazy do DuckDB-Wasm.** A home e a busca usam só `catalogo.json` (fetch
   simples), sem carregar os vários MB de WASM. O DuckDB começa a carregar em segundo plano depois
   da primeira renderização (`requestIdleCallback`) e só é aguardado nas abas de detalhe. É o que
   mantém o site usável no celular (visão, §9).
2. **Registro pelo manifesto.** `register("secoes")` lê o caminho listado no manifesto do
   município (o arquivo da UF, no empacotamento do ADR-04), faz
   `registerFileURL(..., DuckDBDataProtocol.HTTP, false)` e cria uma view filtrada por
   `municipio_tse`. Glob/Hive não funcionam sobre HTTP (não há listagem), então cada arquivo é
   registrado explicitamente.
3. **Prepared statements.** O DudesApp interpola strings removendo aspas; aqui as consultas usam
   `conn.prepare(...)` com parâmetros, e `uf`/`municipio_tse` passam por validação contra o
   catálogo antes (I9).
4. **Superfície SQL restrita.** Continua valendo a regra do DudesApp: o frontend só faz `WHERE`,
   `ORDER BY`, `LIMIT`, `GROUP BY` com agregações simples e normalizações de exibição (por 100
   aptos). Se uma tela precisa de mais que isso, falta um mart.

Requisitos do host de dados: `Accept-Ranges: bytes`; CORS com `GET`, `HEAD` e o header `Range`
permitidos e `Content-Length`, `Content-Range` e `ETag` expostos.

---

## 7. Orquestração e reprodutibilidade

O DudesApp roda por `source()` com um bloco de "master parameters" editado à mão. A revisão do
próprio DudesApp (`docs/PIPELINE_REVIEW.md`) apontou as consequências: parâmetros hardcoded,
documentação divergente, tags em string livre criando partições órfãs e tabelas que só recebem
upsert e nunca apagam. Na escala nacional isso não se sustenta, então aqui:

- **`targets`** orquestra o grafo; ramificação dinâmica por UF (`pattern = map(uf)`), e por
  município dentro da UF onde o custo justificar. `crew` paraleliza os workers.
- **`renv`** fixa as versões dos pacotes; o hash do `renv.lock` vai para o manifest.
- **Configuração por eleição** em `config/eleicoes/<election_id>.yml` (formato da visão, §8),
  validada com `checkmate` na entrada do pipeline. `election_id`, categorias, métodos e hipóteses
  são vocabulário fechado: um valor desconhecido falha o build, não cria partição nova.
- **`release_id = <election_id>-<timestamp UTC>`** é a chave de rastreabilidade, papel que o
  `run_id` tem no DudesApp: dados → modelo → mart → tela.
- **Builds completos e imutáveis por release**, sem upsert incremental na Gold publicada. O `targets`
  evita recomputar o que não mudou; a release em si é sempre um snapshot fechado.
- **Execução:** `tar_make()` → `build_web_bundle(election_id)` → `validate_web_bundle()` →
  `quarto render web`. Um único `Rscript run.R <election_id>` encadeia tudo.

---

## 8. Qualidade e validação

Há três níveis de falha com tratamentos diferentes. Essa é a principal mudança em relação ao
DudesApp, onde toda violação interrompe o build: em escala nacional, um município problemático não
pode bloquear os outros 5,5 mil.

| Nível | Exemplos | Tratamento |
|-------|----------|------------|
| **Contrato** | PK duplicada, coluna ausente, tipo errado, FK para município inexistente, `model_estimate` sem intervalo, fixture `DEMO-*`/`00000` na release | `stop()` — nenhuma release é gerada |
| **Dados (por município)** | resíduo da identidade ≠ 0, total diverge do oficial, 2º turno ausente, seções sem correspondência | quarentena: `validation_status != "passed"`, `features.*` em `partial`/`failed`, `publication_status` `partial`/`unavailable` no catálogo; só `observed` publicado, motivo exposto na aba Qualidade |
| **Estatística (por município)** | falha computacional, poucas unidades, cobertura baixa, checagem preditiva reprovada, pouca massa de mudança identificada | `features.ecological_model` = `partial`, `insufficient_data` ou `failed`, conforme `05-metodo-analitico.md` §5.7 |

Testes (`testthat`, desde o primeiro commit; o DudesApp só ganhou testes depois):

- **Fixture-ouro sintética.** Município fictício (`DEMO-*`/`00000`) com seções geradas a partir de
  uma matriz de transição conhecida: teste de aceitação da Silver, da contabilidade (resíduo zero)
  e, na fase 3, da recuperação do modelo. Nenhum município real tem fixture ou tratamento especial;
  testes com dados reais do TSE usam municípios escolhidos por perfil (pequeno, grande, com seções
  agregadas).
- **Identidades contábeis** por seção (I2) em fixtures sintéticas, incluindo seção agregada e
  variação de aptos.
- **Limites (LP)** contra casos com solução fechada (limites de Fréchet sem restrições extras).
- **Contrato do bundle:** PK única, sem list-columns, tipos, `evidence_type` válido, I5 e I6, tudo
  dirigido por `contract/`.
- **Ponta a ponta:** build do bundle a partir de uma Gold mínima em `tests/fixtures/` (padrão
  `test_build_end_to_end.R` do DudesApp).
- **Frontend:** módulos JS puros com `node tests/web/<módulo>.check.mjs` (padrão DudesApp, sem
  npm); E2E, acessibilidade (axe) e screenshots 375/768/1440 px com Playwright em `tests/e2e/`,
  ferramenta só de desenvolvimento, contra o site renderizado com o bundle sintético de
  `tests/fixtures/`.

---

## 9. Publicação e deploy

| Ambiente | App | Dados |
|----------|-----|-------|
| Desenvolvimento | `quarto preview web` | `web/data/` local, mesma origem, release de fixture ou de uma UF |
| Fase 1–2 | GitHub Pages ou Cloudflare Pages, como no DudesApp | dentro do `_site/` (volume pequeno) |
| Fase 3+ | Cloudflare Pages (ou similar) | object storage com CDN (Cloudflare R2 ou S3 + CloudFront), Range + CORS |

Ordem de publicação de uma release, pensada para o site nunca apontar para dados incompletos:

1. sobe `releases/<release_id>/` inteira (imutável, `Cache-Control: public, max-age=31536000, immutable`);
2. verifica a release remota (HEAD em todos os arquivos dos manifestos, uma consulta Range de amostra);
3. troca o `latest.json` (o único arquivo mutável);
4. publica o app, se ele mudou.

**Rollback** = voltar o `latest.json` para a release anterior. Releases antigas ficam no storage
até uma política explícita de retenção.

Como no DudesApp, `data/` e o bundle são gitignored e o build roda na máquina do autor; o CI, quando
existir, roda testes com fixtures, não o pipeline nacional.

Dependências de runtime (Plotly, DuckDB-Wasm) vêm de jsDelivr com versão fixa no import map,
começando pelas mesmas do DudesApp (`@duckdb/duckdb-wasm@1.29.0`, `plotly.js-dist-min@2.35.2`).
O `web/vendor/` permite servir tudo localmente, se o CDN de terceiros virar problema.

---

## 10. Estrutura do repositório

Três áreas que não se misturam: **código da aplicação** (pipeline R + site), **documentação** e
**exemplos de referência**. Marcado com `*`: já existe hoje; o resto nasce nas fases do roteiro.

```text
obsEleitoral/
├── README.md · CLAUDE.md *
├── _targets.R                    grafo do pipeline
├── run.R                         ponto de entrada: Rscript run.R <election_id>
├── renv.lock
├── config/
│   ├── eleicoes/<election_id>.yml
│   ├── assumptions.yml           hipóteses dos métodos (ids + texto + restrições)
│   └── metodo.yml                parâmetros e limiares do método (05 §6), versionados
├── contract/                     versão legível por máquina do 03 (JSON Schema + marts.yml)
├── R/
│   ├── tse/                      adaptadores Bronze (descobrir, baixar, verificar)
│   ├── normalize/                Silver: parse, harmonização, TSE↔IBGE, dm de chaves
│   ├── reconcile/                identidades, totais oficiais, cobertura
│   ├── accounting/               indicadores observados
│   ├── ecological/               bounds.R · model.R · scenarios.R · uncertainty.R
│   ├── diagnostics/
│   ├── context/
│   ├── web/                      build_web_bundle(), bundle/, utils/, validate_web_bundle.R
│   └── utils/
├── web/                          site Quarto (código da aplicação)
│   ├── _quarto.yml               navegação, page-footer com crédito, inclusão dos tokens
│   ├── *.qmd                     index · explorar · metodologia · dados-e-codigo · sobre
│   ├── css/design-tokens.css *   tokens canônicos da identidade
│   ├── js/                       head.html, módulos ES, pages/
│   ├── vendor/                   (opcional) Plotly e DuckDB-Wasm servidos localmente
│   └── data/                     (gitignored) bundle local para preview
├── tests/
│   ├── testthat/                 R: parser, reconciliação, LP, modelo, contrato
│   ├── web/                      *.check.mjs dos módulos JS puros
│   ├── e2e/                      Playwright + axe (dev)
│   └── fixtures/                 seções e bundle sintéticos (DEMO-*, nunca em release)
├── data/                         (gitignored)
│   ├── reference/                TSE↔IBGE
│   ├── bronze/ · silver/ · gold/
│   └── releases/
├── docs/ *
│   ├── visao_inicial.md          origem: análise da thread que inspirou o projeto
│   ├── arquitetura.md            este documento
│   ├── 01-guia-identidade-visual.md
│   ├── 02-especificacao-funcional-tecnica.md
│   ├── 03-contratos-de-dados.md
│   ├── 04-roteiro-implementacao-claude-code.md
│   ├── 05-metodo-analitico.md
│   └── analise-critica-metodologia.md
└── examples/ *                   referência; nada aqui é lido pela aplicação nem entra em release
    ├── contrato/                 *.demo.json — exemplos fictícios dos contratos do 03
    └── preview/                  prévia HTML estática da identidade + screenshots
```

---

## 11. O que vem do DudesApp e o que muda

| Aspecto | DudesApp | Observatório | Motivo |
|---------|----------|--------------|--------|
| Fronteira analítica | R calcula, browser apresenta | **igual** | separa complexidade de interface |
| Bundle | presentation marts + `manifest.json` | **igual** no espírito: `latest.json` → `catalogo.json` → manifesto por município (03) | multi-eleição, first paint sem Wasm e plano de dados separado |
| Escrita | `write_mart()` com `nanoparquet` | `write_mart()` com DuckDB `COPY` (ZSTD, ordenação, partição) | volume nacional e row groups controlados; continua sem `arrow` |
| Gate | `validate_web_bundle()` com `stop()` | **igual** para contrato + quarentena por município | um município ruim não derruba a release |
| Contrato | Markdown + PKs duplicadas no código | `contract/marts.yml` como fonte única | elimina a duplicação validador/testes |
| Armazenamento interno | `.rds` com objetos `dm` | Parquet Bronze/Silver/Gold via DuckDB; `dm` só para declarar e checar chaves | `.rds` não escala nem é consultável fora da memória |
| Orquestração | `source()` + parâmetros editados à mão | `targets` + `renv` + YAML validado | lições do `PIPELINE_REVIEW.md` |
| Versionamento | `run_id` (acumula no `decision_db`) | `release_id` imutável; Gold por release | auditabilidade pública |
| Frontend | Quarto + ES modules + DuckDB-Wasm + Plotly | **igual** + catálogo sem DuckDB e init lazy | primeira tela leve no celular |
| SQL no browser | interpolação com remoção de aspas | prepared statements + validação contra catálogo | entrada pública, não liga privada |
| Estado | URL → localStorage → manifest | **igual** | links compartilháveis por município |
| Draws | não publicados; bins agregados | **igual** | tamanho e clareza |
| Saúde dos dados | página `data-health` | aba **Qualidade** por município + página de auditoria | auditoria é requisito do produto |
| Privacidade | modo `public` remove nomes de donos | dados públicos do TSE; nada a esconder, tudo a referenciar | o risco aqui é interpretação errada, não vazamento |
| Testes | adicionados depois, script próprio | `testthat` desde o início, fixture-ouro | o produto é contestável publicamente |

---

## 12. Registro de decisões

| ID | Decisão | Alternativa descartada | Por quê | Rever se… |
|----|---------|------------------------|---------|-----------|
| ADR-01 | Site estático + DuckDB-Wasm sobre Parquet pré-computado | API/servidor R (Shiny, Plumber) | custo zero de operação, escala por CDN, mesmo padrão do DudesApp | surgir funcionalidade que exija computação por usuário |
| ADR-02 | webR fora do núcleo | rodar inferência no navegador | modelos são pesados e devem ser idênticos para todos; celular | houver demanda real por simulações próprias de usuários avançados (vira módulo opcional) |
| ADR-03 | Quarto + ES modules, sem build Node | SvelteKit / React + Vite | metodologia com LaTeX, autor único em R, reaproveita o DudesApp | a interface exigir componentização que fique inviável sem framework |
| ADR-04 | Marts de detalhe particionados por UF, ordenados por município, lidos com HTTP Range | um diretório por município (visão §9) | ~27 arquivos por mart, contra mais de 16 mil por eleição; limites de arquivos por deploy nos hosts estáticos; cache de CDN mais eficiente | o spike da fase 3 mostrar latência ruim ou Range pouco confiável no host → plano B: arquivos por município no object storage (sem limite de quantidade) |
| ADR-05 | Plano de dados (object storage) separado do plano do app a partir da fase 3 | tudo dentro de `_site/` | volume nacional, releases imutáveis, rollback por troca de manifest | o volume total couber com folga num deploy de Pages |
| ADR-06 | DuckDB em R como motor Silver/Gold e escritor de Parquet; sem `arrow` | `arrow` + `data.table` | um motor só, out-of-core, partição e ZSTD nativos; o DudesApp já evitou `arrow` pelo peso da instalação | surgir gargalo que o DuckDB não resolva |
| ADR-07 | Plotly como biblioteca única de gráficos | Observable Plot + d3-sankey | Sankey e choropleth nativos, reuso do DudesApp | o peso do Plotly no celular se mostrar crítico → avaliar build parcial do Plotly |
| ADR-08 | `targets` + `renv` + YAML validado | `source()` com parâmetros no script (DudesApp) | ramificação por UF, cache incremental, vocabulário fechado | — |
| ADR-09 | `evidence_type` obrigatório em todo número publicado | separar só por página/aba | a distinção observed/conditional_bound/model_estimate é a tese metodológica do projeto | — |
| ADR-10 | Quarentena por município em vez de falha global para problemas de dados | `stop()` em qualquer inconsistência | cobertura nacional tolerante a falhas (visão §11) | — |

---

## 13. Evolução por etapas

Fases, gates e prompts: [`04-roteiro-implementacao-claude-code.md`](04-roteiro-implementacao-claude-code.md).
O desenvolvimento usa uma eleição de dois turnos já publicada (ex.: 2022) como base de teste da
infraestrutura; nenhuma fase depende de um município específico.

---

## 14. Riscos e questões em aberto

- **Disponibilidade do 2º turno no TSE** (visão, §5). Mitigação: adaptador de coleta individual e
  2022 como base de desenvolvimento.
- **Harmonização entre turnos** (seções agregadas, voto em trânsito, variação de aptos). Regra
  escrita em `05-metodo-analitico.md` §2–3; falta confirmar com os dados de 2022 a fonte do tipo de
  seção e a distribuição da mudança de aptos.
- **Custo computacional da estimação.** Dois ou mais métodos, validação cruzada e calibração por
  simulação para 5.570 municípios; medir o tempo por UF antes da Fase 3.
- **Arquivos JSON por município.** Manifesto, resumo e qualidade por município somam ~17 mil
  arquivos por eleição; se o host limitar, agrupar por UF (o 03 permite, via manifesto).
- **Limites dos hosts.** Número de arquivos por deploy, tamanho máximo de arquivo e suporte a Range
  variam por plano e mudam com o tempo; confirmar antes da fase 3.
- **Peso inicial no celular.** DuckDB-Wasm + Plotly somam vários MB; medir na fase 4 e decidir
  entre vendor, build parcial do Plotly ou adiar o DuckDB para a primeira interação.
- **SEO e prévia de link por município.** Uma página única renderizada no cliente não gera
  `og:title` por município. Opção: pré-gerar páginas mínimas por município só com metadados (5,6
  mil HTMLs pequenos), a decidir na fase 4.
- **Exterior (UF `ZZ`)**: decidido, fora do escopo (`05-metodo-analitico.md` §0).
- **Sensibilidade política.** A arquitetura reduz o risco de leitura errada (classes, hipóteses,
  proveniência sempre visíveis), mas o texto da interface e da metodologia precisa de revisão
  editorial própria, fora do escopo deste documento.
