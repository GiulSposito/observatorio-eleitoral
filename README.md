# Caderno Eleitoral

**Observatório eleitoral municipal, independente e estático** · pt-BR · especificação v1.1 (27 de outubro de 2026)

Escolha um município brasileiro, compare o 1º e o 2º turno da **eleição presidencial de 2026** seção por seção e entenda o que os dados permitem concluir. Três níveis de evidência ficam sempre separados: o que foi **observado** (contabilidade exata, reconciliada com o TSE), o que é **matematicamente possível** (limites sob hipóteses explícitas) e o que é **estimado** (inferência ecológica com incerteza e diagnósticos).

O motor de dados é feito em **R** e publica resultados pré-computados em **JSON + Parquet**. O site é **estático**, feito em **Quarto + JavaScript (ES modules) + DuckDB-Wasm + Plotly** — o mesmo stack do DudesApp. Não há backend de aplicação. Todos os números exibidos vêm de dados oficiais do TSE processados pelo pipeline, para qualquer município.

## Origem da ideia

A análise que motivou o projeto foi publicada por **Rômulo Fiúza e Mello** ([@fiuzaemello](https://x.com/fiuzaemello)) numa [thread no X em 26 de outubro de 2026](https://x.com/fiuzaemello/status/2114763737425211824). A discussão dessa thread — o que ela mostra, o que dados agregados não permitem afirmar e como generalizar a análise para qualquer município — está em [`docs/visao_inicial.md`](docs/visao_inicial.md).

O crédito também aparece na aplicação: no rodapé de todas as páginas e na página **Sobre**. O Caderno Eleitoral é independente; método, código e eventuais erros são de responsabilidade do projeto, não do autor da thread.

## Estado atual

Ainda não há pipeline nem site. O repositório tem a especificação, os tokens de design e exemplos de referência. A implementação segue as fases de [`docs/04-roteiro-implementacao-claude-code.md`](docs/04-roteiro-implementacao-claude-code.md), começando pela Fase 0.

## Organização

```text
obsEleitoral/
├── README.md · CLAUDE.md
├── docs/                          documentação
│   ├── visao_inicial.md           origem: discussão da thread que inspirou o projeto
│   ├── arquitetura.md             stack, camadas, módulos, ADRs, estrutura-alvo do repositório
│   ├── 01-guia-identidade-visual.md
│   ├── 02-especificacao-funcional-tecnica.md
│   ├── 03-contratos-de-dados.md   schema R → navegador (fonte de verdade)
│   ├── 04-roteiro-implementacao-claude-code.md
│   ├── 05-metodo-analitico.md     verificações, população entre turnos, limites, estimação
│   └── analise-critica-metodologia.md
├── web/                           código da aplicação (site Quarto)
│   └── css/design-tokens.css      tokens canônicos da identidade
└── examples/                      referência; nada aqui é lido pela aplicação nem entra em release
    ├── contrato/                  *.demo.json — exemplos fictícios dos contratos do 03
    └── preview/                   prévia HTML estática da identidade + screenshots
```

`R/`, `config/`, `contract/`, `tests/`, `_targets.R`, `run.R` e `renv.lock` nascem nas fases seguintes; a árvore completa está em [`docs/arquitetura.md`](docs/arquitetura.md) §10. `data/` (bronze/silver/gold/releases) e o bundle local `web/data/` nunca são versionados.

## Documentos

| Documento | Conteúdo | Manda em |
|---|---|---|
| [`docs/arquitetura.md`](docs/arquitetura.md) | Camadas R (bronze/silver/gold), `R/web`, módulos do frontend, consulta no navegador, orquestração, validação, deploy, ADRs | Stack e estrutura |
| [`docs/01-guia-identidade-visual.md`](docs/01-guia-identidade-visual.md) | Linguagem, paleta, tipografia, componentes, gráficos, acessibilidade | Visual |
| [`docs/02-especificacao-funcional-tecnica.md`](docs/02-especificacao-funcional-tecnica.md) | Público, telas, navegação, requisitos de ETL e frontend, testes, critérios de aceite | Funcionalidade |
| [`docs/03-contratos-de-dados.md`](docs/03-contratos-de-dados.md) | `latest.json`, `catalogo.json`, manifesto, `resumo.json`, Parquets, invariantes, testes de contrato | Schema |
| [`docs/04-roteiro-implementacao-claude-code.md`](docs/04-roteiro-implementacao-claude-code.md) | Fases 0–4 com prompts, gates e checklist por entrega | Ordem de trabalho |
| [`docs/05-metodo-analitico.md`](docs/05-metodo-analitico.md) | Verificações V1–V3, população entre turnos, limites de Fréchet, estimação com vários métodos, grau de identificação, calibração e regras de publicação | Método |
| [`CLAUDE.md`](CLAUDE.md) | Regras para agentes de código, comandos, definição de pronto | Execução |
| [`docs/analise-critica-metodologia.md`](docs/analise-critica-metodologia.md) | Revisão crítica da metodologia e da especificação: achados por severidade e recomendações | Pendências a decidir |

## Como começar

1. Leia `CLAUDE.md` e os documentos acima.
2. Peça ao Claude Code a **Fase 0** do roteiro: site Quarto em `web/` com os tokens de `web/css/design-tokens.css`, usando `examples/preview/identidade-preview.html` como referência visual e um bundle sintético de teste. Nenhum número real nesta fase.
3. Depois: Fase 1A (ingestão factual em R), 1B (integração com DuckDB-Wasm), limites, inferência e escala nacional.

Para ver a prévia de identidade, abra `examples/preview/identidade-preview.html` no navegador a partir do repositório (ela carrega os tokens de `web/css/`). Os números e as cidades da prévia são fictícios; ela não consulta o TSE, não inicializa DuckDB e não implementa modelagem.

## Comandos

Os scripts ainda não existem; estes são os comandos-alvo definidos na arquitetura.

```bash
Rscript -e 'renv::restore()'
Rscript run.R <election_id>                     # pipeline → bundle → validação → render
Rscript -e 'targets::tar_make()'                # só o pipeline
Rscript -e 'testthat::test_dir("tests/testthat")'
for f in tests/web/*.check.mjs; do node "$f"; done
quarto preview web                              # desenvolvimento, com web/data/ local
quarto render web                               # gera web/_site/
```

## Limitações deliberadas

- Escopo: só a eleição presidencial de 2026 (1º × 2º turno). Votos no exterior ficam fora.
- Dados agregados por seção não identificam voto individual nem migração individual; o projeto não afirma fraude, intenção ou causa.
- A estimação de fluxos depende de qualidade, comparabilidade e hipóteses; nem todo município terá estimativa.
- O nome `Caderno Eleitoral` é provisório e não implica associação com o Tribunal Superior Eleitoral.
- Esquemas e disponibilidade das fontes do TSE variam por eleição, UF e turno; o pipeline confere tudo no momento da coleta.

## Referências

- Portal de Dados Abertos do TSE: https://dadosabertos.tse.jus.br/
- Arquivos de divulgação de resultados: https://www.tse.jus.br/eleicoes/eleicoes-2026-content/arquivos/divulgacao-de-resultados
- `targets`: https://docs.ropensci.org/targets/
- DuckDB R: https://duckdb.org/docs/stable/clients/r
- DuckDB-Wasm: https://duckdb.org/docs/current/clients/wasm/data_ingestion
- Quarto websites: https://quarto.org/docs/websites/
- Plotly.js: https://plotly.com/javascript/
- WCAG 2.2: https://www.w3.org/TR/WCAG22/
