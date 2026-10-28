# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Caderno Eleitoral

Este arquivo é a referência obrigatória para agentes de código neste repositório.

## Estado atual do repositório

Ainda **não há pipeline nem site**. Existem três áreas, que não se misturam:

- `docs/` — documentação (visão de origem, arquitetura, guia visual, especificação, contratos, roteiro, método analítico, revisão crítica).
- `web/` — código da aplicação; por enquanto só `web/css/design-tokens.css`.
- `examples/` — referência que a aplicação nunca lê: `contrato/*.demo.json` (`release_id: DEMO-001`, município `00000`) e `preview/` (prévia HTML estática da identidade).

`R/`, `config/`, `contract/`, `tests/`, `_targets.R`, `run.R` e `renv.lock` nascem nas Fases 0–1; árvore-alvo em `docs/arquitetura.md` §10. `.claude/skills/` traz skills de R do projeto (ex.: `tdd-workflow`, `r-style-guide`, `dm-relational`).

## Missão

Implementar um observatório eleitoral brasileiro independente, estático, auditável e acessível. Permitir que qualquer pessoa selecione **qualquer município**, compare o 1º e o 2º turno da **eleição presidencial de 2026** seção por seção e entenda a diferença entre fatos observados, limites de viabilidade matemática e estimativas de inferência ecológica.

Stack igual ao do DudesApp (`../football/DudesApp`): **site Quarto + JavaScript em ES modules sem etapa de build + DuckDB-Wasm + Plotly.js + CSS tokens**. Dados produzidos **offline em R**, com `targets`, `renv`, `duckdb` (motor e escritor de Parquet, sem `arrow`), `dplyr`/`dm` e `testthat`. Hospedagem: arquivos estáticos/CDN. Não criar backend de aplicação.

## Origem e crédito

A ideia da análise vem da thread de **Rômulo Fiúza e Mello** (@fiuzaemello): https://x.com/fiuzaemello/status/2114763737425211824. O crédito é requisito do produto: rodapé de todas as páginas (`page-footer` em `web/_quarto.yml`) e página `Sobre`. Não remover nem esconder. `docs/visao_inicial.md` registra a discussão da thread; o município citado lá **não** tem tratamento, fixture, teste ou destaque na aplicação.

## Leia ANTES de programar

1. `README.md` — escopo, organização, origem e comandos.
2. `docs/arquitetura.md` — stack, camadas R, `R/web`, módulos do frontend, consulta no navegador, validação, deploy, ADRs.
3. `docs/01-guia-identidade-visual.md` — identidade, componentes, visualizações, rodapé com crédito.
4. `docs/02-especificacao-funcional-tecnica.md` — telas, navegação, requisitos e critérios de aceite.
5. `docs/03-contratos-de-dados.md` — contrato entre R e UI; fonte de verdade para esquemas.
6. `docs/04-roteiro-implementacao-claude-code.md` — fases, gates e prompts.
7. `docs/05-metodo-analitico.md` — método: verificações, população entre turnos, limites, estimação e regras de publicação.
8. `web/css/design-tokens.css` e `examples/preview/identidade-preview.html` — referência visual; a prévia **não** é a aplicação.

Em caso de conflito: contratos (03) para schema; método (05) para verificações, limites e estimação; arquitetura para stack e módulos; especificação (02) para funcionalidade; guia/tokens para visual. `docs/visao_inicial.md` é registro de origem, não especificação. Registrar conflitos no README e solicitar decisão apenas quando bloquearem a implementação.

## Decisões fixas

- Português brasileiro, acessibilidade WCAG 2.2 AA.
- Escopo eleitoral: Presidente da República 2026, 1º turno (4/10) × 2º turno (25/10), todos os municípios; exterior fora. Nenhuma outra eleição é usada, nem para desenvolvimento ou calibração.
- Site estático; sem autenticação, API própria, Shiny, SSR, Node no build do site, chatbot, banco operacional ou WebR no MVP.
- Catálogo/manifestos JSON e estatísticas Parquet versionados; `resumo.json` acessível sem WASM.
- DuckDB-Wasm inicializado apenas ao solicitar detalhes; sempre protegido por fallback.
- Plotly é a única biblioteca de gráficos (inclui Sankey); dependências de runtime (Plotly, DuckDB-Wasm) com URL e versão fixas em `web/js/vendor.js`, carregadas sob demanda. O Quarto insere scripts de módulo antes do `<head>` incluído, então import map não funciona.
- Sem UI kit genérico, gradientes, glassmorphism, sombras e cartões ornamentais. Não adicionar frameworks, mapas, ícones, animações ou bibliotecas sem requisito existente que justifique.
- As cores de candidatos são **slots editoriais A/B**, nunca identidade político-partidária. Regra nacional: `A` = menor número de urna (03 §2).
- Sem aba Horários nem logs de urna (fora do escopo).
- Separar rigorosamente `observed`, `conditional_bound` e `model_estimate`. Não remover avisos de incerteza, cobertura e fonte para melhorar a estética.
- Não introduzir mapas sem necessidade analítica comprovada.
- Não acessar feeds de dados ao executar testes offline; arquivos TSE são obtidos por job próprio.

## Restrições científicas e editoriais

- Dados agregados **não permitem identificar voto individual nem migração individual**.
- Nunca afirmar fraude, intenção de voto, causa ou transferência individual a partir de correlações de seção.
- Limites LP exigem `assumption_id`, informação de escopo e solução viável.
- Sankey somente com `features.ecological_model = ready` (`docs/05-metodo-analitico.md` §5.7) e só com células `determined`/`estimated`. Nunca montar Sankey a partir de limites. A matriz pontual é sempre a média posterior das contagens.
- Modelo ecológico não converge? Exibir estado indisponível, não última amostra, média não validada ou zero.
- Identificadores TSE e IBGE são distintos; preservar zeros à esquerda e rastrear mapa de correspondência.
- Só entram em limites e estimação unidades pareadas 1:1, `regular`, com `population_status` `closed` ou `net_change`; o resto fica nos dados observados com `exclusion_reason` (05 §2–3). Nunca forçar matriz fechada.
- A identidade ΔA + ΔB = O₁ + ΔC − ΔI é aritmética dentro de cada turno: serve de explicação, não verifica o pareamento entre turnos (05 §2).
- Todas as fontes públicas, hashes, timestamps, versões e exclusões metodológicas devem ser rastreáveis.
- Todo número exibido vem do pipeline a partir de dados oficiais do TSE. Nenhum município é privilegiado e nenhum valor é copiado de publicação externa (inclusive da thread de origem).
- Dados sintéticos só em `tests/fixtures/` e `examples/`, com `DEMO-*` ou `00000`, explicitamente rotulados; **jamais** entram em release (o validador falha).
- Nunca gerar um número real para preencher espaço em branco ou usar fallback silencioso para município diferente.

## Arquitetura em uma página

**R calcula; JSON/Parquet transportam; DuckDB-Wasm seleciona; JavaScript apresenta.** O navegador nunca estima, reconcilia nem corrige números.

- **Pipeline (R, `targets`):** TSE → bronze (brutos + URL/sha256/coleta) → silver (IDs e seções normalizados, TSE ≠ IBGE) → gold (reconciliação, LP, modelo, diagnósticos) → `R/web/build_web_bundle()` → `validate_web_bundle()` (gate) → release em staging → só então atualizar `latest.json` (publicação atômica). Entrada única: `Rscript run.R <election_id>`. `data/` é gitignored.
- **Release:** `latest.json` (único arquivo mutável) → `releases/<release_id>/catalogo.json` → manifesto por município → assets (`resumo.json`, `qualidade.json`, `secoes.parquet`, `limites.parquet`, `cenarios.parquet`, `fluxos_estimados.parquet`), com JSON por município e Parquet por UF (03 §3); o frontend só usa caminhos que o manifesto lista.
- **Frontend (`web/`):** páginas `index`, `explorar`, `metodologia`, `dados-e-codigo`, `sobre` (`.qmd` com ponto de montagem); lógica em `web/js/`. `data.js` é o **único** módulo que busca JSON e fala com DuckDB-Wasm; `catalog.js` busca município sem DuckDB; `state.js` mantém o recorte na URL; `format.js`, `evidence.js`, `components.js`, `charts.js` (Plotly), `app.js`, `pages/`.
- **Carga:** `latest` → catálogo (busca) → manifesto → `resumo.json` (first paint, sem Wasm) → Parquet via DuckDB-Wasm só ao abrir aba de detalhe.
- **Gates por status:** `manifest.features.*` ∈ `ready | partial | insufficient_data | failed | unavailable` decide quais abas aparecem (ex.: `ecological_model`: `ready` permite Sankey, `partial` publica só a tabela, conforme 05 §5.7). `validation_status != passed` exige advertência e bloqueio de análises sensíveis. `catalogo.publication_status`: `ready | partial | unavailable`.
- **Classe de evidência:** `evidence_type ∈ {observed, conditional_bound, model_estimate}`; limite LP (`min_votes/max_votes` + `assumption_id` + `constraint_scope`) nunca se mistura com intervalo estatístico (`interval_low/estimate/interval_high` + `interval_type`).
- **Versões rastreadas:** `app_version`, `schema_version` (semver; major em mudança incompatível), `pipeline_git_sha`, `method_version`, `release_id`.

## Convenções de implementação

- JavaScript em ES modules sem bundler; validar `schema_version` e estrutura dos JSON em runtime no `data.js` (padrão do DudesApp).
- Componentes e gráficos recebem dados preparados; nenhum deles monta SQL ou URLs. SQL constante e parametrizado só em `data.js`; `uf`/`municipio_tse` validados contra o catálogo antes de virar caminho ou parâmetro.
- `R/web/` não analisa nada: seleciona, renomeia, ordena e escreve via `write_mart()`. Cálculo novo vai para a gold.
- Código R separado em funções testáveis; `targets` orquestra jobs e `renv.lock` fixa dependências.
- Toda transição de schema exige mudança em `docs/03-contratos-de-dados.md`, `contract/`, fixtures, teste de contrato e versionamento. Não mudar o modelo de dados só para acomodar um gráfico.
- Usar `Intl.NumberFormat('pt-BR')`, vírgula decimal, datas com fuso explícito, sinal de delta e unidade.
- Requisições assíncronas têm cancelamento ou invalidação ao trocar município; não permitir dados residuais de recorte anterior.
- Todas as visualizações essenciais possuem tabela equivalente e nota de fonte/método.
- Interações são funcionais, não controles decorativos. Usar padrões acessíveis de foco e teclado.

## Workflow de trabalho para agentes

1. Escolher **uma fase** do roteiro; expor plano de 3–7 passos antes de editar.
2. Listar arquivos afetados, contratos relevantes e testes de aceite.
3. Implementar menor vertical slice funcional; evitar scaffolding desnecessário.
4. Rodar testes R, checks JS, teste de contrato, E2E e render aplicáveis.
5. Capturar telas desktop 1440 px e mobile 375 px e comparar com `examples/preview/` e o guia.
6. Encerrar com: arquivos alterados, testes executados e resultados, pendências reais e próximo incremento.
7. Não declarar a fase concluída sem executar testes, nem inventar evidências de QA.

Fases (detalhe, gates e prompts em `docs/04-roteiro-implementacao-claude-code.md`; não pular gates): **0** visual com bundle sintético · **1A** ingestão factual em R · **1B** integração DuckDB-Wasm · **2** limites LP e cenários · **3** inferência ecológica · **4** escala nacional e publicação.

## Definição de pronto do MVP factual (Fases 0–1)

- [ ] Buscar município com/sem acentos e desambiguar homônimos por UF.
- [ ] URL compartilhável `explorar.html?e=...&m=...` funciona ao recarregar e ao usar Voltar/Avançar.
- [ ] Visual conforme `docs/01-guia-identidade-visual.md`, sem ornamentos proibidos.
- [ ] Crédito à thread de Rômulo Fiúza e Mello no rodapé de todas as páginas e em `Sobre`.
- [ ] `resumo.json` real vem de fonte oficial, foi reconciliado e exibe cobertura/versão/fonte.
- [ ] `secoes.parquet` é consultado via worker DuckDB-Wasm após seleção de aba de detalhe.
- [ ] Falha no Wasm deixa resumo e metodologia disponíveis.
- [ ] Não há Sankey nem estimativa sem dados/modelo validados.
- [ ] Testes R, checks JS e E2E passam; `quarto render web` passa; QA de 375/768/1440 px registrada.
- [ ] Nenhum dado sintético no `web/_site/` publicado nem em release.

## Comandos-alvo (criar scripts antes de executá-los)

```bash
Rscript -e 'renv::restore()'
Rscript run.R <election_id>                       # pipeline → bundle → validação → render
Rscript -e 'targets::tar_make()'                  # só o pipeline
Rscript -e 'testthat::test_dir("tests/testthat")'
for f in tests/web/*.check.mjs; do node "$f"; done
quarto preview web                                # desenvolvimento, com web/data/ local
quarto render web                                 # gera web/_site/
cd tests/e2e && npm ci && npx playwright test     # E2E + axe; npm só aqui, nunca no site
```

Teste isolado:

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-<nome>.R")'
Rscript -e 'targets::tar_make(names = <target>)'
node tests/web/<modulo>.check.mjs
cd tests/e2e && npx playwright test <arquivo>.spec.js
```

Testes não usam rede; testes contra fontes TSE ao vivo ficam separados e opcionais.
