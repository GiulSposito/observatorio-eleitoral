# Caderno Eleitoral — Roteiro de implementação para Claude Code

**Objetivo:** dividir a construção em entregas verificáveis, sem permitir que uma UI aparentemente pronta esconda lacunas no pipeline ou na metodologia.

Este roteiro é **planejamento**, não implementação final. O pacote contém uma referência de estilo HTML e arquivos de contrato; cabe ao agente escrever e testar a aplicação real.

## 0. Preparação do repositório

A estrutura-alvo do repositório está em `arquitetura.md` §10: código da aplicação (`R/`, `web/`, `tests/`, `config/`, `contract/`), documentação (`docs/`) e exemplos de referência (`examples/`) separados. O `.gitignore` já exclui `data/`, caches do `targets`/`renv`, saída do Quarto (`web/_site/`, `web/.quarto/`), o bundle local (`web/data/`) e artefatos de teste; fixtures pequenas de `tests/fixtures/` são versionadas.

Todo número exibido pela aplicação vem do pipeline R a partir de dados oficiais do TSE, para qualquer município, na eleição presidencial de 2026 (1º × 2º turno). Nenhuma outra eleição é usada. Enquanto o TSE não publicar os dados do 2º turno, o desenvolvimento começa pelos arquivos do 1º turno de 2026. O método está em `05-metodo-analitico.md`. Não há município privilegiado, nem valores copiados de publicações externas. Dados sintéticos existem só em `tests/fixtures/` e `examples/`, com `DEMO-*`/`00000`, e são bloqueados em release.

## Fase 0 — Visual e experiência (sem dados eleitorais reais)

**Prompt para Claude Code:**

> Leia integralmente `CLAUDE.md`, `docs/arquitetura.md`, `docs/01-guia-identidade-visual.md`, `docs/02-especificacao-funcional-tecnica.md` e `docs/03-contratos-de-dados.md`. Crie a Fase 0 do Caderno Eleitoral como site Quarto em `web/`, com JavaScript em ES modules sem etapa de build, no mesmo padrão do DudesApp (`.qmd` com ponto de montagem + `web/js/`). Use `web/css/design-tokens.css` como fonte de tokens e `examples/preview/identidade-preview.html` como referência de composição, sem copiar seus números. Implemente `index`, `explorar`, `metodologia`, `dados-e-codigo` e `sobre`; rodapé com o crédito da thread de Rômulo Fiúza e Mello em todas as páginas; seletor acessível, URL compartilhável `explorar.html?e=&m=`, abas Resumo/Seções/Transferências/Cenários/Qualidade e estados de carregamento/erro/indisponibilidade. Para desenvolver a interface, use um bundle sintético em `tests/fixtures/` (`DEMO-*`/`00000`, rotulado `DADOS FICTÍCIOS`), servido só no preview local. Não implemente R, DuckDB nem inferência nesta fase. Faça checks `tests/web/*.check.mjs` e E2E em `tests/e2e/`, verifique 375/768/1440 px e reporte os resultados.

**Saídas:** layout editorial navegável, busca funcional, URL consistente, design tokens adotados, blocos `BrandHeader`, `MunicipalityCombobox`, `MetricStrip`, `ChartFrame`, `AnalysisTabs`, `MethodLabel`, `DataQualityNotice` em `web/js/components.js`.

**Gate:** nenhum número real; bundle sintético com indicação visível de demonstração e fora de qualquer release; crédito da ideia no rodapé e em `Sobre`; sem gradientes/sombras; navegação e busca por teclado; todos os links e controles operam.

## Fase 1A — Pipeline factual em R (recorte municipal)

**Prompt:**

> Implemente somente a ingestão factual em R para a eleição presidencial de 2026, 1º e 2º turnos (começando pelo 1º se o 2º ainda não estiver publicado), uma UF, com municípios de teste escolhidos por perfil (pequeno, grande, com seções agregadas) e nenhum tratamento especial no código. Inspecione o layout real dos arquivos do TSE antes de assumir colunas; crie adapters de fonte e manifests. Use `targets`, `duckdb`, `dplyr`/`dm`, `testthat` e `renv` (sem `arrow`; ver `docs/arquitetura.md`, ADR-06). Normalize candidato, município TSE, zona, seção, turno, comparecimento e votos. Implemente as verificações V1–V3, os tipos de seção e as classes de população de `docs/05-metodo-analitico.md` §1–3; a identidade contábil é só exibição. Meça em 2026 a distribuição da mudança líquida de aptos por seção para calibrar `τ`, e confirme a fonte do tipo de seção e as categorias especiais de voto. Produza `resumo.json`, `secoes.parquet`, `qualidade.json` e `manifest.json` conformes ao contrato 03. Bloqueie a publicação se não validar. Não implemente modelo ecológico nesta fase.

**Gate:** V1 e V3 passam ou têm divergência explicada com código; toda unidade fora da análise de transição tem `exclusion_reason`; distribuição da mudança de aptos de 2026 registrada; parser versionado, arquivos brutos com URL/hash, testes sintéticos + testes com dados reais, release reproduzível. Se a fonte não estiver disponível, entregar parser e fixtures com status `unavailable`, nunca números inventados.

## Fase 1B — Integração real do site com os Parquets

**Prompt:**

> Integre a Fase 0 com os artefatos da Fase 1A. Em `web/js/data.js`, carregue `latest.json` e `catalogo.json`, depois `resumo.json` sem inicializar WASM. Inicialize DuckDB-Wasm somente na aba Seções, usando caminhos exclusivamente do manifesto validado. Implemente tabela exportável, scatter por seção, modo de normalização, filtro de zona e fallback para falha WASM. Não adicione outra fonte de verdade; scripts do frontend não devem corrigir ou reestimar totais. Acrescente testes de versão, URL, race conditions e compatibilidade Parquet.

**Gate:** URL direta funciona em hosting estático; o resumo aparece mesmo sem WASM; nenhuma aba usa dados de município anterior.

## Fase 2 — Limites de viabilidade ecológica

**Prompt:**

> Implemente os limites de `docs/05-metodo-analitico.md` §4: Fréchet em fórmula fechada por unidade, somados no município, com as pseudo-categorias de população; cenários com restrições por unidade resolvidos por LP (`ROI`/GLPK ou `lpSolve`, escolha documentada), com `assumption_id`. Meça a sensibilidade à hipótese `pop-liquida-minima`. Teste casos viáveis/inviáveis e comparação seção a seção. Não modele transferências individuais como observadas. Exporte `limites.parquet` e `cenarios.parquet`, com validação de contratos. Na UI, mostrar a matriz de intervalos e o motivo pelo qual limites marginais não formam automaticamente uma matriz para Sankey. Cenários são selecionados entre arquivos pré-computados, não resolvidos no navegador.

**Gate:** todas as restrições reproduzíveis e testes de LP passam; sem Sankey baseado em intervalos extremados.

## Fase 3 — Inferência ecológica e incerteza

**Prompt:**

> Implemente a estimação de `docs/05-metodo-analitico.md` §5: `dm-homog` e `lphom` (e `ecolRxC`, se viável) sobre as unidades do próprio município, sem pooling entre municípios; validade computacional; grau de identificação por célula; checagem preditiva com validação cruzada; calibração por simulação com os processos G1–G4 antes de fixar os limiares de `config/metodo.yml`. Publique `fluxos_estimados.parquet` com a média posterior das contagens, a classe de identificação e a faixa entre métodos, e `features.ecological_model` conforme §5.7. Sankey só com `ready`, acompanhado da matriz tabular. Não assuma que bootstrap simples resolve toda incerteza.

**Gate:** relatório de calibração com cobertura empírica ≥ 90% para células `estimated` nos processos G2–G4, ou decisão registrada de publicar só limites; regras de 05 §5.7 cobertas por testes; nenhuma alegação de transferência individual.

## Fase 4 — Escala nacional, publicação e operação

**Prompt:**

> Generalize o pipeline R para todas as UFs e municípios elegíveis sem materializar todo o país na memória. Use branches controlados do `targets`, partição Parquet/arquivos agrupados quando necessário e releases imutáveis. Adicione catálogo nacional, cobertura por município, publicação atômica por manifest/sha256, testes de município pequeno/grande e URLs de CDN. Teste HTTP Range/CORS e desempenho de carregamento sob demanda. Prepare documentação e comandos de rebuild incremental.

**Gate:** cobertura não é confundida com 100% de processamento; faltantes são rotulados; cada release auditável; smoke tests de 3 perfis de tamanho e dois navegadores.

## Registros de decisão (ADR)

As decisões ficam na tabela de `arquitetura.md` §12 (ADR-01 a ADR-10: stack estático, Quarto + ES modules, Plotly, DuckDB sem `arrow`, particionamento, plano de dados, `evidence_type`, quarentena). A acrescentar ali quando decididos: chaves de seção e correspondência TSE/IBGE; unidade comparável e tratamento de seções agregadas; modelo ecológico (método, priors, diagnósticos, comunicação).

## Checklist transversal por entrega

- [ ] A interface identifica `Observado`, `Limite condicional`, `Estimado` ou `Indisponível`.
- [ ] Títulos e legendas em pt-BR, unidades e denominadores explícitos.
- [ ] Fontes, hashes e versões vinculados a cada recorte.
- [ ] Acessibilidade de teclado, foco, Zoom 200%, tabela equivalente para gráficos.
- [ ] `quarto render web`, `tests/web/*.check.mjs` e E2E de `tests/e2e/` executados (quando a etapa tem UI).
- [ ] Crédito da ideia (thread de Rômulo Fiúza e Mello) presente no rodapé e em `Sobre`.
- [ ] `testthat`/teste de contrato executados (quando a etapa tem R).
- [ ] Screenshot do desktop e mobile; nenhuma sobreposição/clipping.
- [ ] Mudanças de contrato documentadas com compatibilidade.
- [ ] Nenhum placeholder vira zero ou dado oficial.
- [ ] README atualizado com limitações e próxima fase.

## Estratégia de versionamento

- `app_version`: versão do frontend.
- `schema_version`: versão dos contratos JSON e Parquet.
- `pipeline_git_sha`: versão exata da ETL.
- `method_version`: versão de contabilidade/LP/modelagem.
- `release_id`: snapshot publicado dos dados.

O usuário deve conseguir voltar a uma versão de release e reproduzir os mesmos gráficos, desde que o código de renderização seja compatível com a versão do schema.
