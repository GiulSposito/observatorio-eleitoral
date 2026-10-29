# Caderno Eleitoral

**Observatório eleitoral municipal, independente e estático** · pt-BR · especificação v1.1 (27 de outubro de 2026)

Escolha um município brasileiro, compare o 1º e o 2º turno da **eleição presidencial de 2026** seção por seção e entenda o que os dados permitem concluir. Três níveis de evidência ficam sempre separados: o que foi **observado** (contabilidade exata, reconciliada com o TSE), o que é **matematicamente possível** (limites sob hipóteses explícitas) e o que é **estimado** (inferência ecológica com incerteza e diagnósticos).

O motor de dados é feito em **R** e publica resultados pré-computados em **JSON + Parquet**. **A primeira versão publicada cobre os municípios do Estado de São Paulo.** O site é **estático**, feito em **Quarto + JavaScript (ES modules) + DuckDB-Wasm + Plotly** — o mesmo stack do DudesApp. Não há backend de aplicação. Todos os números exibidos vêm de dados oficiais do TSE processados pelo pipeline, para qualquer município.

## Origem da ideia

A análise que motivou o projeto foi publicada por **Rômulo Fiúza e Mello** ([@fiuzaemello](https://x.com/fiuzaemello)) numa [thread no X em 26 de outubro de 2026](https://x.com/fiuzaemello/status/2114763737425211824). A discussão dessa thread — o que ela mostra, o que dados agregados não permitem afirmar e como generalizar a análise para qualquer município — está em [`docs/visao_inicial.md`](docs/visao_inicial.md).

O crédito também aparece na aplicação: no rodapé de todas as páginas e na página **Sobre**. O Caderno Eleitoral é independente; método, código e eventuais erros são de responsabilidade do projeto, não do autor da thread.

## Estado atual

Publicado em **https://giulsposito.github.io/observatorio-eleitoral/**. A primeira release cobre os 645 municípios do Estado de São Paulo, com dados oficiais do TSE do 1º e do 2º turno.

- Fatos observados e limites saem para todos os municípios; a verificação V1–V3 passou em todos.
- A estimativa de fluxos só é publicada onde a calibração por simulação a validou: municípios com 15 a 149 seções comparáveis. Nos maiores, a cobertura dos intervalos ficou entre 40% e 75%, abaixo da meta de 90%, e o site mostra só os limites, com o motivo.
- Na release atual, 170 municípios têm estimativa completa com Sankey; 207 ficaram sem estimativa porque o modelo não convergiu; 154 têm menos de 15 seções; 114 estão acima da faixa validada.
- Próximo incremento: modelo com taxas que variam entre seções (HMC), para estender a estimativa aos municípios grandes, e os demais estados.

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
├── R/ · _targets.R · run.R        pipeline em R (TSE → bronze/silver/gold → método → bundle)
├── config/ · contract/            parâmetros do método e contrato executável (JSON Schema, marts)
├── tests/                         testthat, checks JS, E2E (Playwright), fixtures sintéticas
├── web/                           site Quarto: páginas .qmd, js/, css/
└── examples/                      referência; nada aqui é lido pela aplicação nem entra em release
    ├── contrato/                  *.demo.json — exemplos fictícios dos contratos do 03
    └── preview/                   prévia HTML estática da identidade + screenshots
```

Pipeline em `R/` (`_targets.R`, `run.R`, `config/`, `contract/`, `renv.lock`; ver [`R/README.md`](R/README.md)), testes em `tests/`; a árvore completa está em [`docs/arquitetura.md`](docs/arquitetura.md) §10. `data/` (bronze/silver/gold/releases) e o bundle local `web/data/` nunca são versionados.

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
2. `Rscript -e 'renv::restore()'` e, para gerar uma release, `Rscript run.R 2026-presidente`: baixa os arquivos do TSE, roda o pipeline e copia o bundle validado para `web/data/`. A release de SP leva cerca de 2 h em 8 núcleos, quase todo esse tempo gasto na calibração e na estimação.
3. `quarto preview web` para ver o site local. Para desenvolver sem dados reais, `web/scripts/use-fixture.sh` copia o bundle sintético `DEMO-001`.

Para ver a prévia de identidade, abra `examples/preview/identidade-preview.html` no navegador a partir do repositório (ela carrega os tokens de `web/css/`). Os números e as cidades da prévia são fictícios; ela não consulta o TSE, não inicializa DuckDB e não implementa modelagem.

## Comandos

```bash
Rscript -e 'renv::restore()'
Rscript run.R <election_id>                     # pipeline → bundle → validação → render
Rscript -e 'targets::tar_make()'                # só o pipeline
Rscript -e 'testthat::test_dir("tests/testthat")'
for f in tests/web/*.check.mjs; do node "$f"; done
quarto preview web                              # desenvolvimento, com web/data/ local
quarto render web                               # gera web/_site/
quarto publish gh-pages web                     # publica no GitHub Pages
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
