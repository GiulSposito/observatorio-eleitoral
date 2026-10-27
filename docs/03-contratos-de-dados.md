# Caderno Eleitoral — Contratos de dados R → site estático

**Versão do contrato:** `1.1.0` · **Compatibilidade:** verificada no build, nunca presumida.  
**Objetivo:** especificar os produtos publicados pelo pipeline em R e consumidos pelo site estático (Quarto + ES modules + DuckDB-Wasm; ver `arquitetura.md`).

## 1. Princípios de engenharia

1. **R é o produtor de verdade**: o frontend não estima migrações, não ajusta fluxos e não corrige inconsistências.
2. **Releases imutáveis**: `release_id` e hashes identificam exatamente os artefatos publicados.
3. **Versionamento explícito**: contrato semântico `major.minor.patch`; mudança incompatível exige `major` novo.
4. **IDs eleitorais são strings**: códigos de município TSE e IBGE são identificadores distintos; preservar zeros à esquerda; não inferir correspondência por igualdade numérica.
5. **Ausente != zero**: dados faltantes ou inadequados são `null`/status, nunca preenchidos automaticamente com `0`.
6. **Dados observados != inferência**: todas as métricas têm `evidence_type` ou pertencem a um arquivo de evidência claramente identificado.
7. **Apresentar rastreabilidade**: cada tela associa método, eleição, recorte, cobertura e origem oficial.
8. **Nenhum arquivo de preview é dado oficial**: conteúdo `DEMO-*` deve falhar na validação de um release de produção.

## 2. Layout físico publicado

```text
public/data/
├── latest.json
├── releases/
│   └── 2026-10-27_r001/
│       ├── catalogo.json
│       └── elections/
│           └── 2026-presidente-2t/
│               ├── models.json
│               ├── GO/
│               │   └── 00000/                 # Código ilustrativo
│               │       ├── manifest.json
│               │       ├── resumo.json
│               │       ├── qualidade.json
│               │       ├── secoes.parquet
│               │       ├── limites.parquet
│               │       ├── cenarios.parquet
│               │       ├── fluxos_estimados.parquet  # Opcional
│               │       └── horarios.parquet          # Opcional
│               └── ...
└── ...
```

- `latest.json` pode mudar; **todo o restante do release é imutável** e recebe `Cache-Control: public, max-age=31536000, immutable` quando seguro.
- URLs retornadas pelos manifestos são **relativas à base de release** ou URLs HTTP(S) autorizadas por configuração; não concatenar texto de query string diretamente.
- O produtor decide o empacotamento físico (arquivos por município ou por grupo). O **manifesto** abstrai isso: o frontend lê os caminhos que ele contém. Para milhares de arquivos pequenos, reavaliar agrupamento por UF e centralizar metadados (proposta em `arquitetura.md`, ADR-04). Não tornar o layout físico um contrato lógico rígido.
- JSON é destinado à navegação e ao *first paint*; Parquet ao detalhe tabular e consultas; o cliente não baixa Parquet de todos os municípios.

## 3. `latest.json`

```json
{
  "schema_version": "1.1.0",
  "release_id": "2026-10-27_r001",
  "published_at": "2026-10-27T18:00:00Z",
  "catalog_url": "releases/2026-10-27_r001/catalogo.json",
  "pipeline_git_sha": "0123456789abcdef0123456789abcdef01234567"
}
```

O frontend resolve o catálogo e o manifesto a partir deste ponteiro. Nunca armazenar o release ID em constante hardcoded nas telas.

## 4. `catalogo.json`

```json
{
  "schema_version": "1.1.0",
  "release_id": "2026-10-27_r001",
  "elections": [{
    "election_id": "2026-presidente-2t",
    "year": 2026,
    "office": "presidente",
    "rounds": [1, 2],
    "label": "Presidência · 2026 · Comparação entre turnos",
    "finalist_slots": ["candidate_a", "candidate_b"]
  }],
  "municipalities": [{
    "municipio_tse": "00000",
    "municipio_ibge": "0000000",
    "name": "NOME OFICIAL",
    "uf": "GO",
    "election_ids": ["2026-presidente-2t"],
    "manifest_url": "elections/2026-presidente-2t/GO/00000/manifest.json",
    "publication_status": "ready"
  }]
}
```

- `municipio_tse` e `municipio_ibge` são dois campos independentes; o exemplo usa IDs fictícios.
- `publication_status`: `ready | partial | unavailable`. Município indisponível pode existir no catálogo para orientar a navegação, mas não deve exibir métricas.
- Para o Brasil inteiro, avaliar índice por UF se a transferência e o parse do JSON aumentarem; os esquemas lógicos são mantidos.

## 5. `manifest.json` (por município)

```json
{
  "schema_version": "1.1.0",
  "release_id": "2026-10-27_r001",
  "election_id": "2026-presidente-2t",
  "municipio_tse": "00000",
  "uf": "GO",
  "published_at": "2026-10-27T18:00:00Z",
  "sections_expected": 34,
  "sections_comparable": 34,
  "coverage_fraction": 1.0,
  "validation_status": "passed",
  "features": {
    "summary": "ready",
    "sections": "ready",
    "bounds": "ready",
    "scenarios": "ready",
    "ecological_model": "unavailable",
    "vote_logs": "unavailable"
  },
  "assets": {
    "summary": {"path": "resumo.json", "media_type": "application/json", "sha256": "<64_hex>"},
    "quality": {"path": "qualidade.json", "media_type": "application/json", "sha256": "<64_hex>"},
    "sections": {"path": "secoes.parquet", "media_type": "application/vnd.apache.parquet", "sha256": "<64_hex>"},
    "bounds": {"path": "limites.parquet", "media_type": "application/vnd.apache.parquet", "sha256": "<64_hex>"}
  },
  "sources": [{
    "provider": "TSE",
    "dataset": "Resultados por seção",
    "source_url": "https://dadosabertos.tse.jus.br/",
    "collected_at": "2026-10-27T12:00:00Z",
    "source_sha256": "<64_hex>"
  }],
  "pipeline_version": "0.1.0",
  "method_version": "accounting-1.0.0"
}
```

Amostra de estrutura; hashes fictícios entre `<>` não são válidos. No pipeline real, preencher `sha256` com hexadecimal completo e conferir sua integridade. `assets` só lista artefatos realmente publicados. Um `feature` pode estar `ready | partial | insufficient_data | failed | unavailable`.

### Invariantes

- `sections_comparable <= sections_expected` e `0 <= coverage_fraction <= 1`.
- `features.summary == ready` implica `assets.summary` existente e status de reconciliação aprovado ou parcial declarado.
- `features.ecological_model` segue `05-metodo-analitico.md` §5.7: `ready` permite Sankey; `partial` publica só a tabela; `insufficient_data` e `failed` publicam só limites. `ready` e `partial` exigem `assets.ecological_model` (`fluxos_estimados.parquet`) e `quality.model.status` igual a `features.ecological_model`.
- `features.vote_logs == unavailable` implica **não mostrar aba Horários**.
- Em `validation_status != passed`, o frontend deve exibir advertência e bloquear análises sensíveis.

## 6. `resumo.json` — fast path

```json
{
  "schema_version": "1.1.0",
  "release_id": "2026-10-27_r001",
  "election_id": "2026-presidente-2t",
  "status": "ready",
  "location": {"name": "CIDADE EXEMPLO", "uf": "GO", "municipio_tse": "00000"},
  "finalists": [
    {"slot": "candidate_a", "candidate_id": "A", "name": "Candidato A", "round_1_votes": 3120, "round_2_votes": 3655, "delta_votes": 535},
    {"slot": "candidate_b", "candidate_id": "B", "name": "Candidato B", "round_1_votes": 2780, "round_2_votes": 3101, "delta_votes": 321}
  ],
  "totals": {
    "round_1": {"eligible": 8450, "turnout": 6610, "abstention": 1840, "valid": 6312, "other": 412, "invalid": 298},
    "round_2": {"eligible": 8450, "turnout": 6838, "abstention": 1612, "valid": 6756, "other": 0, "invalid": 82}
  },
  "reconciliation": {
    "delta_turnout": 228,
    "delta_invalid": -216,
    "delta_valid": 444,
    "delta_finalists": 856,
    "identity_residual": 0,
    "scope": "comparable_sections",
    "evidence_type": "observed"
  },
  "coverage": {"expected_sections": 34, "comparable_sections": 34, "fraction": 1.0},
  "display_notes": ["Dados de demonstração, não oficiais."]
}
```

**Atenção:** todos os valores acima são **sintéticos/ilustrativos**, usados apenas para documentar o schema. A título de teste, `other_1 + delta_turnout - delta_invalid = 412 + 228 - (-216) = 856`; `delta_valid = 6756 - 6312 = 444`. O dado de exemplo nunca pode ser publicado como resultado oficial. Implementar `fixtures_only: true` em configurações locais e falhar build de produção se algum `municipio_tse` for `00000`, `DEMO-*` ou houver `display_notes` que informem dados fictícios.

A soma correta é:

`delta_finalists = other_round_1 + (turnout_2 - turnout_1) - (invalid_2 - invalid_1)`.

A identidade é contábil e **não** demonstra trajetórias individuais.

## 7. `secoes.parquet` — fatos normalizados e métricas

**Granularidade:** uma linha por unidade de comparação para um município/eleição. A unidade pode representar uma seção ou conjunto de seções harmonizadas; declarar `unit_type`.

| Coluna | Tipo lógico Parquet | Regra |
|---|---|---|
| `election_id` | STRING | Igual ao manifesto |
| `municipio_tse` | STRING | Igual ao manifesto |
| `uf` | STRING | UF do cadastro oficial |
| `zona` | STRING | Preservar zeros à esquerda |
| `secao` | STRING | Preservar zeros; se unidade agregada, ID derivado explícito |
| `comparison_unit_id` | STRING | Único no conjunto por eleição/município |
| `unit_type` | STRING | `section | aggregated_sections` |
| `comparison_status` | STRING | `matched | aggregated | unmatched` (05 §2.2) |
| `eligible_t1`, `eligible_t2` | INT64 nullable | Nunca impute zero |
| `turnout_t1`, `turnout_t2` | INT64 nullable | Votantes |
| `abstention_t1`, `abstention_t2` | INT64 nullable | Elegíveis - votantes |
| `candidate_a_t1`, `candidate_a_t2` | INT64 nullable | Votos do finalista A |
| `candidate_b_t1`, `candidate_b_t2` | INT64 nullable | Votos do finalista B |
| `others_t1` | INT64 nullable | Outros candidatos no 1º turno |
| `invalid_t1`, `invalid_t2` | INT64 nullable | Brancos + nulos |
| `delta_turnout`, `delta_a`, `delta_b`, `delta_invalid` | INT64 nullable | T2 - T1 somente em unidades comparáveis |
| `polling_place_id`, `polling_place_name` | STRING nullable | Dados oficiais, quando presentes |
| `section_type` | STRING | `regular | transit | special` (05 §3.1) |
| `integrity_status` | STRING | `passed | failed` — V1 nos dois turnos (05 §2.1) |
| `population_status` | STRING nullable | `closed | net_change | excluded_population` (05 §3.2); null se a unidade não foi pareada |
| `eligible_net_change` | INT64 nullable | `eligible_t2 - eligible_t1` |
| `location_changed` | BOOLEAN nullable | Local de votação diferente entre turnos (V2.5) |
| `in_transition_analysis` | BOOLEAN | Entra nos limites e na estimação |
| `exclusion_reason` | STRING nullable | Código da exclusão (05 §2.2); null quando `in_transition_analysis` |

- Duas linhas com mesma `comparison_unit_id` constituem erro de ingestão.
- Unidades com `in_transition_analysis = false` continuam nos gráficos de resultados observados, mas não entram em limites nem em estimação (05 §2–3).
- Qualquer linha não comparável deve deixar `delta_*` como `null`, não zero.
- Valores negativos só são permitidos nos deltas, nunca em votos/eleitores absolutos.

## 8. `limites.parquet` — limites de viabilidade

**Granularidade:** município × eleição × cenário/hipótese × origem × destino, com limites calculados a partir de restrições por unidade quando for o caso.

| Campo | Tipo | Semântica |
|---|---|---|
| `election_id`, `municipio_tse` | STRING | Chave |
| `scenario_id`, `assumption_id` | STRING | Hipótese reproduzível |
| `origin`, `destination` | STRING | IDs de categorias |
| `min_votes`, `max_votes` | INT64 ou DOUBLE | Limites condicionais |
| `constraint_scope` | STRING | `municipal_margins | section_margins | constrained` |
| `status` | STRING | `feasible | infeasible | insufficient_data` |
| `method_id`, `method_version` | STRING | `transport-lp`, versão |
| `units_used` | INT64 | Unidades com `in_transition_analysis` |
| `eligible_share_used` | DOUBLE | Aptos do 1º turno nas unidades usadas ÷ aptos do município |

`origin` inclui `N` (entrada líquida) e `destination` inclui `S` (saída líquida) quando houver unidades `net_change`; `assumption_id` sempre inclui a hipótese de população `pop-liquida-minima` (05 §1, §3). Sem cenário, os limites são os de Fréchet somados por unidade (05 §4.1).

**Aviso obrigatório:** `min_votes/max_votes` de células diferentes não formam, em geral, uma única matriz simultaneamente viável. Por isso, não alimentar um Sankey com limites extremos reunidos arbitrariamente. Em casos de mudança do universo eleitoral, LP fechado não é permitido sem variáveis e hipóteses próprias de entrada/saída.

## 9. `fluxos_estimados.parquet` — estimação ecológica (posterior ao MVP factual)

| Campo | Tipo | Semântica |
|---|---|---|
| `election_id`, `municipio_tse` | STRING | Chave |
| `model_id`, `model_version`, `assumption_id` | STRING | Proveniência |
| `origin`, `destination` | STRING | Categorias de transição |
| `estimate_votes` | DOUBLE | Média posterior das contagens do método `md-bayes` |
| `estimate_statistic` | STRING | Sempre `posterior_mean` (05 §5.2) |
| `interval_low`, `interval_high` | DOUBLE | Quantis/intervalos do método |
| `interval_type` | STRING | `credible_interval` por exemplo |
| `interval_level` | DOUBLE | Ex. `0.95` |
| `model_status` | STRING | `ready | partial | failed | insufficient_data` (05 §5.7) |
| `method_range_low`, `method_range_high` | DOUBLE nullable | Menor e maior estimativa pontual entre os métodos (05 §5.2) |
| `bounds_min`, `bounds_max` | DOUBLE | Limites de Fréchet somados, sem cenário; `conditional_bound` |
| `identification_ratio` | DOUBLE nullable | `R` de 05 §5.4; null quando `W = 0` |
| `identification_class` | STRING | `determined | estimated | weak | not_identified` |
| `diagnostic_ref` | STRING | Chave no `qualidade.json` |

A matriz pontual é a média posterior das contagens e fecha as margens das unidades usadas, dentro da tolerância de ponto flutuante; mediana nunca forma matriz. Sankey só com `features.ecological_model = ready` e só com células `determined` ou `estimated` (05 §5.7). O modelo é uma hipótese estatística, não dado individual.

## 10. `qualidade.json` — evidências de integridade

Mínimos obrigatórios:

- `source_coverage`: recursos esperados/baixados/checados (com URLs e hashes).
- `section_coverage`: unidades esperadas, presentes, correspondidas, agregadas, excluídas, regra de comparação.
- `checks`: para cada asserção, `id`, `passed`, `scope`, `count_failed`, `details_url` opcional. O `id` tem o prefixo da família: `integrity.*` (V1), `harmonization.*` (V2), `official_totals.*` (V3); divergência explicada traz `explanation_code`.
- `accounting_residual`: máximo absoluto do resíduo por seção e no agregado.
- `model`: `model_id`, `model_version`, `status`, `reason_unavailable` quando apropriado, `assumptions`, `methods` (id, versão, status computacional), `diagnostics`, `predictive_check` (`k_folds`, `model_error`, `null_error`, `passed`), `identified_change_share`, `n_units_used`, `eligible_share_used`, `calibration_id` (05 §5).
- `computed_at`, `pipeline_git_sha`, `source_snapshot_id`, `schema_version`, `release_id`.

### Categorias de evidência

| Categoria | Semântica | Representação |
|---|---|---|
| `observed` | Conteúdo publicado pelo TSE ou derivações algébricas determinísticas | Número com fonte/denominador |
| `conditional_bound` | Faixa de valores viáveis sob restrições declaradas | Intervalo com hipóteses |
| `model_estimate` | Estimação estatística RxC | Ponto + intervalo + método/diagnóstico |
| `unavailable` | Não há dados ou qualidade suficiente | Mensagem clara; sem placeholder numérico |

## 11. `cenarios.parquet`

Cada cenário precisa ser **viável ou rotulado como inviável**, identificável por `scenario_id`, `assumption_id`, `description_ptbr`, `status`. Valores podem ser somas municipais ou matriz completa publicada; nunca executar estimadores Bayesianos ou otimização de grande porte no cliente no MVP.

## 12. Testes de contrato mínimos

1. Validar JSON contra JSON Schema (`jsonschema`) e colunas/tipos Parquet com DuckDB.
2. Garantir `schema_version` compatível em `latest`, `catalog`, `manifest`, `summary` e `quality`.
3. Conferir chaves `municipio_tse` + `election_id` entre catálogo, manifesto e outputs.
4. Conferir `total_valid_t1 = cand_a_t1 + cand_b_t1 + others_t1` e `total_valid_t2 = cand_a_t2 + cand_b_t2` somente para cargo/eleição com dois finalistas.
5. V1 por seção e turno (05 §2.1): `turnout = valid + invalid`, `eligible = turnout + abstention`, sem negativos. V2 (05 §2.2): pareamento 1:1; `population_status` coerente com `eligible_net_change` e `τ`; `in_transition_analysis` só para `regular` com `closed` ou `net_change`.
6. A identidade ΔA + ΔB = O₁ + ΔC − ΔI é recalculada só para exibição, com escopo declarado; nenhum teste a usa como verificação entre turnos.
7. Testar dados faltantes, códigos com zero à esquerda, homônimos de municípios, seção agregada, universo variável e modelo não convergido.
8. Validar intervalos `min <= max`, `lower <= estimate <= upper` quando se tratar de quantis apropriados, sem misturar limite LP e intervalo estatístico.
9. Verificar bytes e SHA-256 dos arquivos de release antes de publicar o ponteiro `latest.json`.
10. Teste de segurança: impedir URL remota inesperada e SQL composto a partir de entradas do usuário.
11. Garantir que fixtures `DEMO-*`/`00000` nunca entrem em release de produção.
12. `fluxos_estimados`: `estimate_statistic = posterior_mean`; soma por linha igual à margem; células `weak`/`not_identified` nunca entram no Sankey; `features.ecological_model` coerente com as regras de 05 §5.7.

## 13. Contrato de publicação e fallback

- Publicação atômica: gerar `data/releases/<id>/` em staging, validar e só então atualizar `latest.json`.
- Falha de Wasm não invalida a página: mostrar `resumo.json`, contexto de qualidade e opção de baixar dados.
- Falha de download de um Parquet não derruba resultados observados; apenas a aba que o utiliza fica `temporariamente indisponível`.
- Mudança de município cancela/ignora requisições anteriores para impedir exibição cruzada de dados.
- `Range`, CORS e `Content-Type` devem ser testados no ambiente de hospedagem escolhido; o suporte efetivo a leitura parcial depende de provedor/configuração.
- Cabeçalhos de cache e manifestos devem impedir que frontend de uma versão misture dados de outra.

## 14. Histórico

- `1.1.0` (27/10/2026): campos de verificação, tipo de seção e população em `secoes.parquet`; pseudo-categorias e cobertura em `limites.parquet`; classe de identificação, faixa entre métodos e limites em `fluxos_estimados.parquet`; `posterior_mean` obrigatório; `partial` em `model_status`; campos de checagem preditiva e calibração em `qualidade.json`. Motivo: `05-metodo-analitico.md`.
- `1.0.0`: versão inicial.

## 15. Referências

- Portal de Dados Abertos do TSE: https://dadosabertos.tse.jus.br/
- Arquivos e descrição dos resultados: https://www.tse.jus.br/eleicoes/eleicoes-2026-content/arquivos/divulgacao-de-resultados
- DuckDB-Wasm, ingestão de dados: https://duckdb.org/docs/current/clients/wasm/data_ingestion
- DuckDB R: https://duckdb.org/docs/stable/clients/r
- targets R: https://docs.ropensci.org/targets/
- Quarto websites: https://quarto.org/docs/websites/
