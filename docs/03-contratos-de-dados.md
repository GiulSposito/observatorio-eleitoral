# Caderno Eleitoral — Contratos de dados R → site estático

**Versão do contrato:** `1.2.0` · **Compatibilidade:** verificada no build, nunca presumida.
**Objetivo:** especificar os produtos publicados pelo pipeline em R e consumidos pelo site estático
(Quarto + ES modules + DuckDB-Wasm; ver `arquitetura.md`). A versão legível por máquina está em
`contract/` (JSON Schema dos arquivos JSON e `marts.yml` para os Parquets); as duas mudam juntas.

## 1. Princípios de engenharia

1. **R é o produtor de verdade**: o frontend não estima migrações, não ajusta fluxos e não corrige inconsistências.
2. **Releases imutáveis**: `release_id` e hashes identificam exatamente os artefatos publicados.
3. **Versionamento explícito**: contrato semântico `major.minor.patch`; mudança incompatível exige `major` novo. O frontend recusa `major` desconhecido.
4. **IDs eleitorais são strings**: códigos de município TSE e IBGE são identificadores distintos; preservar zeros à esquerda; não inferir correspondência por igualdade numérica.
5. **Ausente != zero**: dados faltantes ou inadequados são `null`/status, nunca preenchidos automaticamente com `0`.
6. **Classe de evidência explícita**: cada arquivo declara sua classe (§11); onde um arquivo mistura classes (`fluxos_estimados.parquet`), cada linha tem `identification_class` e as colunas de limite e de estimativa são separadas.
7. **Rastreabilidade**: cada tela associa método, eleição, recorte, cobertura e origem oficial.
8. **Nenhum arquivo de demonstração é dado oficial**: `release_id` `DEMO-*` ou `municipio_tse` `00000` falham na validação de uma release de produção.

## 2. Vocabulário fixo

| Termo | Valor |
|---|---|
| `election_id` | `2026-presidente` |
| `release_id` | `<election_id>-<AAAAMMDDTHHMMSSZ>` (UTC), por exemplo `2026-presidente-20261027T180000Z`; fixtures usam `DEMO-001` |
| Slots | `A` e `B`. **Regra nacional:** `A` é o finalista com o menor número de urna (2026: 13 = A, 22 = B). A regra e o mapeamento ficam no catálogo; cores e posições seguem o slot em todas as telas |
| Categorias de origem (1º turno) | `A`, `B`, `O` (demais candidatos), `I` (brancos + nulos), `X` (abstenção), `N` (entrada líquida de aptos) |
| Categorias de destino (2º turno) | `A`, `B`, `I`, `X`, `S` (saída líquida de aptos) |
| Versões | `schema_version` (este contrato), `release_id`, `pipeline_git_sha` (commit do pipeline), `method_version` (`05-metodo-analitico.md`, com os parâmetros de `config/metodo.yml`), `app_version` (só no site) |
| Status de feature | `ready | partial | insufficient_data | failed | unavailable` |
| `validation_status` | `passed` (V1 e V3 sem falha não explicada) · `partial` (alguma seção com falha de V1, ou divergência explicada em V3) · `failed` (divergência não explicada em V3) |
| `publication_status` (catálogo) | `ready` (`validation_status = passed`) · `partial` · `unavailable` |

## 3. Layout físico publicado

```text
data/
├── latest.json
└── releases/<release_id>/
    ├── catalogo.json
    ├── metodo.json
    └── 2026-presidente/
        ├── municipios/<UF>/<municipio_tse>/
        │   ├── manifest.json
        │   ├── resumo.json
        │   └── qualidade.json
        └── uf=<UF>/
            ├── secoes.parquet
            ├── limites.parquet
            ├── cenarios.parquet
            └── fluxos_estimados.parquet
```

- `latest.json` pode mudar; **todo o restante da release é imutável**.
- **Todo caminho dentro de manifestos e do catálogo é relativo à base da release** (`releases/<release_id>/`). O frontend nunca concatena texto vindo da URL do usuário.
- JSON por município serve à navegação e ao *first paint*; Parquet por UF (ADR-04) serve ao detalhe. Os Parquets são ordenados por `municipio_tse, zona, secao` (ou `origin, destination`) com row groups pequenos; o frontend filtra sempre por `municipio_tse`.
- Exterior (UF `ZZ`) não é publicado.

## 4. `latest.json`

```json
{
  "schema_version": "1.2.0",
  "release_id": "2026-presidente-20261027T180000Z",
  "published_at": "2026-10-27T18:00:00Z",
  "release_base": "releases/2026-presidente-20261027T180000Z/",
  "catalog_url": "releases/2026-presidente-20261027T180000Z/catalogo.json",
  "pipeline_git_sha": "0123456789abcdef0123456789abcdef01234567",
  "method_version": "metodo-1.0.0"
}
```

Os caminhos de `latest.json` são relativos à raiz `data/`.

## 5. `catalogo.json`

```json
{
  "schema_version": "1.2.0",
  "release_id": "2026-presidente-20261027T180000Z",
  "generated_at": "2026-10-27T18:00:00Z",
  "election": {
    "election_id": "2026-presidente",
    "year": 2026,
    "office": "presidente",
    "label": "Presidência · 2026 · 1º × 2º turno",
    "rounds": [
      {"round": 1, "date": "2026-10-04"},
      {"round": 2, "date": "2026-10-25"}
    ],
    "slot_rule": "lowest_ballot_number",
    "finalists": [
      {"slot": "A", "number": "13", "name": "NOME DO FINALISTA A"},
      {"slot": "B", "number": "22", "name": "NOME DO FINALISTA B"}
    ]
  },
  "municipalities": [
    {
      "municipio_tse": "00000",
      "municipio_ibge": null,
      "name": "NOME OFICIAL",
      "display_name": "Nome Oficial",
      "uf": "GO",
      "n_sections": 34,
      "manifest_url": "2026-presidente/municipios/GO/00000/manifest.json",
      "publication_status": "ready"
    }
  ]
}
```

- `name` é o nome oficial do TSE; `display_name` é a versão em caixa mista gerada no pipeline (preposições `de`, `da`, `do`, `das`, `dos`, `e` em minúsculas).
- `municipio_ibge` é `null` enquanto não houver tabela oficial de correspondência versionada; nunca é inferido.
- Município `unavailable` aparece na busca, mas não exibe métricas.

## 6. `manifest.json` (por município)

```json
{
  "schema_version": "1.2.0",
  "release_id": "2026-presidente-20261027T180000Z",
  "election_id": "2026-presidente",
  "municipio_tse": "00000",
  "uf": "GO",
  "name": "NOME OFICIAL",
  "generated_at": "2026-10-27T18:00:00Z",
  "validation_status": "passed",
  "features": {
    "summary": "ready",
    "sections": "ready",
    "bounds": "ready",
    "scenarios": "ready",
    "ecological_model": "partial"
  },
  "assets": {
    "summary":  {"path": "2026-presidente/municipios/GO/00000/resumo.json", "media_type": "application/json", "sha256": "<64 hex>", "bytes": 1820},
    "quality":  {"path": "2026-presidente/municipios/GO/00000/qualidade.json", "media_type": "application/json", "sha256": "<64 hex>", "bytes": 4110},
    "sections": {"path": "2026-presidente/uf=GO/secoes.parquet", "media_type": "application/vnd.apache.parquet", "sha256": "<64 hex>", "bytes": 912345},
    "bounds":   {"path": "2026-presidente/uf=GO/limites.parquet", "media_type": "application/vnd.apache.parquet", "sha256": "<64 hex>", "bytes": 45678},
    "scenarios":{"path": "2026-presidente/uf=GO/cenarios.parquet", "media_type": "application/vnd.apache.parquet", "sha256": "<64 hex>", "bytes": 3456},
    "flows":    {"path": "2026-presidente/uf=GO/fluxos_estimados.parquet", "media_type": "application/vnd.apache.parquet", "sha256": "<64 hex>", "bytes": 56789}
  },
  "sources": [
    {"provider": "TSE", "dataset": "Votação por seção eleitoral 2026", "file": "votacao_secao_2026_BR.zip",
     "source_url": "https://cdn.tse.jus.br/estatistica/sead/odsele/votacao_secao/votacao_secao_2026_BR.zip",
     "collected_at": "2026-10-27T12:00:00Z", "source_sha256": "<64 hex>", "bytes": 241891087}
  ],
  "pipeline_git_sha": "0123456789abcdef0123456789abcdef01234567",
  "method_version": "metodo-1.0.0"
}
```

### Invariantes

- `assets` só lista arquivos publicados; uma feature `ready` ou `partial` exige o asset correspondente (`summary`→`summary`, `sections`→`sections`, `bounds`→`bounds`, `scenarios`→`scenarios`, `ecological_model`→`flows`).
- O `sha256` de um Parquet por UF é o hash do arquivo da UF, repetido nos manifestos dos municípios dela.
- `features.ecological_model` segue `05-metodo-analitico.md` §5.7: `ready` permite Sankey; `partial` publica só a tabela; `insufficient_data` e `failed` publicam só limites (o município não tem linhas em `fluxos_estimados.parquet`).
- `resumo.status` é igual a `features.summary`, e `qualidade.model.status` é igual a `features.ecological_model`.
- Com `validation_status = failed`, o frontend exibe advertência e mostra só dados observados por seção.

## 7. `resumo.json` — fast path

```json
{
  "schema_version": "1.2.0",
  "release_id": "2026-presidente-20261027T180000Z",
  "election_id": "2026-presidente",
  "status": "ready",
  "validation_status": "passed",
  "location": {"municipio_tse": "00000", "uf": "GO", "name": "CIDADE EXEMPLO", "display_name": "Cidade Exemplo"},
  "finalists": [
    {"slot": "A", "number": "13", "name": "NOME DO FINALISTA A", "round_1_votes": 3120, "round_2_votes": 3655, "delta_votes": 535},
    {"slot": "B", "number": "22", "name": "NOME DO FINALISTA B", "round_1_votes": 2780, "round_2_votes": 3101, "delta_votes": 321}
  ],
  "totals": {
    "round_1": {"eligible": 8450, "turnout": 6610, "abstention": 1840, "valid": 6312, "other": 412, "blank": 120, "null": 178, "invalid": 298},
    "round_2": {"eligible": 8450, "turnout": 6838, "abstention": 1612, "valid": 6756, "other": 0, "blank": 30, "null": 52, "invalid": 82}
  },
  "accounting": {
    "other_round_1": 412,
    "delta_turnout": 228,
    "delta_invalid": -216,
    "delta_valid": 444,
    "delta_finalists": 856,
    "identity_residual": 0,
    "scope": "all_sections",
    "evidence_type": "observed"
  },
  "coverage": {
    "sections_total": 34,
    "sections_installed": 34,
    "units_in_transition_analysis": 34,
    "eligible_share_used": 1.0
  },
  "display_notes": []
}
```

- Valores ilustrativos e sintéticos. Conferência: `412 + 228 − (−216) = 856`; `6756 − 6312 = 444`.
- `accounting` é aritmética dentro de cada turno (05 §2); nunca verificação entre turnos.
- `totals` somam **todas** as seções instaladas do município; `coverage` diz quantas entram na análise de transição.

## 8. `secoes.parquet` (por UF) — fatos por seção

Uma linha por unidade de comparação (05 §1). Classe: `observed`.

| Coluna | Tipo | Regra |
|---|---|---|
| `election_id`, `uf`, `municipio_tse` | STRING | Chave |
| `zona`, `secao` | STRING | Zeros à esquerda preservados |
| `comparison_unit_id` | STRING | `<municipio_tse>-<zona>-<secao>`; único por UF |
| `unit_type` | STRING | `section | aggregated_sections` |
| `comparison_status` | STRING | `matched | aggregated | unmatched` |
| `section_type` | STRING | `regular | transit | special | unknown` (05 §3.1) |
| `polling_place_id`, `polling_place_name` | STRING nullable | Local de votação no 1º turno |
| `location_changed` | BOOLEAN nullable | V2.5 |
| `integrity_status` | STRING | `passed | failed` (V1 nos dois turnos) |
| `installed` | BOOLEAN | Seção instalada nos dois turnos |
| `eligible_t1`, `eligible_t2` | INT32 nullable | Aptos |
| `turnout_t1`, `turnout_t2` | INT32 nullable | Comparecimento |
| `abstention_t1`, `abstention_t2` | INT32 nullable | Abstenção |
| `candidate_a_t1`, `candidate_a_t2`, `candidate_b_t1`, `candidate_b_t2` | INT32 nullable | Votos dos finalistas |
| `others_t1` | INT32 nullable | Demais candidatos no 1º turno |
| `blank_t1`, `null_t1`, `blank_t2`, `null_t2` | INT32 nullable | Brancos e nulos |
| `invalid_t1`, `invalid_t2` | INT32 nullable | Brancos + nulos |
| `delta_turnout`, `delta_a`, `delta_b`, `delta_invalid` | INT32 nullable | T2 − T1; null fora de unidades `matched` |
| `eligible_net_change` | INT32 nullable | `eligible_t2 − eligible_t1` |
| `population_status` | STRING nullable | `closed | net_change | excluded_population` (05 §3.2) |
| `in_transition_analysis` | BOOLEAN | Entra em limites e estimação |
| `exclusion_reason` | STRING nullable | `not_installed | integrity_failed | unmatched | transit_section | special_section | population_change_above_tau | possible_aggregation`; null quando `in_transition_analysis` |

- Contagens absolutas nunca negativas; deltas podem ser.
- Seções não instaladas aparecem com contagens `null` e `exclusion_reason = not_installed`.

## 9. `limites.parquet` (por UF) — limites de viabilidade

Uma linha por município × cenário × origem × destino. Classe: `conditional_bound`.

| Coluna | Tipo | Regra |
|---|---|---|
| `election_id`, `uf`, `municipio_tse` | STRING | Chave |
| `scenario_id` | STRING | `base` (Fréchet sem restrição extra) ou id de `config/assumptions.yml` |
| `assumption_id` | STRING | Hipóteses combinadas, separadas por `+` (sempre inclui `pop-liquida-minima`) |
| `origin`, `destination` | STRING | Categorias do §2 |
| `min_votes`, `max_votes` | INT64 nullable | Somas dos limites por unidade; null se `status != feasible` |
| `status` | STRING | `feasible | infeasible | insufficient_data` |
| `units_used`, `units_infeasible` | INT32 | Unidades usadas e inviáveis no cenário |
| `eligible_share_used` | DOUBLE | Aptos do 1º turno nas unidades usadas ÷ aptos do município |
| `method_id`, `method_version` | STRING | `frechet` ou `transport-lp`; `method_version` |

Os limites de células diferentes não formam uma matriz simultaneamente viável: nunca alimentam um Sankey.

## 10. `cenarios.parquet` (por UF)

Uma linha por município × cenário. Classe: `conditional_bound`. Rótulos e descrições ficam em `metodo.json`.

| Coluna | Tipo | Regra |
|---|---|---|
| `election_id`, `uf`, `municipio_tse` | STRING | Chave |
| `scenario_id`, `assumption_id` | STRING | Como em `limites.parquet` |
| `status` | STRING | `feasible | infeasible | insufficient_data` |
| `units_used`, `units_infeasible` | INT32 | |

## 11. `fluxos_estimados.parquet` (por UF) — estimação ecológica

Uma linha por município × origem × destino, só para municípios com `features.ecological_model` em `ready` ou `partial`.

| Coluna | Tipo | Regra |
|---|---|---|
| `election_id`, `uf`, `municipio_tse` | STRING | Chave |
| `origin`, `destination` | STRING | Categorias do §2 |
| `model_id`, `model_version` | STRING | `md-bayes`, versão |
| `assumption_id` | STRING | `homogeneidade-municipal+pop-liquida-minima` |
| `estimate_votes` | DOUBLE | Média posterior das contagens (`model_estimate`) |
| `estimate_statistic` | STRING | Sempre `posterior_mean` |
| `interval_low`, `interval_high` | DOUBLE | Intervalo de credibilidade |
| `interval_type`, `interval_level` | STRING, DOUBLE | `credible_interval`, `0.95` |
| `method_range_low`, `method_range_high` | DOUBLE nullable | Menor e maior estimativa pontual entre os métodos |
| `bounds_min`, `bounds_max` | DOUBLE | Limites `base` (`conditional_bound`) |
| `identification_ratio` | DOUBLE nullable | `R` de 05 §5.4; null quando `W = 0` |
| `identification_class` | STRING | `determined | estimated | weak | not_identified` |
| `model_status` | STRING | `ready | partial` |

- A soma de `estimate_votes` por origem fecha a margem da origem dentro da tolerância de ponto flutuante.
- Sankey só com `features.ecological_model = ready`, usando apenas células `determined` e `estimated`.

## 12. `qualidade.json` (por município)

```json
{
  "schema_version": "1.2.0",
  "release_id": "2026-presidente-20261027T180000Z",
  "election_id": "2026-presidente",
  "municipio_tse": "00000",
  "computed_at": "2026-10-27T18:00:00Z",
  "pipeline_git_sha": "0123456789abcdef0123456789abcdef01234567",
  "method_version": "metodo-1.0.0",
  "validation_status": "passed",
  "section_coverage": {
    "sections_total": 34, "sections_installed": 34, "units_paired": 34,
    "units_in_transition_analysis": 34, "eligible_share_used": 1.0,
    "excluded_by_reason": {}, "net_change_tolerance_rule": "max(2, 1% de E1)"
  },
  "population": {"closed": 31, "net_change": 3, "excluded_population": 0},
  "checks": [
    {"id": "integrity.turnout_equals_votes", "family": "integrity", "passed": true, "scope": "sections", "count_failed": 0},
    {"id": "harmonization.pairing_one_to_one", "family": "harmonization", "passed": true, "scope": "units", "count_failed": 0},
    {"id": "official_totals.round_1", "family": "official_totals", "passed": true, "scope": "municipality", "count_failed": 0, "explanation_code": null}
  ],
  "model": {
    "status": "partial",
    "reason_unavailable": null,
    "methods": [
      {"method_id": "md-bayes", "version": "eiPack-0.2-2", "status": "ok", "runtime_s": 12.4, "diagnostics": {"rhat_max": 1.004, "ess_min": 812}},
      {"method_id": "lphom", "version": "lphom-0.3.5-7", "status": "ok", "runtime_s": 0.3, "diagnostics": {}}
    ],
    "predictive_check": {"k_folds": 5, "model_error": 0.061, "null_error": 0.072, "passed": true},
    "identified_change_share": 0.64,
    "n_units_used": 34,
    "calibration_id": "cal-2026-presidente-001"
  }
}
```

`checks[].id` usa o prefixo da família: `integrity.*` (V1), `harmonization.*` (V2), `official_totals.*` (V3). Divergência explicada traz `explanation_code`.

## 13. `metodo.json` (por release)

Conteúdo da página de metodologia e da aba Qualidade que não depende do município:

- `method_version`, `parameters` (cópia de `config/metodo.yml` depois da calibração);
- `categories` (código, rótulo pt-BR, turno);
- `assumptions` e `scenarios` (`id`, `label_ptbr`, `description_ptbr`);
- `calibration` (`calibration_id`, `status`, `target_coverage`, resultados por processo, porte e classe, decisão);
- `national_summary` (municípios por `publication_status` e por `features.ecological_model`; distribuição de `eligible_net_change`).

## 14. Classes de evidência

| Categoria | Semântica | Onde |
|---|---|---|
| `observed` | Dados do TSE ou derivações algébricas determinísticas | `resumo.json`, `secoes.parquet` |
| `conditional_bound` | Faixa viável sob restrições declaradas | `limites.parquet`, `cenarios.parquet`, colunas `bounds_*` |
| `model_estimate` | Estimação estatística RxC | colunas `estimate_*`, `interval_*`, `method_range_*` |
| `unavailable` | Sem dados ou qualidade suficiente | status; nunca placeholder numérico |

## 15. Testes de contrato mínimos

1. JSON contra os JSON Schema de `contract/`; colunas e tipos dos Parquets contra `contract/marts.yml`, com DuckDB.
2. `schema_version` igual em `latest`, `catalogo`, `manifest`, `resumo`, `qualidade` e `metodo`; `release_id` igual em todos.
3. Chaves `municipio_tse` + `election_id` coerentes entre catálogo, manifesto e arquivos; todo caminho de asset existe e tem o `sha256` e `bytes` declarados.
4. `valid = A + B + others` no 1º turno e `valid = A + B` no 2º.
5. V1 por seção e turno; V2 (pareamento 1:1; `population_status` coerente com `eligible_net_change` e `τ`; `in_transition_analysis` só para `regular` com `closed` ou `net_change`).
6. A identidade contábil é recalculada só para exibição; nenhum teste a usa como verificação entre turnos.
7. Dados faltantes, zeros à esquerda, homônimos, seção não instalada, universo variável e modelo não convergido.
8. `min_votes ≤ max_votes`; `interval_low ≤ estimate_votes ≤ interval_high`; `bounds_min ≤ estimate_votes ≤ bounds_max`.
9. `fluxos_estimados`: `estimate_statistic = posterior_mean`; soma por origem igual à margem; só municípios com `ecological_model` em `ready` ou `partial`.
10. Nenhum `DEMO-*` ou `00000` em release de produção.
11. Segurança: nenhum caminho absoluto ou URL externa em manifestos; SQL do frontend só parametrizado.

## 16. Contrato de publicação e fallback

- Publicação atômica: gerar `data/releases/<id>/` em staging, validar e só então escrever `latest.json`.
- Falha de Wasm não invalida a página: `resumo.json`, qualidade e downloads continuam disponíveis.
- Falha de download de um Parquet só desabilita a aba que o usa.
- Mudança de município cancela ou ignora requisições anteriores.

## 17. Histórico

- `1.2.0` (27/10/2026): vocabulário unificado (`election_id`, `release_id`, slots `A`/`B` com regra nacional, categorias, versões); layout com JSON por município e Parquet por UF; `latest.release_base`; `catalogo.election` único com finalistas; `blank`/`null` separados; `cenarios.parquet` e `metodo.json` especificados; aba Horários e `horarios.parquet` removidos do escopo.
- `1.1.0` (27/10/2026): campos de verificação, tipo de seção e população; pseudo-categorias; classe de identificação; `posterior_mean` obrigatório.
- `1.0.0`: versão inicial.

## 18. Referências

- Portal de Dados Abertos do TSE: https://dadosabertos.tse.jus.br/
- Votação por seção (2026): https://cdn.tse.jus.br/estatistica/sead/odsele/votacao_secao/votacao_secao_2026_BR.zip
- Detalhe da votação por seção (2026): https://cdn.tse.jus.br/estatistica/sead/odsele/detalhe_votacao_secao/detalhe_votacao_secao_2026.zip
- DuckDB-Wasm, ingestão de dados: https://duckdb.org/docs/current/clients/wasm/data_ingestion
- DuckDB R: https://duckdb.org/docs/stable/clients/r
- Quarto websites: https://quarto.org/docs/websites/
