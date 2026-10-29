# Caderno Eleitoral — Guia de identidade visual

**Versão:** 1.0 · **Status:** especificação de implementação · **Idioma:** pt-BR  
**Natureza:** plataforma independente de exploração de dados eleitorais; não representar vínculo institucional com o TSE.

## 1. Posicionamento e linguagem

**Conceito:** um caderno de pesquisa estatística interativo. Mais próximo de uma publicação acadêmica/editorial ou de um instituto de estatística do que de um cockpit empresarial.

**Atributos:** neutro, preciso, calmo, direto, auditável, acessível, elegante sem ornamentação.

**Princípios não negociáveis:**

1. Primeiro a informação, depois a interface: gráficos, tabelas e interpretação ocupam o espaço nobre.
2. A identidade editorial não deve privilegiar candidatos, partidos ou narrativas.
3. Observação, limite matemático e inferência estatística têm tratamentos textuais distintos.
4. Cada gráfico informa unidade, denominador, recorte, fonte, período e interpretação correta.
5. O leitor precisa conseguir verificar dados e consultar tabelas sem depender de hover, cor ou animação.
6. Um site de dados não deve parecer um produto de IA generativa: nada de gradientes neon, glassmorphism, sombras volumosas, cartões gigantes, badges desnecessários, emojis, blobs ou hero com números sem contexto.
7. O usuário deve identificar a ação principal em menos de cinco segundos: selecionar município e comparar turnos.

### Nome, marca e assinatura

**Nome de trabalho:** `caderno eleitoral` (minúsculas no wordmark). O nome é configurável; não assumir disponibilidade jurídica do nome ou domínio.  
**Assinatura opcional:** `Dados · Território · Análise` (não repetir em todas as telas).  
**Crédito institucional obrigatório:** `Projeto independente · Dados: Tribunal Superior Eleitoral (TSE)` — sempre claro, jamais mimetizar selo governamental ou usar logomarca do TSE como se houvesse endosso.

O wordmark é texto puro em IBM Plex Sans 600, preferencialmente sem pictograma. Não criar ícone de urna, bandeira, mapa do Brasil colorido, alvo, faísca, gradiente ou símbolo pseudo-institucional. Favicons simples podem usar duas linhas paralelas e um ponto em grafite, mas não são requisito do MVP.

## 2. Paleta e papéis semânticos

Todas as cores deverão ser consumidas por tokens semânticos em CSS (`web/css/design-tokens.css`), nunca por hex repetidos em componentes.

| Token | Valor | Uso |
|---|---|---|
| `--color-page` | `#F7F7F4` | Fundo semelhante a papel, sem textura |
| `--color-surface` | `#FFFFFF` | Superfície de tabela, menu e cabeçalho |
| `--color-ink` | `#202927` | Texto principal e títulos |
| `--color-muted` | `#57645F` | Metadados e descrição |
| `--color-quiet` | `#68726E` | Legendas e números auxiliares |
| `--color-border` | `#D8DDD7` | Divisões discretas |
| `--color-border-strong` | `#A0AAA4` | Delimitação funcional de campos |
| `--color-accent` | `#315D68` | Ações, foco contextual e links |
| `--color-candidate-a` | `#315D68` | Série 1 em comparações locais |
| `--color-candidate-b` | `#9B5C34` | Série 2, terra/argila |
| `--color-other` | `#6B7370` | Outros candidatos |
| `--color-invalid` | `#737874` | Brancos, nulos e dados não atribuídos |
| `--color-turnout` | `#5F6C4B` | Comparecimento e abstenção (com rótulos explícitos) |
| `--color-alert` | `#984D45` | Erro, divergência ou falha de qualidade |
| `--color-success` | `#4B6754` | Validação executada com sucesso |
| `--color-selection` | `#ECF2F0` | Foco contextual muito discreto |

### Associação de cores a candidatos

A e B são **slots visuais** com regra nacional: `A` é o finalista com o menor número de urna (03 §2), registrado uma vez no `catalogo.json`. Nunca atribuir a cor por ideologia/partido, não alternar cores entre telas da mesma disputa e nunca presumir significado político para azul/terra. A cor não basta para identificar série: usar rótulo direto, forma de marcador, padrão de linha ou legenda textual.

### Contraste e acessibilidade

- Tinta `#202927` sobre papel: aproximadamente **13,9:1**.
- Texto secundário `#57645F` sobre papel: aproximadamente **5,77:1**.
- Azul-petróleo `#315D68` sobre papel: aproximadamente **6,76:1**.
- Terra `#9B5C34` sobre papel: aproximadamente **4,92:1**.
- Texto pequeno deve ter contraste >= 4,5:1; gráficos e contornos essenciais >= 3:1 contra fundos adjacentes. O cinza de borda sutil não deve ser o **único** indicador visual de estado.
- Em telas monocromáticas/impressão, identificar as séries também por traço, símbolo, título e ordenação.

Norma de referência: WCAG 2.2 AA: https://www.w3.org/TR/WCAG22/.

## 3. Tipografia

**Fonte principal:** IBM Plex Sans (licença aberta; usar WOFF2 auto-hospedado conforme condições de licença, ou fallback de sistema enquanto não houver assets autorizados).  
**Fonte técnica excepcional:** IBM Plex Mono, apenas para código de seção, ID, hash, versão, SQL e exemplos técnicos.  
**Fallback:** `system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif`.

**Não usar** fonte condensada, display serif só para parecer editorial, tipografia cursiva, outline, caps lock extensivo nem três ou mais famílias.

| Papel | Desktop | Mobile | Peso | Entrelinha |
|---|---:|---:|---:|---:|
| Título de página | 34 px | 28 px | 600 | 1,15 |
| Título de seção | 23 px | 21 px | 600 | 1,25 |
| Título de gráfico | 17 px | 17 px | 600 | 1,3 |
| Corpo editorial | 16 px | 16 px | 400 | 1,55 |
| Interface geral | 14 px | 14 px | 400/500 | 1,45 |
| Legendas/fontes | 13 px | 13 px | 400 | 1,45 |
| Metadados técnicos | 12 px | 12 px | 400/500 | 1,4 |
| Número de destaque | 27 px | 24 px | 500/600 | 1,15 |

Dados numéricos: `font-variant-numeric: tabular-nums lining-nums`; números com sinal e unidade; `12.530 votos`, `+5,2 p.p.`, `0,47` em português brasileiro. A vírgula separa casas decimais; o ponto separa milhares. Evitar siglas sem explicação.

## 4. Sistema de layout

- `max-width` do conteúdo: **1.200 px**; artigos de metodologia e parágrafos densos: `max-width: 760 px`.
- Desktop: grade de 12 colunas, espaçamento entre colunas 24 px; página com 36 px de margem externa, respeitando largura máxima.
- Tablet: 24 px de margem; mobile: 16 px.
- Sistema de espaçamento base 4/8 px; macroespaçamentos 24, 32, 48, 64 px.
- Cabeçalho: 64 px de altura, branco com linha horizontal 1 px, wordmark à esquerda, navegação com 2–3 destinos à direita.
- Não utilizar menu lateral persistente no MVP, cards aninhados, bordas em todas as áreas ou fundo escuro no painel principal.
- Superfícies de conteúdo usam fundo branco **somente quando ajuda a agrupar**; preferir seções separadas por espaçamento e linhas.
- Raio dos cantos: 2–4 px; botões 4 px; caixas de busca 4 px; sem pílulas como padrão e **sem sombras** em painéis.
- Gráficos precisam de no mínimo 280 px de largura no mobile e escala inteligível; para detalhes de muitas seções oferecer tabela rolável e modo de visualização alternativo.

### Estrutura de página municipal (desktop)

```
┌─────────────────────────────────────────────────────────────────────┐
│ caderno eleitoral               Explorar   Metodologia   Sobre     │
├─────────────────────────────────────────────────────────────────────┤
│ Brasil / Santa Catarina / Município                                │
│                                                                     │
│ Município, UF                            [Buscar outro município]  │
│ Eleição · Cargo · Turnos · Cobertura · Atualização                   │
│ ─────────────────────────────────────────────────────────────────── │
│ Resumo    Seções    Transferências    Cenários    Qualidade          │
│                                                                     │
│ Indicador 1       Indicador 2       Indicador 3       Indicador 4    │
│ ─────────────────────────────────────────────────────────────────── │
│                                                                     │
│ [Gráfico principal — 8 colunas]       [Leitura — 4 colunas]          │
│                                                                     │
│ [Gráfico / tabela complementar — 12 colunas]                        │
│                                                                     │
│ Fonte · Denominador · Método · Versão · Download                    │
└─────────────────────────────────────────────────────────────────────┘
```

No mobile, os gráficos ocupam a largura disponível; os quatro indicadores tornam-se grade 2x2 ou lista, com títulos intactos e valores mais contidos. As abas podem rolar horizontalmente com indicação de continuidade, preservando navegação pelo teclado.

## 5. Padrões de componentes

### 5.1 Cabeçalho

- Wordmark sem ícone; no máximo três links (`Explorar`, `Metodologia`, `Dados e código`).
- Uma linha inferior sutil, sem barra colorida de marca e sem sombra sticky invasiva.
- No mobile, menu simples de texto; botão hamburguer apenas se realmente necessário.

### 5.2 Seletor de município

- Combobox com busca acentuada/sem acento e por `município`, `UF`, `código IBGE` ou `código TSE`.
- Resultado: `Campinas — SP`, segunda linha curta com UF e eventual código.
- Navegação completa por teclado, foco visível, `aria-expanded`, `aria-controls`, `aria-activedescendant`; evitar select nativo contendo milhares de opções.
- Município escolhido aparece na URL, sem depender de cookies, login ou estado global opaco.

### 5.3 Filtros

Seletores compactos de eleição, cargo, turno ou modo de comparação. Até quatro controles por linha. Mostrar valores selecionados em texto; nunca criar 12 filtros agrupados em um sidebar. Ao trocar eleição, resetar dados incompatíveis e manter município somente se elegível.

### 5.4 Faixa de indicadores

Números acompanhados de nome, unidade, período e comparação. Divisórias verticais discretas e **sem painel colorido**. Preferir `+1.204 votos` a `↑ 20,84%` quando a unidade de referência não for óbvia. Diferenças percentuais devem especificar se são percentuais ou pontos percentuais.

### 5.5 Gráficos

Bloco com ordem fixa: **título factual → subtítulo/unidade → gráfico → interpretação curta opcional → fonte/metodologia → acesso à tabela**. Eixos curtos e rotulados; poucas linhas de grade; tipografia nunca inferior a 12 px. Evitar legendas distantes quando a identificação direta das séries é possível.

### 5.6 Tabelas

Fundo branco, cabeçalho com borda inferior mais forte, separadores horizontais sutis, números alinhados à direita, zona/seção à esquerda. Ordenação explícita com `aria-sort`; paginação ou virtualização onde necessário. Exportação CSV é secundária, mas disponível. Não usar zebra pesada.

### 5.7 Destaques metodológicos

Três tags semânticas textuais distintas: `OBSERVADO`, `LIMITE CONDICIONAL`, `ESTIMADO PELO MODELO`. O texto é a principal codificação; cores são discretas. Separar **limites de viabilidade** de **intervalos de incerteza**. Nunca apresentar estimativas como se fossem transferências individuais comprovadas.

### 5.8 Estados

- `carregando`: skeleton discreto só no conteúdo que será preenchido; animação mínima e desativável por prefers-reduced-motion.
- `sem dados`: explicar exatamente qual fonte ou turno não está disponível, sem imputar zeros.
- `dados incompletos`: mostrar cobertura e qual análise foi desabilitada.
- `modelo não convergiu`: substituir resultado por diagnóstico, não por zero nem por última estimativa arbitrária.
- `não identificado`: célula ou município em que os dados não distinguem os fluxos possíveis (`05-metodo-analitico.md` §5.4). Mostrar os limites e a frase padrão, nunca um número central.
- `erro de rede/Wasm`: manter a ficha municipal e resumos JSON disponíveis.
- `vazio de busca`: informar como ampliar termo, sem tela lúdica.

### 5.9 Rodapé e crédito da ideia

O rodapé de **todas as páginas** traz, em texto discreto e com link: `Análise inspirada na thread de Rômulo Fiúza e Mello (@fiuzaemello)`, apontando para https://x.com/fiuzaemello/status/2114763737425211824. Acompanham a versão dos dados, a data de atualização, a licença e `Projeto independente`. O crédito não usa logotipo, avatar ou destaque visual e não sugere que o autor da thread endosse o projeto; a página `Sobre` detalha a origem.

## 6. Gramática de visualização

| Pergunta | Gráfico preferido | Interação permitida | Risco a evitar |
|---|---|---|---|
| Como os totais mudaram? | Slope/dot plot ou barras com base zero | Alternar votos e % | Eixos truncados em barras |
| De onde vem o saldo contábil? | Waterfall de componentes | Detalhar por seção | Chamar saldo de migração observada |
| Quais seções se destacam? | Scatter com linha de referência; ranking ordenável | Filtro por zona/local | Correlação como evidência causal |
| Como variam os municípios? | Dot plot e distribuição com percentis | Normalizar por aptos | Comparar volumes absolutos desigual |
| Quais fluxos o modelo estima? | Sankey + matriz RxC tabular | Selecionar método/hipóteses | Fluxo parecer individualmente observado |
| Qual o grau de identificação? | Intervalos lado a lado e matriz de limites | Trocar suposições | Misturar limite LP e IC bayesiano |

**Dados com incerteza:** quando houver inferência, exibir estimativa central e intervalo **com o tipo nomeado** (`95% de credibilidade` ou `faixa viável sob restrição X`). Não misturar o conceito num único objeto `lower/upper` sem metadados.

**Tamanho:** altura típica 280–380 px; 420 px apenas para scatter denso; Sankey pode crescer verticalmente conforme o número de categorias. Gráficos como conteúdo principal não devem ocupar apenas 1/3 da tela com cards decorativos ao redor.

**Interação:** tooltips resumem, mas não substituem rótulos e tabela; escovar pontos é opcional; hover, clique e teclado conduzem à mesma informação. Em espaços reduzidos, priorizar tabela sobre scatter ininteligível.

## 7. Linguagem e microcopy

**Tom:** informativo, contido, não acusatório, compreensível a quem não sabe estatística. Não usar expressões como `o modelo descobriu`, `a urna revelou`, `transferência comprovada`, `anomalia suspeita`, `IA explica tudo`.

Preferir:

- `Os votos válidos aumentaram em 1.142 entre os turnos.`
- `A correlação entre as variações por seção é 0,47; isso não estabelece causalidade.`
- `O modelo estima uma distribuição compatível com os totais, mas outras distribuições também são possíveis.`
- `Os limites abaixo pressupõem que não houve troca direta entre os dois finalistas.`
- `Dados indisponíveis para este recorte: análise não calculada.`

Cada página deve conter uma explicação de até 100 palavras **observacional** e uma seção própria de método. Qualquer leitura narrativa que dependa de um modelo deve estar rotulada como hipótese.

## 8. Gráficos e tabelas: acessibilidade e exportação

- Todo gráfico tem `<figure>`, `<figcaption>`, título, descrição em texto e tabela equivalente acessível.
- Foco visível mínimo de 2 px; alvo de clique recomendável >= 44 × 44 px nos controles principais.
- Cor não é o único canal de significado; adotar marcações e rótulos diretos.
- Não depender de movimento ou hover; honrar `prefers-reduced-motion`.
- Fonte `IBM Plex Sans` em local quando disponível, com fallback sem saltos excessivos de layout.
- Formatação monetária não aparece; unidades eleitorais explicitadas (`votos`, `eleitores`, `%` e `p.p.`).
- CSV é a forma tabular exportável; SVG/PNG para gráficos em uma fase posterior, se mantiver rótulos legíveis.
- Sempre permitir baixar dados e consultar origem do recorte, com timestamp e versão.

## 9. Critérios de design para aprovar o MVP

1. Página municipal com navegação, seleção, dois gráficos e tabela fica inteligível sem rolagem lateral a partir de 375 px.
2. É possível explicar o gráfico principal lendo somente título, legenda e fonte.
3. Não existem gradientes, sombras de cartões, avatars, badges decorativos, slogans de IA ou thumbnails genéricas.
4. Nenhuma série de candidato é identificada somente pela cor.
5. Todos os textos e controles passam avaliação de WCAG 2.2 AA; todo gráfico essencial tem alternativa tabular.
6. Uma página impressa/PDF mantém as legendas e as relações visuais, ainda que as interações sejam omitidas.
7. Uma pessoa pode diferenciar `observação`, `limite` e `inferência` sem ler a página de metodologia.
8. Em resolução de 1440 px, a área de conteúdo permanece contida e editorial, sem se espalhar de ponta a ponta.

## 10. Arquivos e implementação

- `web/css/design-tokens.css`: fonte canônica de cores, medidas e tipografia, incluída pelo site Quarto.
- `examples/preview/identidade-preview.html`: composição visual de referência com dados **fictícios**. Não é a aplicação final.
- `docs/02-especificacao-funcional-tecnica.md`: comportamento e critérios de aceite.
- `docs/03-contratos-de-dados.md`: saída do R e entrada do navegador.
- `docs/arquitetura.md`: stack e módulos do frontend (Quarto + ES modules + Plotly + DuckDB-Wasm).
- `CLAUDE.md`: contrato de execução para Claude Code.

## 11. Referências técnicas (não referências de marca)

- IBM Plex: https://github.com/IBM/plex
- WCAG 2.2: https://www.w3.org/TR/WCAG22/
- Plotly.js: https://plotly.com/javascript/
- Quarto: https://quarto.org/docs/websites/
- DuckDB-Wasm: https://duckdb.org/docs/stable/clients/wasm/overview

A identidade acima é original para o projeto. Não pressupõe licença ou associação com órgão público ou publicação existente.
