# Análise crítica da metodologia e da especificação

> **Data:** 27 de outubro de 2026 · **Escopo:** todos os documentos de `docs/` (visão inicial,
> arquitetura, 01–04) e `CLAUDE.md` · **Natureza:** revisão; não altera a especificação. As
> correções propostas ficam na seção G para decisão.
>
> **Atualização (27/10/2026):** C1, C2, C3, C4 e A1 foram tratados em
> [`05-metodo-analitico.md`](05-metodo-analitico.md), e o escopo passou a ser a eleição
> presidencial de 2026 (1º × 2º turno), sem uso de outras eleições: onde esta revisão sugere
> dados de 2022, leia-se arquivos de 2026. A4 (aba Horários removida), A6 (vocabulário) e A7 (regra
> dos slots) foram resolvidos no contrato 1.2.0. Os demais achados seguem abertos.

## Sumário executivo

**A proposta é viável, e a tese central está certa:** separar o que foi observado, o que é
matematicamente possível e o que é estimado é a forma honesta de tratar transferências de voto a
partir de dados agregados. A crítica da visão inicial ao método da thread também confere (§B.3).

O problema está menos na ideia e mais em **o que a especificação promete validar**. Quatro pontos são
críticos:

1. **C1** — o critério de qualidade da inferência ecológica verifica o cálculo, não a validade da
   estimativa. Convergência e margens fechadas passam mesmo quando a estimativa está errada.
2. **C2** — a identidade contábil é uma tautologia dentro de cada turno. Resíduo zero não prova
   que as seções foram pareadas corretamente entre turnos.
3. **C3** — a matriz de transição supõe população fechada, e o voto em trânsito quebra isso de
   forma sistemática. A especificação manda bloquear o modelo sem definir o tratamento.
4. **C4** — "qualquer município" só vale onde houve 2º turno daquele cargo.

Há ainda 8 achados de severidade alta (contrato incompleto, inconsistências entre documentos,
mediana posterior que não fecha margens, correlações enganosas, aba Horários sem pergunta
analítica) e 6 médios.

**Impossível em princípio:** certificar que a estimativa ecológica de um município está correta.
Sem verdade de campo, o melhor que o produto pode afirmar é que a estimativa é compatível com os
dados sob hipóteses declaradas e quão sensível ela é a essas hipóteses. A especificação deve ser
reescrita nesses termos (§F).

---

## Método da revisão

- Leitura integral de `visao_inicial.md`, `arquitetura.md`, `01`–`04` e `CLAUDE.md`, buscando
  (a) erros matemáticos ou estatísticos, (b) promessas impossíveis de cumprir, (c) lacunas que
  impedem implementar ou testar e (d) contradições entre documentos.
- Conferência aritmética da identidade contábil, dos limites determinísticos e da matriz
  alternativa da visão (§B).
- Verificação de fatos externos: pacotes R no CRAN, regras do voto em trânsito de 2026 e limites
  de hospedagem estática (fontes ao final).
- Severidade: **Crítico** compromete a correção do que é publicado; **Alto** impede implementar
  ou testar de forma determinística, ou induz leitura errada; **Médio** gera custo, retrabalho ou
  risco localizado.

---

## A. Estratégia de análise

### A.1 O que está certo

- **Três classes de evidência** (`observed`, `conditional_bound`, `model_estimate`) com
  renderização diferente e `unavailable` como estado, nunca zero.
- **Limites antes de modelo.** Mostrar primeiro o que as margens permitem e só depois uma
  estimativa condicionada a hipóteses é a ordem certa.
- **Proibição de Sankey montado com limites** e exigência de tabela equivalente para todo gráfico.
- **Cadastro fechado.** No Brasil o cadastro eleitoral fecha antes da eleição, então não há
  eleitores novos entre turnos. Isso torna a hipótese de população fechada mais defensável aqui do
  que em comparações entre eleições distintas, desde que trânsito e seções especiais sejam
  tratados (C3).

### A.2 Problemas de estratégia

**C1 — O critério de qualidade da inferência ecológica não mede o que promete (Crítico).**
02 §4.5 e §5.6, 03 §5 e §9, 04 Fase 3 e `CLAUDE.md` condicionam a estimativa e o Sankey a
"diagnóstico aprovado", convergência e "margens consistentes". Mas:

- R-hat e ESS medem se o amostrador explorou a posterior, não se o modelo descreve o mundo. Um
  modelo com hipótese errada (por exemplo, homogeneidade das taxas de transição entre seções)
  converge perfeitamente para a resposta errada.
- Modelos que amostram contagens internas por seção (como o multinomial-Dirichlet de Rosen et al.,
  implementado em `eiPack::ei.MD.bayes`) fecham as margens **por construção**. O teste de margens
  não discrimina nada.
- O teste com "dados sintéticos com matriz geradora conhecida" (04 Fase 3) é circular quando os
  dados são gerados pelo próprio modelo: mostra que o código funciona, não que o método funciona
  nos dados reais.

O problema de fundo é o viés de agregação: se as taxas de transição variam com a composição da
seção (o que é plausível), o modelo atribui a fluxos o que é efeito de composição, e nenhum
diagnóstico interno detecta isso.

**Proposta de critério**, em camadas:

1. Validade computacional (o que já existe): convergência e margens.
2. **Sensibilidade entre famílias de modelo:** pelo menos dois métodos de natureza diferente,
   por exemplo `ei.MD.bayes` (bayesiano hierárquico), `lphom` (programação linear sob
   homogeneidade, feito para transferência de votos entre eleições) e `ecolRxC` (estrutura
   latente de Thomsen), mais variação de priors.
3. **Informação relativa:** razão entre a largura do intervalo posterior e a largura dos limites
   determinísticos agregados, por célula. Quando os métodos discordam por quase toda a faixa
   permitida pelos limites, o resultado é **"não identificado"**: publicar os limites e não
   publicar ponto nem Sankey.
4. **Checagem preditiva:** ajustar sem parte das seções e prever as margens de 2º turno das seções
   deixadas de fora; comparar com um modelo nulo simples.
5. **Simulações adversariais:** recuperar matrizes conhecidas em dados gerados **fora** das
   hipóteses do modelo (taxas correlacionadas com composição, heterogeneidade entre zonas).

**C4 — "Qualquer município" depende do cargo (Crítico).** README, `CLAUDE.md` e 02 §0 prometem
análise para qualquer município. Só existe comparação entre turnos onde houve 2º turno daquele
cargo:

- **Presidente:** todos os municípios, se houver 2º turno.
- **Governador:** só nas UFs com 2º turno.
- **Prefeito:** só em municípios com mais de 200 mil eleitores (CF, art. 29, II) que tiveram
  2º turno.

O motor genérico ("eleição é configuração", arquitetura §2.1) está certo; a promessa do produto e o
catálogo (03 §4) precisam expressar a elegibilidade por eleição.

**A2 — Pooling entre municípios (Alto).** A visão (§7) e a arquitetura (§4.3) propõem um modelo
hierárquico que empresta informação de municípios "semelhantes". Em município pequeno, a
estimativa vira essencialmente a média do grupo, e a definição de "semelhante" já é uma hipótese
forte (porte, UF, perfil político). Mostrar o peso do pooling (arquitetura §4.3) é necessário mas
não suficiente: um Sankey municipal que reflete sobretudo a região induz leitura local. Proposta:
abaixo de um limiar de informação local, não publicar estimativa municipal; publicar no nível em
que o pooling é natural (UF ou região) e deixar o município com limites e dados observados.

**A3 — Correlação por seção (Alto).** A aba Seções (02 §4.4) destaca a correlação de Pearson entre
variação de comparecimento e variação de votos de um finalista. Três problemas:

- **Mecânica:** pela identidade, ΔA + ΔB = O₁ + ΔC − ΔI. Parte da correlação entre ΔA e ΔC é
  aritmética, não comportamento (a visão já aponta isso).
- **Escala:** deltas absolutos crescem com o tamanho da seção. Correlacionar valores absolutos
  mede em boa parte o tamanho das seções.
- **Multiplicidade:** com 5.570 municípios e seções em número pequeno, vários coeficientes
  parecerão extremos só por acaso, e um site público convida a procurar o "mais anômalo".

Proposta: normalizar por aptos como padrão; exigir número mínimo de seções para mostrar o
coeficiente; mostrar intervalo de confiança; oferecer a distribuição de referência da UF; não
ordenar nem destacar municípios por coeficiente.

**A4 — Aba Horários sem pergunta analítica (Alto).** 02 §4.8 e 03 §2 preveem a aba a partir de
logs de urna. Não há pergunta definida que o horário de votação responda sobre transferência de
votos, o custo de ingestão é alto (logs por urna, nacionalmente) e a aba convida a leitura de
"horário suspeito", contra as próprias regras editoriais. Proposta: retirar do escopo até existir
uma pergunta legítima (por exemplo, filas e distribuição do comparecimento ao longo do dia) com
método próprio.

**Enquadramento do produto.** A visão fala em "reproduzir a thread". Componentes da thread que se
apoiam em correlação ou horário como indício não devem ser reproduzidos como análises; o valor do
produto está nos dados observados, nos limites e na incerteza honesta.

---

## B. Correção matemática e estatística

### B.1 A identidade contábil é intra-turno (C2, Crítico)

Em cada seção, com comparecimento C, votos A e B dos finalistas, outros O e inválidos I:

- 1º turno: C₁ = A₁ + B₁ + O₁ + I₁
- 2º turno: C₂ = A₂ + B₂ + I₂

Subtraindo: **ΔA + ΔB = O₁ + ΔC − ΔI**, com ΔI = I₂ − I₁.

A igualdade decorre só de "comparecimento = soma dos votos" **em cada turno separadamente**.
Consequências:

- Resíduo diferente de zero aponta erro de dado ou de categoria dentro de um turno (por exemplo,
  votos anulados fora das categorias), não problema entre turnos.
- **Um pareamento errado de seções entre turnos também dá resíduo zero.** O invariante I2
  (arquitetura §2.2), 02 §5.4 e 03 §12, item 6, tratam a identidade como verificação entre turnos e
  superestimam o que ela verifica.
- Na interface, o waterfall (02 §4.3) é uma boa explicação, mas deve ser apresentado como
  aritmética, nunca como "reconciliação entre turnos" (02 §1, objetivo 2).

**O que falta:** checagens próprias de harmonização, como aptos iguais entre turnos (ou diferença
explicada), mesma zona e local de votação, unicidade do pareamento, cobertura, e soma das seções
contra os totais oficiais por turno.

### B.2 Limites determinísticos (M1, Médio)

Sem restrições adicionais, numa seção com totais de origem rᵢ, totais de destino cⱼ e total N, os
limites de cada célula são os de Fréchet/Duncan-Davis, em fórmula fechada:

    max(0, rᵢ + cⱼ − N) ≤ xᵢⱼ ≤ min(rᵢ, cⱼ)

Como as seções são independentes, **o limite municipal de um fluxo é a soma dos limites das
seções**. Isso é bem mais informativo que limites calculados só com margens municipais (o
`constraint_scope = municipal_margins` de 03 §8).

Consequências para a especificação:

- LP (02 §5.5) só é necessário com restrições adicionais (célula zerada, retenção mínima). A
  fórmula fechada serve de oráculo para os testes.
- Restrições definidas por seção mantêm o problema separável (soma de LPs pequenos). Restrições
  que **ligam seções**, como "mesma taxa de retenção em todas as seções", não são separáveis e
  exigem um LP municipal. A especificação deve dizer qual tipo de cenário é permitido.

### B.3 Conferência da crítica da visão

- **Argumento dos "206 votos":** o mínimo de votos de A vindos de inválidos e abstenção numa seção
  é max(0, A₂ − A₁ − B₁ − O₁) sem restrição, e max(0, A₂ − A₁ − O₁) se não houver fluxo de B para A.
  A visão está certa: o número da thread depende da hipótese de ausência de fluxo B→A.
- **Matriz alternativa** da visão §3: linhas e colunas somam os totais publicados. A conclusão
  ("acertar os totais não valida o modelo") está correta.
- **Graus de liberdade:** (5 − 1)(4 − 1) = 12 por seção, como na visão.

### B.4 Mediana posterior não fecha margens (A1, Alto)

03 §9 permite `estimate_statistic = posterior_median`, e o mesmo parágrafo exige que a matriz
pontual respeite os totais; `CLAUDE.md` e 02 §4.5 proíbem reescalar. Essas regras são
incompatíveis: a soma das medianas das células não é a mediana da soma e, em geral, não fecha
as margens. A **média posterior das contagens** fecha por linearidade da esperança (cada amostra
fecha). Proposta: Sankey e matriz pontual só com média posterior de contagens; mediana e quantis
apenas como colunas por célula na tabela.

### B.5 Normalização "por 100 aptos" (parte de A5)

Quando os aptos de uma seção mudam entre turnos (C3), "por 100 aptos" é ambíguo: aptos do 1º, do
2º ou a média? O denominador precisa ser fixado no contrato.

---

## C. Dados do TSE e população fechada

**C3 — Voto em trânsito e seções especiais (Crítico).** A matriz origem × destino (5 × 4, com
abstenção) só fecha se o conjunto de eleitores aptos de cada unidade for o mesmo nos dois turnos.
Pelas regras de 2026:

- o voto em trânsito é solicitado por turno e pode ser para cidades diferentes em cada turno;
- só funciona em capitais e em municípios com mais de 100 mil eleitores;
- para o 2º turno de 2026, cerca de 314 mil eleitores pediram trânsito.

O eleitor em trânsito sai da seção de origem naquele turno e aparece numa seção especial em outro
município. Isso altera os aptos por seção entre turnos em pequenas quantidades espalhadas por todo
o país (origem) e concentradas nas seções de trânsito (destino). Seções especiais (por exemplo, em
estabelecimentos prisionais) têm dinâmica própria.

A especificação marca `changed_electorate` (03 §7) e manda "bloquear modelo fechado até tratamento
explícito" (`CLAUDE.md`, 02 §4.3), mas o tratamento não existe. Na prática, ou o bloqueio atinge
muitas unidades, ou alguém relaxa a regra sem registro. **Definir antes da Fase 2:**

- excluir seções de trânsito e especiais da matriz fechada e reportá-las à parte;
- para diferenças pequenas de aptos, usar categorias explícitas de entrada e saída ou uma
  tolerância documentada, com seu efeito nos limites;
- medir a magnitude com os dados de 2022 antes de fixar a regra.

**M2 — Categorias de voto incompletas (Médio).** A especificação reduz tudo a A, B, outros,
inválidos e abstenção. Faltam regras para:

- votos anulados por decisão judicial (candidatura sub judice), que não são brancos nem nulos
  comuns;
- brancos e nulos separados (o contrato só tem a soma);
- votação por cédula ou urna de contingência;
- seções anuladas.

Cada uma muda em que categoria o voto entra e, portanto, a identidade e as margens.

**M3 — Reconciliação "exata" pode bloquear legitimamente (Médio).** 02 §5.4 e 04 Fase 1A exigem
soma das seções igual ao total oficial, bloqueando a publicação. Há divergências legítimas
(seções anuladas, retotalização, diferença de escopo entre arquivos). Proposta: lista fechada de
divergências explicadas, cada uma com código e registro em `qualidade.json`; bloquear só a
divergência sem explicação.

---

## D. Qualidade e completude da especificação

**A5 — Contrato insuficiente para implementar e testar (Alto).**

- 03 §12 manda validar contra JSON Schema, mas **nenhum schema existe**.
- Enums ausentes: `validation_status` (o exemplo usa `passed`; a fixture usa `demo_only`), o
  `status` de `resumo.json`, `unit_type` de unidades harmonizadas.
- Arquivos sem esquema: `cenarios.parquet` (só quatro campos em 03 §11), `horarios.parquet`,
  `models.json`. `qualidade.json` tem apenas "mínimos" (03 §10).
- Falta o mapa entre `features`, chaves de `assets` e arquivos (por exemplo, `ecological_model` ↔
  `fluxos_estimados.parquet`, `scenarios` ↔ `cenarios.parquet`).
- Denominadores indefinidos: o que conta como seção "esperada" (instalada, agregada, anulada) em
  `coverage_fraction`; "por 100 aptos" (§B.5).

**A6 — Inconsistências entre documentos (Alto).**

| Tema | Onde diverge |
|---|---|
| `release_id` | 03 §3 usa `2026-10-27_r001` e uma release com várias eleições; arquitetura §7 usa `<election_id>-<timestamp UTC>`, uma eleição por release |
| `election_id` | 03 usa `2026-presidente-2t`; arquitetura §7 usa `config/eleicoes/<election_id>.yml` com exemplos `2026-presidente` |
| Versões | 03 §5: `pipeline_version`, `method_version`; 04: `app_version`, `pipeline_git_sha`, `method_version`; arquitetura I6: "versão Silver", `model_version` |
| Categorias | arquitetura §2.1: `finalist_a`, `finalist_b`, `other`; 03: `candidate_a`, `candidate_b`, `others_t1` |
| Classe de evidência | arquitetura I4: por valor; 03 §1, item 6: por valor **ou** por arquivo; `secoes.parquet` não tem coluna |
| Métodos na tela | arquitetura §4.3: "os três lado a lado"; 02 §4.5: seletor entre limites e modelo |
| Status do resumo | `resumo.status` (03 §6) e `manifest.features.summary` (03 §5) |

**A7 — Atribuição dos slots A/B (Alto).** 01 §2 diz que A e B são definidos "pela ordem explícita no
`manifest.json` daquela disputa", mas o manifesto (03 §5) não tem esse campo e é por município.
Sem uma regra **nacional e determinística** (por exemplo, número de urna ou ordem do resultado
nacional do 1º turno, gravada no catálogo), o mesmo candidato pode mudar de slot e de cor entre
municípios.

**A8 — Critérios sem número (Alto).** "Diagnóstico aprovado" (03 §5, 04 Fase 3), "tolerância
explicada no método" (03 §9), "informação insuficiente" (02 §5.6), "baixa identificabilidade" e
"mínimo de seções" não têm limiar. Sem número, os critérios não podem ser verificados por
`validate_web_bundle()` nem por testes. Proposta: tabela de limiares versionada em
`config/assumptions.yml` ou similar, publicada na página de metodologia.

**Duplicação residual (Baixo).** 02 §5 (engenharia de dados) e arquitetura §4 (camadas) cobrem o
mesmo terreno com granularidade diferente; manter requisitos em 02 e implementação na arquitetura.

---

## E. Engenharia

**M4 — Ordem das fases (Médio).** A Fase 0 constrói a interface antes de qualquer contato com os
arquivos reais do TSE, e o contrato 03 fixa colunas que talvez não existam por seção e por turno.
Proposta: um teste exploratório curto com uma UF de 2022 (dois turnos completos) antes de
congelar o contrato 1.0.0, verificando aptos por seção, agregação, trânsito e categorias de voto.

**M5 — Atritos de stack e hospedagem (Médio).**

- **Quarto e "sem UI kit":** sites Quarto usam Bootstrap como base de tema. Cumprir o guia visual
  exige SCSS próprio que neutralize Bootstrap; vale um teste visual cedo.
- **Peso inicial:** o DudesApp carrega o Plotly no `<head>` (vários MB). Isso viola o orçamento de
  250 KB iniciais (02 §8). O Plotly precisa ser carregado sob demanda, como o DuckDB-Wasm.
- **Limites de arquivos:** o Cloudflare Pages permite 20 mil arquivos por site no plano gratuito e
  100 mil nos pagos. Manifesto, resumo e qualidade por município somam cerca de 17 mil arquivos por
  eleição e por release, então o plano de dados separado (ADR-05) é necessário desde a primeira
  release nacional.
- **Custo de MCMC:** 5.570 municípios × métodos × análises de sensibilidade × releases. Medir por
  UF antes da Fase 3 (a arquitetura §14 já aponta).
- **Reprodutibilidade:** MCMC com seed fixa reproduz na mesma plataforma; entre sistemas e versões
  de BLAS, a igualdade é numérica com tolerância, não bit a bit. Documentar isso.

**M6 — Escolha de métodos (Médio).** `eiPack` (0.2-2) está no CRAN e é um bom ponto de partida. Há
pacotes desenhados especificamente para transferência de votos entre duas eleições: `lphom`
(Pavía e Romero; programação linear sob homogeneidade) e `ecolRxC` (Pavía e Thomsen, 2025). Devem
entrar na comparação de sensibilidade (C1).

---

## F. O que é impossível ou incorreto

| # | Afirmação ou exigência | Por quê | Reformulação |
|---|---|---|---|
| 1 | Publicar estimativa ecológica municipal "validada" | Sem verdade de campo; diagnósticos internos não detectam viés de agregação | "Compatível com os dados sob as hipóteses H, com sensibilidade S"; "não identificado" quando a sensibilidade cobre os limites |
| 2 | Identidade contábil como verificação entre turnos | É intra-turno; pareamento errado passa | Checagens próprias de harmonização |
| 3 | Matriz pontual por mediana que respeite os totais sem reescalar | Soma das medianas ≠ mediana da soma | Só média posterior de contagens |
| 4 | Análise para "qualquer município" em qualquer eleição | Só há 2º turno em parte dos cargos e municípios | Elegibilidade por eleição no catálogo |
| 5 | Bloquear o modelo sempre que o eleitorado muda e ter cobertura nacional de estimativas | O voto em trânsito muda aptos em muitas seções | Regra explícita de exclusão e tolerância, medida em 2022 |

---

## G. Recomendações priorizadas

**P0 — antes da Fase 1A ou da Fase 2:**

1. Reescrever o critério de qualidade da inferência ecológica (C1) em 02 §4.5 e §5.6, 03 §5 e §9,
   04 Fase 3 e `CLAUDE.md`.
2. Separar a checagem intra-turno da harmonização entre turnos (C2) em arquitetura §2.2 (I2),
   02 §5.3–5.4 e 03 §12.
3. Definir o tratamento de trânsito, seções especiais e diferença de aptos (C3), com um ADR novo.
4. Expressar a elegibilidade por eleição (C4) em README, 02 §0–1 e 03 §4.
5. Teste exploratório com dados de 2022 antes de congelar o contrato (M4), no roteiro 04.

**P1 — antes de congelar o contrato 1.0.0:**

6. JSON Schema e enums completos; esquemas de cenários e modelos; mapa features ↔ assets ↔ arquivos;
   denominadores (A5).
7. Unificar `release_id`, `election_id`, versões, categorias e status (A6).
8. Regra nacional dos slots A/B no catálogo (A7).
9. Tabela de limiares versionada (A8).
10. Só média posterior para matriz pontual e Sankey (A1).
11. Categorias de voto do TSE e divergências explicadas na reconciliação (M2, M3).
12. Correlação normalizada, com mínimo de seções, intervalo e referência da UF (A3).
13. Decidir a retirada da aba Horários (A4).

**P2 — durante as Fases 2–4:**

14. Fórmula fechada como base dos limites e regra para cenários não separáveis (M1).
15. Política de pooling e de publicação no nível UF (A2).
16. Plotly sob demanda, tema Quarto sem Bootstrap aparente, plano de dados separado, medição de
    custo de MCMC (M5).
17. `lphom` e `ecolRxC` na comparação de métodos (M6).

---

## Tabela de achados

| ID | Severidade | Onde | Problema | Recomendação |
|---|---|---|---|---|
| C1 | Crítico | 02 §4.5, §5.6; 03 §5, §9; 04 Fase 3; `CLAUDE.md` | Critério de qualidade mede o cálculo, não a validade | Sensibilidade entre métodos, informação relativa aos limites, checagem preditiva, simulação fora das hipóteses |
| C2 | Crítico | arquitetura §2.2 (I2); 02 §1, §5.4; 03 §12 | Identidade é intra-turno; pareamento errado passa | Checagens de harmonização próprias |
| C3 | Crítico | 03 §7; 02 §4.3, §5.3; `CLAUDE.md` | População não é fechada (trânsito, seções especiais); tratamento indefinido | Exclusão e tolerância explícitas, medidas em 2022; ADR |
| C4 | Crítico | README; `CLAUDE.md`; 02 §0 | "Qualquer município" depende do cargo e do 2º turno | Elegibilidade por eleição no catálogo |
| A1 | Alto | 03 §9 | Mediana posterior não fecha margens | Média posterior para matriz pontual |
| A2 | Alto | visão §7; arquitetura §4.3 | Pooling transforma estimativa municipal em média regional | Limiar de informação local; publicar no nível UF |
| A3 | Alto | 02 §4.4 | Correlação mecânica, de escala e sujeita a multiplicidade | Normalizar, mínimo de seções, intervalo, referência da UF, sem ranking |
| A4 | Alto | 02 §4.8; 03 §2 | Horários sem pergunta analítica; risco de leitura de anomalia | Retirar do escopo |
| A5 | Alto | 03 §5–§12 | Sem JSON Schema, enums e esquemas de vários arquivos; denominadores indefinidos | Completar o contrato |
| A6 | Alto | 03; arquitetura §2, §4.3, §7; 02 §4.5; 04 | Identificadores, versões, categorias e status divergentes | Unificar vocabulário |
| A7 | Alto | 01 §2; 03 §4–§6 | Regra dos slots A/B inexistente no contrato | Regra nacional no catálogo |
| A8 | Alto | 02 §5.6; 03 §5, §9; 04 Fase 3 | Limiares sem número | Tabela de limiares versionada |
| M1 | Médio | 02 §5.5; 03 §8 | LP onde há fórmula fechada; cenários não separáveis sem regra | Fréchet como base e oráculo; regra de cenários |
| M2 | Médio | 03 §6–§7 | Categorias de voto do TSE incompletas | Regras para anulados, brancos/nulos, contingência, seções anuladas |
| M3 | Médio | 02 §5.4; 04 Fase 1A | Reconciliação exata bloqueia divergências legítimas | Divergências explicadas com código |
| M4 | Médio | 04 | Interface antes de validar contrato com dados reais | Teste exploratório com 2022 |
| M5 | Médio | arquitetura §4.5, §9; 02 §8 | Bootstrap, peso do Plotly, limite de arquivos, custo e reprodutibilidade de MCMC | Ver §E |
| M6 | Médio | arquitetura §4.3 | Métodos específicos de transferência não considerados | Incluir `lphom` e `ecolRxC` |

---

## Fontes externas

- `eiPack` no CRAN: https://cran.r-project.org/package=eiPack
- `lphom` no CRAN: https://cran.r-project.org/package=lphom
- `ecolRxC` no CRAN: https://cran.r-project.org/package=ecolRxC
- Rosen, O., Jiang, W., King, G. e Tanner, M. A. (2001). Bayesian and frequentist inference for
  ecological inference: the R×C case. *Statistica Neerlandica*, 55(2), 134–156.
- Voto em trânsito em 2026 (regras por turno, capitais e municípios com mais de 100 mil eleitores):
  https://investnews.com.br/economia/voto-em-transito/
- Pedidos de voto em trânsito para o 2º turno de 2026:
  https://www.tnh1.com.br/noticia/nid/mais-de-314-mil-pessoas-solicitaram-voto-em-transito-para-o-2-turno-das-eleicoes/
- Segundo turno para prefeito em municípios com mais de 200 mil eleitores: Constituição Federal,
  art. 29, II — https://www.planalto.gov.br/ccivil_03/constituicao/constituicao.htm
- Limites do Cloudflare Pages: https://developers.cloudflare.com/pages/platform/limits/

As regras do voto em trânsito devem ser confirmadas na resolução do TSE da eleição antes de
implementar o tratamento de C3.
