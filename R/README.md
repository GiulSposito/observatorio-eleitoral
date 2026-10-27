# Código R — organização e interfaces

Pipeline do Caderno Eleitoral (presidente 2026, 1º × 2º turno). O método está em
`docs/05-metodo-analitico.md`; os arquivos publicados, em `docs/03-contratos-de-dados.md` e `contract/`.
Dependências fixadas em `renv.lock` (declaradas em `DESCRIPTION`, modo `explicit`).

## Pastas

| Pasta | Responsabilidade |
|---|---|
| `R/utils/` | configuração (`config/*.yml`), caminhos, logging, helpers de DuckDB |
| `R/tse/` | download com URL, sha256, bytes e data de coleta (bronze) |
| `R/normalize/` | leitura dos CSV do TSE com DuckDB, seções × turno, pareamento (silver) |
| `R/reconcile/` | verificações V1, V2 e V3; tipos de seção; classes de população (05 §2–3) |
| `R/accounting/` | totais municipais, conta contábil (só exibição), unidades para o método |
| `R/ecological/` | limites, cenários, estimação, identificação, validação cruzada, calibração (05 §4–5) |
| `R/diagnostics/` | resumo de diagnósticos por município e nacional |
| `R/web/` | `build_web_bundle()`, `validate_web_bundle()`, `write_mart()` (03 + `contract/`) |

Convenções: funções puras sempre que possível (tibble entra, tibble sai); I/O só em `R/tse/`,
`R/web/` e nos targets. Identificadores são `character` com zeros à esquerda. Ausente é `NA`, nunca `0`.

## Interface entre dados e método

A camada de dados entrega, por município, um tibble de **unidades** (só as que têm
`in_transition_analysis == TRUE`):

| Coluna | Tipo | Conteúdo |
|---|---|---|
| `election_id`, `uf`, `municipio_tse`, `comparison_unit_id` | chr | chaves |
| `population_status` | chr | `closed` ou `net_change` |
| `o_A`, `o_B`, `o_O`, `o_I`, `o_X`, `o_N` | int | margens de origem (1º turno); `o_X` = aptos − comparecimento; `o_N` = max(0, E₂ − E₁) |
| `d_A`, `d_B`, `d_I`, `d_X`, `d_S` | int | margens de destino (2º turno); `d_X` = aptos − comparecimento; `d_S` = max(0, E₁ − E₂) |

Invariante por linha: `o_A + o_B + o_O + o_I + o_X + o_N == d_A + d_B + d_I + d_X + d_S`.
A tabela nacional de unidades fica em `data/gold/2026-presidente/units.parquet`.

O método expõe (em `R/ecological/`):

```r
ec_bounds(units, scenario = "base", assumptions)  # -> tibble: origin, destination, min_votes, max_votes,
                                                  #    status, units_used, units_infeasible, method_id
ec_estimate(units, params, seed)                  # -> list(flows = tibble (colunas de 03 §11 sem chaves),
                                                  #         status = "ready"|"partial"|"insufficient_data"|"failed",
                                                  #         model = list(...)  # campos de qualidade.model (03 §12)
                                                  #    )
ec_calibrate(margins_t1, params, seed)            # -> list(report = tibble, thresholds = list(...),
                                                  #         calibration_id, status, decision)
```

- `params` é `config/metodo.yml` já carregado (lista), com os limiares calibrados quando existirem.
- `seed` é derivado de `(release_id, municipio_tse, method_id)` por `seed_for()` em `R/utils/`.
- `ec_estimate()` aplica as regras de publicação de 05 §5.7 e nunca devolve linhas para
  `insufficient_data` ou `failed`.
- A camada de dados não implementa nada de `R/ecological/`; nos testes dela, usar o stub de
  `tests/testthat/helper-ecological-stub.R`.

## Dados locais

A raiz de dados é `data/` (gitignored), ou o caminho da variável de ambiente `CADERNO_DATA_DIR`
quando definida (útil em worktrees, para reaproveitar downloads). Layout:
`<raiz>/bronze/2026-presidente/*.zip`, `<raiz>/silver/…`, `<raiz>/gold/…`, `<raiz>/releases/<release_id>/`.
O download não repete um arquivo que já existe com o mesmo tamanho declarado pelo servidor; o sha256 é
sempre recalculado e registrado.

## Execução

```bash
Rscript run.R 2026-presidente          # pipeline completo → data/releases/<release_id>/ → web/data/
Rscript -e 'targets::tar_make()'       # só o grafo
Rscript -e 'testthat::test_dir("tests/testthat")'
```
