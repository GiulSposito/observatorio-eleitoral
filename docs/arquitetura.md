# Arquitetura intencional — Observatório Eleitoral Municipal

> **Status:** proposta v0.1 · 2026-10-27
> **Base:** [`visao_inicial.md`](visao_inicial.md) (produto e metodologia) + a arquitetura
> já em produção no projeto DudesApp (`docs/app_arch.md`, `docs/app_web_data_contract.md`,
> `R/web/`, `web/`), adaptada para escala nacional.

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
4. **A classe do resultado faz parte do dado.** Todo número publicado carrega `result_class ∈
   {observado, limite, estimado}`, e a interface renderiza cada classe de um jeito diferente. Não
   existe um "número" sem classe.
5. **Incompleto é um estado, não um erro silencioso.** Município sem dados completos, sem
   reconciliação ou com baixa identificabilidade aparece com `status` explícito e **sem estimativa
   fabricada**.
6. **Proveniência ponta a ponta.** Qualquer número na tela leva até a release, o modelo, as
   hipóteses e os arquivos do TSE (URL + hash) que o produziram.
7. **O motor é genérico; a eleição é configuração.** Nada no código conhece "Lula", "Flávio",
   "2026" ou "presidente". Candidatos são mapeados para categorias (`finalist_a`, `finalist_b`,
   `other`, `invalid`, `abstention`) por arquivo de configuração.
8. **Infraestrutura mínima.** `git clone` + dados de entrada + build = aplicação completa.

Em uma frase (adaptada do DudesApp):

> **R calcula; Parquet transporta; DuckDB-Wasm seleciona; JavaScript apresenta.**

### 2.2 Invariantes verificáveis

São regras de revisão: um PR que viole uma delas está errado, mesmo que funcione.

| # | Invariante | Onde é verificada |
|---|------------|-------------------|
| I1 | Todo arquivo do TSE usado tem URL, `sha256`, tamanho e data de coleta registrados em `source_files` | teste da camada Bronze |
| I2 | Para eleição com dois finalistas, o resíduo da identidade ΔA + ΔB = O₁ + ΔC − ΔI é zero em toda seção harmonizada | `reconcile/`, gate de reconciliação |
| I3 | Somas por município e UF batem com os totais oficiais do TSE | `reconcile/` |
| I4 | Toda linha de mart com valor numérico tem `result_class`; `estimado` sempre traz `method_id`, `assumption_id`, `lower` e `upper` | `validate_web_bundle()` |
| I5 | Município com `status != "ok"` não tem linhas `estimado` | `validate_web_bundle()` |
| I6 | Todos os marts de uma release vêm do mesmo `release_id`, da mesma versão Silver e da mesma `model_version` | `validate_web_bundle()` |
| I7 | Identificadores são `string` no bundle; não há list-columns; `NA` vira `NULL` no Parquet | `write_mart()` |
| I8 | O frontend só conhece caminhos de dados via `manifest.json`; nenhum caminho fixo no JS | revisão + teste de fumaça |
| I9 | Nenhuma entrada do usuário chega a SQL ou a um caminho sem antes ser validada contra o catálogo | `web/js/data.js` |
| I10 | Draws de MCMC/bootstrap não são publicados; publicam-se quantis, intervalos e histogramas agregados | contrato de dados |

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
│  HTML · CSS · ES modules              manifest.json      (no-cache)      │
│  Plotly · DuckDB-Wasm                 releases/<release_id>/  (imutável) │
│        │                                catalogo-municipios.json         │
│        │  fetch manifest ─────────────► nacional/*.parquet               │
│        │  HTTP Range + CORS ──────────► uf=<UF>/*.parquet                │
│        ▼                                                                 │
│  navegador: busca → município → abas (Resumo · Seções · Fluxos ·         │
│             Cenários · Qualidade) · comparação · metodologia             │
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
- **Seções agregadas, seções alteradas entre turnos, voto em trânsito e variação de aptos** geram
  um `harmonization_status` por seção. Uma seção sem correspondência limpa entre turnos não entra na
  matriz fechada; ela é tratada como entrada/saída explícita (visão, §6).
- **Exterior (UF `ZZ`)** é uma pseudo-UF; fica fora do escopo municipal até haver decisão
  específica.

Armazenamento: Parquet/ZSTD particionado por `uf`, escrito pelo DuckDB em R
(`COPY ... TO ... (FORMAT parquet, COMPRESSION zstd, PARTITION_BY (uf))`). As chaves e as FKs são
declaradas com `{dm}` sobre a conexão DuckDB; `dm_examine_constraints()` é **gate** (falha o
target), não relatório impresso.

### 4.3 Gold — motor analítico

**Responsabilidade:** produzir todos os resultados analíticos em fidelidade total. A Gold é o
"produto de dados" do projeto: além de alimentar o site, pode ser publicada como dataset aberto
para quem quiser reproduzir ou auditar.

Módulos, cada um com entrada e saída tabulares:

| Módulo | Entrada | Saída (Gold) | `result_class` |
|--------|---------|--------------|----------------|
| `reconcile/` | Silver | `reconciliation` — município × verificação: esperado, observado, resíduo, `pass` | observado |
| `accounting/` | `section_comparison` | `municipal_indicators` — deltas, terceiros, inválidos, participação, normalizados por 100 aptos | observado |
| `ecological/bounds` | margens por seção | `section_bounds`, `municipal_bounds` — mín/máx de cada célula origem→destino por conjunto de hipóteses (LP) | limite |
| `ecological/model` | `section_comparison` (+ pooling por UF/perfil) | `transition_estimates` — estimativa, `lower`/`upper`, método, hipótese, `model_version`, `status` | estimado |
| `ecological/scenarios` | margens + hipóteses | `scenarios` — resultado sob cada contrafactual explícito | estimado |
| `ecological/uncertainty` | modelo | quantis, histogramas agregados (sem draws) | estimado |
| `diagnostics/` | modelo + Silver | `model_diagnostics` — R-hat, ESS, n de seções, peso do pooling, `identifiability` | — |
| `context/` | `municipal_indicators` | `municipal_context` — posição do município entre comparáveis (UF, porte, perfil) | observado |
| `logs/` (posterior) | logs de urna | `vote_time_profile` — distribuição temporal agregada, só onde a cobertura é confiável | observado |

Regras do motor:

- **Três métodos, nunca um só** (visão, §7): limites por LP, inferência ecológica estatística
  (ponto de partida `eiPack::ei.MD.bayes`; modelo hierárquico próprio em Stan/`cmdstanr` se
  necessário) e cenários contrafactuais. O site mostra os três lado a lado.
- **Pooling visível.** Quando um município pequeno empresta força de outros, a Gold registra o peso
  disso (`pooling_weight` ou equivalente) e a interface mostra.
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
    └── contract.R          lê contract/marts.yml (fonte única de grão, PK, tipos)
```

- **Não analisa nada.** Seleciona, renomeia, junta dimensões para leitura humana, ordena e escreve.
  Se um mart precisa de um cálculo novo, esse cálculo vai para a Gold.
- **Contrato legível por máquina.** Diferente do DudesApp, onde o mapa de PKs está duplicado entre
  `validate_web_bundle.R` e `tests/web/test_pk_unique.R`, aqui grão, PK, partição, colunas
  obrigatórias e tipos de cada mart ficam em **um** arquivo, `contract/marts.yml`, lido pelo
  validador, pelos testes e pelo gerador da documentação do contrato.
- **Ordenação física é contrato.** Marts particionados por UF são escritos ordenados por
  `municipio_tse, zona, secao`, com row groups pequenos, para que o DuckDB-Wasm leia só o trecho do
  município (ver §6).

### 4.5 Frontend estático — `web/`

Mesmo stack do DudesApp: **Quarto website + ES modules sem etapa de build + DuckDB-Wasm + Plotly**.

- **Por que Quarto, e não SvelteKit/React** (que a visão inicial cogitava): a página de metodologia
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
├── data.js          ÚNICO módulo que fala com DuckDB-Wasm; accessors tipados
├── catalog.js       busca de município sobre catalogo-municipios.json (sem DuckDB)
├── state.js         seleção canônica: URL → localStorage → defaults do manifest
├── format.js        pt-BR: números, sinais, percentuais, intervalos
├── classes.js       renderização por result_class (observado / limite / estimado)
├── charts.js        wrappers Plotly: barras por seção, Sankey, intervalos, histogramas
├── app.js           shell: cabeçalho (eleição, município, release), banners de status
└── pages/           index · municipio · comparar · qualidade · dados
```

- **Páginas Quarto:** `index.qmd` (busca + panorama nacional), `municipio.qmd` (uma página para
  todos os municípios, com abas renderizadas no cliente), `comparar.qmd`, `metodologia.qmd`
  (estática, com fórmulas), `dados.qmd` (downloads da Gold, proveniência, como reproduzir),
  `sobre.qmd`.
- **Estado em URL**, compartilhável: `municipio.html?eleicao=2026-presidente&uf=SC&mun=<tse>&aba=fluxos&metodo=...`.

---

## 5. Contrato de dados web

O contrato completo fica em `docs/web_data_contract.md`, gerado em parte a partir de
`contract/marts.yml`. Aqui fica só a estrutura.

### 5.1 `manifest.json` — bootstrap

Primeiro e único arquivo com caminho fixo. Servido com `Cache-Control: no-cache`; todo o resto é
imutável.

```json
{
  "schema_version": "1.0.0",
  "generated_at": "2026-11-15T12:00:00Z",
  "data_base_url": "https://dados.exemplo.org/releases/2026-presidente-20261115T120000/",
  "elections": [
    {
      "election_id": "2026-presidente",
      "release_id": "2026-presidente-20261115T120000",
      "model_versions": { "bounds": "lp-v1", "ei": "ei-hier-v1", "scenarios": "scn-v1" },
      "silver_version": "s-20261114",
      "git_sha": "abc1234",
      "renv_lock_sha256": "…",
      "coverage": { "municipios": 5570, "ok": 5412, "incompleto": 120, "baixa_identificabilidade": 38 }
    }
  ],
  "datasets": {
    "catalogo":       "catalogo-municipios.json",
    "municipios":     "nacional/municipios.parquet",
    "secoes":         "uf={uf}/secoes.parquet",
    "fluxos":         "uf={uf}/fluxos.parquet",
    "limites":        "uf={uf}/limites.parquet",
    "cenarios":       "uf={uf}/cenarios.parquet",
    "qualidade":      "uf={uf}/qualidade.parquet",
    "metodos":        "metodos.json",
    "fontes":         "nacional/fontes.parquet"
  }
}
```

Regras herdadas do DudesApp: o frontend checa o *major* de `schema_version` e recusa versões que não
conhece; caminhos vêm só de `datasets`; `{uf}` é preenchido com um valor validado contra o catálogo.

### 5.2 Layout da release

```text
releases/<release_id>/
├── catalogo-municipios.json      ~5,6 mil linhas: código TSE/IBGE, nome, UF, n_secoes, status
├── metodos.json                  métodos, hipóteses e textos de interface (de assumptions.yml)
├── nacional/
│   ├── municipios.parquet        1 linha/município: KPIs, status, flags de qualidade, contexto
│   └── fontes.parquet            proveniência resumida (source_files)
├── uf=SC/
│   ├── secoes.parquet            seção × par de turnos, pronto para a aba Seções
│   ├── fluxos.parquet            município × origem × destino × método × hipótese (Sankey)
│   ├── limites.parquet           município (e seção) × célula × hipótese: mín/máx
│   ├── cenarios.parquet          município × cenário × categoria
│   └── qualidade.parquet         reconciliação + diagnósticos por município
├── uf=SP/ …
└── gold/                         (opcional) Gold completa para download/reprodução
```

**Particionamento por UF, não por município.** São cerca de 27 arquivos por mart, contra mais de 16
mil arquivos por eleição no layout por município da visão inicial. Cada arquivo é ordenado por
município com row groups pequenos, e o DuckDB-Wasm usa as estatísticas min/max dos row groups e
HTTP Range para baixar só o trecho necessário. Detalhes e plano B em [ADR-04](#12-registro-de-decisões).

### 5.3 Regras de tipo e forma (herdadas do DudesApp)

- Identificadores (`municipio_tse`, `municipio_ibge`, `zona`, `secao`, `*_id`) são **string**.
  Evita perda de zeros à esquerda e o `BigInt` do Arrow no JS.
- Contagens: `integer`. Medidas, proporções, limites e quantis: `double`. Flags: `boolean`.
- Ausente = `NULL` no Parquet; nunca `"NA"`, `""` ou `0`.
- Nada de list-columns; estruturas aninhadas viram formato longo.
- Formato longo para indicadores (`indicator_id`, `value`, `lower`, `upper`, `result_class`,
  `method_id`, `assumption_id`) em vez de dezenas de colunas largas, para que novos indicadores não
  quebrem o schema.

### 5.4 Marts por tela

| Tela / aba | Marts | Classe predominante |
|------------|-------|---------------------|
| Busca, panorama | `catalogo`, `municipios` | observado |
| Resumo | `municipios` (linha do município), `fluxos` (destaques) | observado + estimado |
| Seções | `secoes` | observado |
| Fluxos (Sankey) | `fluxos`, `limites` | estimado + limite |
| Cenários | `cenarios`, `metodos` | estimado |
| Qualidade / auditoria | `qualidade`, `fontes`, manifest | — |
| Comparar municípios | `municipios`, `secoes` de cada município | observado |

---

## 6. Consulta no navegador

Padrão de `web/js/data.js` do DudesApp, com quatro ajustes para a escala nacional.

1. **Inicialização lazy do DuckDB-Wasm.** A home e a busca usam só `catalogo-municipios.json` (fetch
   simples), sem carregar os vários MB de WASM. O DuckDB começa a carregar em segundo plano depois
   da primeira renderização (`requestIdleCallback`) e é aguardado na página do município. É o que
   mantém o site usável no celular (visão, §9).
2. **Registro por UF.** `register("secoes", { uf })` resolve o template do manifest, faz
   `registerFileURL(..., DuckDBDataProtocol.HTTP, false)` e cria uma view
   `secoes_<uf>`. Glob/Hive não funcionam sobre HTTP (não há listagem), então cada arquivo é
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
| **Contrato** | PK duplicada, coluna ausente, tipo errado, FK para município inexistente, `estimado` sem intervalo | `stop()` — nenhuma release é gerada |
| **Dados (por município)** | resíduo da identidade ≠ 0, total diverge do oficial, 2º turno ausente, seções sem correspondência | município entra em quarentena: `status = "incompleto"` ou `"falha_reconciliacao"`, só dados observados publicados, motivo exposto na aba Qualidade |
| **Estatística (por município × método)** | R-hat alto, ESS baixo, poucas seções, pooling dominante | `status = "baixa_identificabilidade"`, estimativa publicada com aviso, ou suprimida conforme regra da config |

Testes (`testthat`, desde o primeiro commit; o DudesApp só ganhou testes depois):

- **Fixture-ouro de Lebon Régis/SC.** Os números da thread (Lula 2.899 → 3.503, Flávio 3.245 →
  3.481, outros 456, válidos 6.600 → 6.984, brancos e nulos 313 → 182, comparecimento 6.913 → 7.166,
  30 seções) são teste de aceitação da Silver e da contabilidade.
- **Identidades contábeis** por seção (I2) em fixtures sintéticas, incluindo seção agregada e
  variação de aptos.
- **Limites (LP)** contra casos com solução fechada (limites de Fréchet sem restrições extras).
- **Contrato do bundle:** PK única, sem list-columns, tipos, `result_class` válido, I5 e I6, tudo
  dirigido por `contract/marts.yml`.
- **Ponta a ponta:** build do bundle a partir de uma Gold mínima em `tests/fixtures/` (padrão
  `test_build_end_to_end.R` do DudesApp).
- **Fumaça do frontend** (opcional, fase 4): carregar `municipio.html` de um fixture em navegador
  headless e checar ausência de erros no console.

---

## 9. Publicação e deploy

| Ambiente | App | Dados |
|----------|-----|-------|
| Desenvolvimento | `quarto preview web` | `web/data/` local, mesma origem, release de fixture ou de uma UF |
| Fase 1–2 | GitHub Pages ou Cloudflare Pages, como no DudesApp | dentro do `_site/` (volume pequeno) |
| Fase 3+ | Cloudflare Pages (ou similar) | object storage com CDN (Cloudflare R2 ou S3 + CloudFront), Range + CORS |

Ordem de publicação de uma release, pensada para o site nunca apontar para dados incompletos:

1. sobe `releases/<release_id>/` inteira (imutável, `Cache-Control: public, max-age=31536000, immutable`);
2. verifica a release remota (HEAD em todos os arquivos do manifest, uma consulta Range de amostra);
3. troca o `manifest.json` (o único arquivo mutável);
4. publica o app, se ele mudou.

**Rollback** = voltar o `manifest.json` para a release anterior. Releases antigas ficam no storage
até uma política explícita de retenção.

Como no DudesApp, `data/` e o bundle são gitignored e o build roda na máquina do autor; o CI, quando
existir, roda testes com fixtures, não o pipeline nacional.

Dependências de runtime (Plotly, DuckDB-Wasm) vêm de jsDelivr com versão fixa no import map,
começando pelas mesmas do DudesApp (`@duckdb/duckdb-wasm@1.29.0`, `plotly.js-dist-min@2.35.2`).
O `web/vendor/` permite servir tudo localmente, se o CDN de terceiros virar problema.

---

## 10. Estrutura do repositório

```text
obsEleitoral/
├── _targets.R
├── run.R                         ponto de entrada: Rscript run.R <election_id>
├── renv.lock
├── config/
│   ├── eleicoes/2026-presidente.yml
│   ├── eleicoes/2022-presidente.yml
│   └── assumptions.yml           hipóteses dos métodos (ids + texto + restrições)
├── contract/
│   └── marts.yml                 fonte única do contrato web (grão, PK, tipos, partição)
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
├── tests/
│   ├── testthat/
│   └── fixtures/                 Lebon Régis, seções sintéticas, Gold mínima
├── data/                         (gitignored)
│   ├── reference/                TSE↔IBGE, malhas simplificadas
│   ├── bronze/
│   ├── silver/
│   ├── gold/
│   └── releases/
├── web/                          site Quarto
│   ├── _quarto.yml
│   ├── *.qmd
│   ├── js/  css/  vendor/
│   └── data/                     (gitignored) bundle local para preview
└── docs/
    ├── visao_inicial.md
    ├── arquitetura.md            este documento
    ├── web_data_contract.md
    └── metodologia.md            fonte da página de metodologia
```

---

## 11. O que vem do DudesApp e o que muda

| Aspecto | DudesApp | Observatório | Motivo |
|---------|----------|--------------|--------|
| Fronteira analítica | R calcula, browser apresenta | **igual** | separa complexidade de interface |
| Bundle | presentation marts + `manifest.json` | **igual**, com `elections[]` e `data_base_url` | multi-eleição e plano de dados separado |
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
| ADR-09 | `result_class` obrigatório em todo número publicado | separar só por página/aba | a distinção observado/limite/estimado é a tese metodológica do projeto | — |
| ADR-10 | Quarentena por município em vez de falha global para problemas de dados | `stop()` em qualquer inconsistência | cobertura nacional tolerante a falhas (visão §11) | — |

---

## 13. Evolução por etapas

Cada etapa da visão (§11) entrega uma fatia vertical: pipeline, bundle e tela.

| Etapa | Arquitetura entregue | Critério de pronto |
|-------|----------------------|--------------------|
| **1. Reproduzir Lebon Régis** | Bronze (BUs de SC), Silver com harmonização, `reconcile/`, `accounting/`, `R/web` mínimo, `municipio.qmd` com Resumo e Seções; bundle dentro de `_site/`. Em paralelo, 2022 completo como teste de dois turnos | fixture-ouro passa; resíduo zero nas 30 seções; totais batem com o TSE |
| **2. Motor ecológico** | `ecological/` (LP, modelo, cenários, incerteza), `diagnostics/`, `assumptions.yml`, abas Fluxos, Cenários e Qualidade, página de metodologia | três métodos publicados lado a lado, com `result_class`, intervalos e diagnósticos |
| **3. Generalizar para o Brasil** | `targets` por UF + `crew`, quarentena, particionamento por UF, spike de Range (ADR-04), plano de dados separado (ADR-05), catálogo nacional | release nacional de 2022 válida; cobertura e quarentenas reportadas no manifest |
| **4. Publicar o site** | busca, comparação entre municípios, contexto estatístico, downloads da Gold, deploy com troca de manifest | release de 2026 publicada; rollback testado |

---

## 14. Riscos e questões em aberto

- **Disponibilidade do 2º turno no TSE** (visão, §5). Mitigação: adaptador de coleta individual e
  2022 como base de desenvolvimento.
- **Harmonização entre turnos** (seções agregadas, voto em trânsito, variação de aptos). É o maior
  risco de engenharia; a regra de tratamento precisa estar escrita antes da etapa 2.
- **Custo computacional do modelo hierárquico nacional.** Falta medir quanto tempo leva por UF;
  pode exigir pooling por UF em vez de nacional, ou um método variacional na primeira release.
- **Limites dos hosts.** Número de arquivos por deploy, tamanho máximo de arquivo e suporte a Range
  variam por plano e mudam com o tempo; confirmar antes da fase 3.
- **Peso inicial no celular.** DuckDB-Wasm + Plotly somam vários MB; medir na fase 4 e decidir
  entre vendor, build parcial do Plotly ou adiar o DuckDB para a primeira interação.
- **SEO e prévia de link por município.** Uma página única renderizada no cliente não gera
  `og:title` por município. Opção: pré-gerar páginas mínimas por município só com metadados (5,6
  mil HTMLs pequenos), a decidir na fase 4.
- **Exterior (UF `ZZ`)**: incluir ou não, e como apresentar.
- **Sensibilidade política.** A arquitetura reduz o risco de leitura errada (classes, hipóteses,
  proveniência sempre visíveis), mas o texto da interface e da metodologia precisa de revisão
  editorial própria, fora do escopo deste documento.
