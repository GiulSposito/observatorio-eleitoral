# Projeto: Observatório Eleitoral Municipal

A proposta é tecnicamente viável, e R + Parquet + WebAssembly é uma combinação interessante para implementá-la. Eu estruturaria a solução como um motor de análise eleitoral reproduzível, capaz de processar os resultados de todas as seções eleitorais do Brasil e publicar análises interativas por município, sem depender de um backend de aplicação.

O ponto mais importante é separar três coisas: a contabilidade exata dos votos, a análise estatística de padrões entre seções e a inferência sobre possíveis transferências de eleitores. Elas têm níveis de certeza muito diferentes.

## 1. O que a thread analisa

A thread de Rômulo Fiúza e Mello foi publicada em 26 de outubro de 2026. Ela investiga uma aparente inconsistência na evolução dos votos de Lula e Flávio Bolsonaro entre os dois turnos da eleição presidencial em Lebon Régis, Santa Catarina, utilizando os boletins de urna das 30 seções eleitorais do município.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://threadreaderapp.com\&sz=32)

Thread Reader App



O ponto de partida é a seguinte comparação:

| Indicador         | 1º turno | 2º turno | Variação |
| ----------------- | -------- | -------- | -------- |
| Lula              | 2.899    | 3.503    | +604     |
| Flávio Bolsonaro  | 3.245    | 3.481    | +236     |
| Outros candidatos | 456      | —        | -456     |
| Votos válidos     | 6.600    | 6.984    | +384     |
| Brancos e nulos   | 313      | 182      | -131     |
| Comparecimento    | 6.913    | 7.166    | +253     |

1º turno

2º turno

09501.9002.8503.800LulaFlávioOutrosBrancos/nulos

Lebon Régis/SC · Comparação divulgada na thread · votos absolutos

A primeira descoberta é uma identidade contábil:

\\[ \underbrace{456}\_{\text{outros candidatos}} +\underbrace{253}\_{\text{mais votantes}} +\underbrace{131}\_{\text{redução brancos/nulos}} =\underbrace{604+236}\_{\text{ganhos dos finalistas}} =840 \\]

Ou seja, o crescimento dos dois finalistas é integralmente compatível com a redistribuição dos votos de outros candidatos, a participação adicional e a redução dos votos inválidos.

Isso não prova que nenhum eleitor tenha trocado de candidato. Demonstra apenas que não é necessário pressupor essa migração para explicar os totais. Essa distinção vai determinar a metodologia do projeto.

## 2. O que seria necessário reproduzir da thread

A thread contém 14 posts e combina análises descritivas, modelagem estatística e investigação dos logs das urnas. Ela não é apenas uma análise de transferência de votos.

Organizei seus componentes como funcionalidades de um produto genérico.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://teapawt.org\&sz=32)

teapawt

[image](https://www.google.com/s2/favicons?domain=https://teapawt.org\&sz=32)

teapawt



| Análise                 | O que a thread faz                                   | Como reproduzir em R                     |
| ----------------------- | ---------------------------------------------------- | ---------------------------------------- |
| Reconciliação eleitoral | Confere votos, abstenção, brancos e nulos            | Agregações e identidades contábeis       |
| Evolução por seção      | Compara ganhos dos candidatos nas 30 seções          | `dplyr`, `duckdb`, `ggplot2`             |
| Terceiros candidatos    | Identifica os 456 votos disponíveis no 1º turno      | Agregação por candidato e seção          |
| Inferência ecológica    | Estima a origem e o destino dos votos                | Modelos ecológicos e otimização          |
| Fluxo de votos          | Apresenta um Sankey de transferências estimadas      | Matriz de transição pré-computada        |
| Correlações             | Relaciona ganho de votos e mudança na participação   | Correlação, regressão e diagnósticos     |
| Análise territorial     | Compara seções e locais de votação                   | Agrupamentos por local, zona e município |
| Contrafactuais          | Testa como seriam os resultados sob outras hipóteses | Simulação restrita por margens           |
| Horários de votação     | Examina eventos registrados nos logs                 | Parser de logs e agregação temporal      |
| Incerteza               | Reestima os fluxos com 150 reamostragens             | Bootstrap e análise de sensibilidade     |

É possível reproduzir todos esses tipos de análise. Porém, não necessariamente os números exatos do Sankey original: a thread não disponibiliza o código, o procedimento completo de estimação nem as restrições utilizadas.

Essa lacuna importa bastante.

## 3. Minha principal crítica à metodologia

### A inferência ecológica não identifica transferências individuais

O autor apresenta, entre outras, as seguintes estimativas:

Abstiveram-se no 1º turno → Lula

## 478

Brancos/nulos no 1º turno → Lula

## 194

Outros candidatos → Flávio

## 292

Fluxos estimados pelo autor, não transferências individuais observadas.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://teapawt.org\&sz=32)

teapawt

O problema matemático é que temos apenas as margens de uma matriz de transição.

No exemplo da thread, seriam cinco categorias de origem e quatro de destino:

\\[ \text{Origem} = \begin{bmatrix} Lula & Flávio & Outros & Inválidos & Abstenção \end{bmatrix} \\]

\\[ \text{Destino} = \begin{bmatrix} Lula & Flávio & Inválidos & Abstenção \end{bmatrix} \\]

Uma matriz \\(5 \times 4\\) tem 20 células desconhecidas. Conhecemos somente cinco somas das linhas e quatro somas das colunas, sendo uma dessas restrições redundante.

Portanto, ainda restam:

\\[ (5-1)(4-1)=12 \\]

Doze graus de liberdade por seção eleitoral, antes de acrescentar hipóteses estatísticas. Com 30 seções, há muita informação, mas ainda não existe uma identificação única dos fluxos.

Para ilustrar, esta matriz alternativa também reproduz exatamente os totais municipais:

| Origem no 1º turno | Lula no 2º | Flávio no 2º | Inválidos | Abstenção |
| ------------------ | ---------- | ------------ | --------- | --------- |
| Lula               | 2.899      | 0            | 0         | 0         |
| Flávio             | 604        | 2.641        | 0         | 0         |
| Outros             | 0          | 456          | 0         | 0         |
| Inválidos          | 0          | 131          | 182       | 0         |
| Abstenção          | 0          | 253          | 0         | 1.571     |
| Total              | 3.503      | 3.481        | 182       | 1.571     |

Ela corresponde a uma narrativa completamente diferente. É um exemplo de possibilidade nas margens municipais, não uma afirmação de que isso ocorreu nem de que satisfaça todas as 30 matrizes seccionais.

A consequência é importante: acertar exatamente os totais não valida, por si só, o modelo de transferência.

### Há uma ressalva também sobre os 206 votos

O autor afirma que pelo menos 206 votos de Lula necessariamente vieram de pessoas que haviam se abstido ou votado branco/nulo, porque o ganho dele excedeu o número de votos de terceiros em determinadas seções.

Esse limite não é incondicional. Ele pressupõe que não exista contribuição líquida de transferências de Flávio para Lula, ou impõe alguma restrição equivalente. Com transferências cruzadas, o limite muda.

A solução deveria distinguir três classes de resultado:

| Classe            | Exemplo                                               | Como apresentar                  |
| ----------------- | ----------------------------------------------------- | -------------------------------- |
| Observado         | Lula cresceu 604 votos                                | Número exato                     |
| Limite matemático | Mínimo/máximo de um fluxo sob determinadas restrições | Intervalo e hipóteses explícitas |
| Estimado          | Cerca de 478 antigos abstencionistas votaram em Lula  | Estimativa + incerteza + modelo  |

Também há uma cautela sobre a correlação de 0,83. A variação de votos de Lula e Flávio é contabilmente relacionada à variação do comparecimento, dos inválidos e dos votos de terceiros. Portanto, parte da associação pode decorrer da própria identidade matemática, não somente de comportamento eleitoral.

Minha sugestão é construir um produto metodologicamente mais sólido que a thread, não simplesmente automatizar as conclusões dela.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://teapawt.org\&sz=32)

teapawt



## 4. Arquitetura proposta

Eu escolheria uma arquitetura batch-first: toda computação estatística relevante ocorre em R; o navegador trabalha apenas com resultados materializados e consultas locais.

PIPELINE DE DADOS E ANÁLISE — R

TSE · Dados abertos

Resultados por seção · BUs · Eleitorado · Locais · Logs

Bronze — Raw

Downloads, hashes, versões e proveniência

Silver — Normalized

Seções harmonizadas, candidatos, comparecimento

Motor analítico em R

Contabilidade

Inferência ecológica

Correlação e cenários

Bootstrap e diagnósticos

Gold — Parquet publicado

Indicadores nacionais, resumos e análises de cada município

SITE ESTÁTICO — BROWSER

DuckDB-Wasm

Consultas locais

Interface Web

Gráficos e mapas

Não há necessidade de Python, banco de dados transacional, API ou servidor R em produção.

### Stack recomendada

| Camada                      | Tecnologia                       | Papel                               |
| --------------------------- | -------------------------------- | ----------------------------------- |
| Orquestração                | `targets` + `renv`               | Pipeline incremental e reproduzível |
| Extração                    | `httr2`, `curl`                  | Downloads do TSE                    |
| Processamento               | `data.table` + DuckDB em R       | Trabalhar com volumes grandes       |
| Armazenamento               | `arrow`, Parquet/ZSTD            | Camadas Silver e Gold               |
| Modelagem                   | R, `eiPack`, otimização linear   | Inferência e limites                |
| Validação                   | `testthat`, `checkmate`          | Qualidade e testes                  |
| Visualizações exploratórias | `ggplot2`                        | Validação offline                   |
| Frontend                    | SvelteKit estático ou React/Vite | Site interativo                     |
| Consultas no navegador      | `@duckdb/duckdb-wasm`            | SQL sobre Parquet                   |
| Gráficos                    | Observable Plot + D3/Sankey      | Visualização                        |
| Publicação                  | Cloudflare Pages/R2 ou S3/CDN    | Hospedagem estática                 |

O DuckDB-Wasm consegue ler Parquet remoto sob demanda, inclusive intervalos de bytes quando a configuração HTTP permite. É justamente a capacidade adequada para este produto.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://duckdb.org\&sz=32)

DuckDB

[image](https://www.google.com/s2/favicons?domain=https://duckdb.org\&sz=32)

DuckDB



## 5. Fontes de dados: o que já existe e o que precisa ser tratado

[Resultados eleitorais por seção — TSE](https://dadosabertos.tse.jus.br/dataset/resultados-2026?utm_source=chatgpt.com)

Fonte prioritária para resultados, votos por candidato e totais de seção. Oferece arquivos de votação por seção e detalhe da apuração.

[image](https://www.google.com/s2/favicons?domain=https://dadosabertos.tse.jus.br\&sz=32)

Portal de Dados Abertos do TSE

[Boletins de urna de 2026 — TSE](https://dadosabertos.tse.jus.br/dataset/resultados-2026-boletim-de-urna?utm_source=chatgpt.com)

Fonte para reproduzir a conferência urna por urna. Os recursos são publicados por UF e turno, com arquivos de verificação.

[image](https://www.google.com/s2/favicons?domain=https://dadosabertos.tse.jus.br\&sz=32)

Portal de Dados Abertos do TSE

[Eleitorado e locais de votação — TSE](https://dadosabertos.tse.jus.br/dataset/eleitorado-2026?utm_source=chatgpt.com)

Permite enriquecer as seções com dados de eleitorado e agrupamento por local de votação.

[image](https://www.google.com/s2/favicons?domain=https://dadosabertos.tse.jus.br\&sz=32)

Portal de Dados Abertos do TSE

Atenção à disponibilidade: na consulta de 27 de outubro de 2026, a página de downloads de boletins em lote ainda exibia apenas os recursos do primeiro turno. Isso não significa que os resultados ou BUs individuais do segundo turno sejam inexistentes. O pipeline deve ter adaptadores para downloads em lote e, quando necessário, coleta individual dos BUs publicados.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://dadosabertos.tse.jus.br\&sz=32)

Portal de Dados Abertos do TSE

[image](https://www.google.com/s2/favicons?domain=https://github.com\&sz=32)

GitHub



Há ainda dois projetos públicos que merecem avaliação, sem necessariamente incorporá-los como dependências:

- [analise-eleicoes-2026](https://github.com/andreagnoletto/analise-eleicoes-2026?utm_source=chatgpt.com): contém rotinas de ingestão de BUs, DuckDB e processamento de logs; útil para estudar layouts, escala e conferências.
- [DataUrnas-BR](https://github.com/alissonlinneker/DataUrnas-BR?utm_source=chatgpt.com): documenta uma extração de dados por seção com armazenamento em Parquet, identificação de seções agregadas e reconciliação com totais oficiais.&#x20;

  [image](https://www.google.com/s2/favicons?domain=https://github.com\&sz=32)

  GitHub

  [image](https://www.google.com/s2/favicons?domain=https://github.com\&sz=32)

  GitHub



Esses projetos podem acelerar bastante a investigação técnica do formato, mesmo mantendo todo o motor analítico em R.

## 6. Modelo de dados canônico

O maior trabalho de engenharia não será o gráfico: será harmonizar corretamente os dados dos dois turnos.

Eu criaria quatro entidades principais.

| Dataset              | Granularidade                | Principais campos                                         |
| -------------------- | ---------------------------- | --------------------------------------------------------- |
| `vote_facts`         | Seção × turno × candidato    | Eleição, UF, município TSE, zona, seção, candidato, votos |
| `section_turnout`    | Seção × turno                | Aptos, comparecimento, abstenção, brancos, nulos, status  |
| `section_comparison` | Seção × par de turnos        | Votos dos finalistas, terceiros, inválidos, deltas        |
| `municipal_analysis` | Município × eleição × modelo | Indicadores, diagnósticos, estimativas e intervalos       |

E uma tabela adicional, fundamental para o Sankey:

`transition_estimates`

| Campo            | Significado                                          |
| ---------------- | ---------------------------------------------------- |
| `municipio_tse`  | Município analisado                                  |
| `election_id`    | Eleição/cargo/turnos                                 |
| `origin`         | Categoria de origem                                  |
| `destination`    | Categoria de destino                                 |
| `estimate`       | Fluxo estimado                                       |
| `lower`, `upper` | Intervalo de incerteza ou limites, conforme o método |
| `method_id`      | Modelo utilizado                                     |
| `assumption_id`  | Conjunto de restrições                               |
| `model_version`  | Versão reproduzível                                  |
| `status`         | Convergência e confiabilidade                        |

Uma questão específica do TSE: código de município eleitoral não é o código IBGE. Deve existir uma tabela de correspondência oficial entre eles. Também é necessário tratar seções agregadas, seções alteradas entre turnos, transferências temporárias e variação do eleitorado apto.

Se os totais de eleitores aptos diferirem entre os turnos, não se deve forçar uma matriz de transição fechada como se o conjunto de pessoas fosse exatamente o mesmo. Esse caso requer um tratamento explícito de entradas/saídas ou uma unidade de comparação harmonizada.

## 7. Como implementar a análise ecológica

Eu implementaria três métodos, em vez de depender de uma única estimativa.

Método A — Restrições matemáticas

Montar um problema de transporte por seção, com linhas de origem, colunas de destino e fluxos não negativos. Resolver a minimização e a maximização de cada célula para encontrar seus limites possíveis, usando programação linear.

Resultado: intervalos que representam o que os totais permitem, sem fingir conhecer transferências individuais.

Método B — Inferência ecológica estatística

Estimar probabilidades compartilhadas ou parcialmente compartilhadas de transferência entre categorias, utilizando o padrão observado nas seções.

O pacote [eiPack::ei.MD.bayes](https://search.r-project.org/CRAN/refmans/eiPack/html/ei.MD.bayes.html?utm_source=chatgpt.com) implementa um modelo hierárquico para tabelas RxC e é uma boa referência inicial, embora não seja necessariamente o modelo definitivo.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://search.r-project.org\&sz=32)

Omega Search



Método C — Cenários contrafactuais

Comparar resultados sob hipóteses explícitas: ausência de trocas entre finalistas, retenção parcial, distribuição proporcional dos novos votos, preferências distintas de terceiros e assim por diante.

O objetivo é mostrar quais conclusões dependem de qual hipótese, e não eleger uma narrativa antecipadamente.

### Por que o modelo precisa ser hierárquico

Lebon Régis tem 30 seções. Outros municípios terão poucas seções, enquanto grandes cidades terão milhares.

Um modelo independente por município pode ser extremamente instável nos municípios pequenos.

A alternativa que eu exploraria é um modelo hierárquico com partial pooling, permitindo compartilhar informação estatística entre municípios semelhantes sem tratar seus comportamentos como idênticos.

Importante: esse compartilhamento deve ficar visível na interface. A estimativa para um município com apenas algumas seções pode refletir fortemente as hipóteses do modelo e dados de outras localidades.

Eu também usaria bootstrap ou simulação posterior, múltiplos pontos iniciais, diagnósticos de convergência e comparação entre especificações. Os 150 reprocessamentos da thread são um ponto de partida, mas não bastam, por si só, para certificar intervalos estatísticos.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://teapawt.org\&sz=32)

teapawt



## 8. Pipeline reproduzível em R

Uma estrutura de repositório adequada seria:

```

observatorio-eleitoral/
├── _targets.R
├── renv.lock
├── config/
│   └── eleicao-2026-presidencial.yml
├── R/
│   ├── tse_download.R
│   ├── tse_parse.R
│   ├── normalize.R
│   ├── reconcile.R
│   ├── ecological_bounds.R
│   ├── ecological_model.R
│   ├── bootstrap.R
│   ├── diagnostics.R
│   └── publish.R
├── tests/
├── data/
│   ├── bronze/
│   ├── silver/
│   └── gold/
└── site/
    ├── src/
    └── public/data/

```

O `_targets.R` ficaria conceitualmente próximo disto:

```

library(targets)

tar_option_set(
  packages = c("arrow", "duckdb", "dplyr", "data.table")
)

source("R/tse_download.R")
source("R/tse_parse.R")
source("R/normalize.R")
source("R/reconcile.R")
source("R/ecological_model.R")
source("R/publish.R")

list(
  tar_target(
    config,
    yaml::read_yaml("config/eleicao-2026-presidencial.yml")
  ),

  tar_target(
    fontes_uf,
    descobrir_fontes_tse(config)
  ),

  tar_target(
    arquivos_uf,
    baixar_verificar_fontes(fontes_uf),
    pattern = map(fontes_uf),
    format = "file"
  ),

  tar_target(
    dados_uf,
    normalizar_uf(arquivos_uf, config),
    pattern = map(arquivos_uf),
    format = "file"
  ),

  tar_target(
    analises_uf,
    analisar_exportar_municipios(dados_uf, config),
    pattern = map(dados_uf),
    format = "file"
  ),

  tar_target(
    indice,
    publicar_catalogo(analises_uf),
    format = "file"
  )
)

```

Esqueleto de arquitetura: as funções de domínio acima ainda precisam ser implementadas. O `targets` suporta ramificação dinâmica para distribuir o processamento.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://community.r-multiverse.org\&sz=32)

R-universe

A configuração separaria o motor do caso concreto:

```

election:
  year: 2026
  office: presidente
  first_round: 1
  second_round: 2

categories:
  first_round:
    - finalist_a
    - finalist_b
    - other
    - invalid
    - abstention
  second_round:
    - finalist_a
    - finalist_b
    - invalid
    - abstention

analysis:
  ecological_model: hierarchical
  compute_lp_bounds: true
  bootstrap_iterations: 1000
  minimum_sections: 10
  save_diagnostics: true

publication:
  format: parquet
  compression: zstd
  partition: municipality

```

O mínimo de 10 seções nesse exemplo é somente uma regra operacional ilustrativa; não há um limiar universal que torne a inferência ecológica confiável.

### Validações obrigatórias

Uma identidade central do pipeline é:

\\[ \Delta A+\Delta B = O_1+\Delta C-\Delta I \\]

em que \\(O_1\\) são votos de outros candidatos no primeiro turno, \\(\Delta C\\) é a mudança de comparecimento e \\(\Delta I\\) é a mudança no número de votos inválidos.

Em R:

```

verificar_saldos <- function(secoes) {
  secoes |>
    dplyr::mutate(
      delta_a = candidato_a_2 - candidato_a_1,
      delta_b = candidato_b_2 - candidato_b_1,
      delta_comparecimento =
        comparecimento_2 - comparecimento_1,
      reducao_invalidos =
        invalidos_1 - invalidos_2,

      residuo =
        delta_a + delta_b -
        (
          outros_1 +
          delta_comparecimento +
          reducao_invalidos
        )
    )
}

```

Nesse formato, para uma eleição com apenas dois finalistas no segundo turno, o resíduo deve ser zero. Diferenças exigem investigação dos dados ou da harmonização.

Mas isso é apenas uma checagem interna: é igualmente necessário comparar as somas com os resultados oficiais, verificar a cobertura de seções e registrar a integridade dos arquivos originais.

## 9. Como publicar os Parquets

Minha escolha seria uma arquitetura híbrida: um catálogo nacional pequeno e arquivos municipais carregados somente sob demanda.

```

public/data/
├── catalogo-municipios.json
└── 2026/
    └── presidente/
        ├── resumo-brasil.parquet
        ├── modelos.json
        └── municipios/
            ├── SC/
            │   ├── 00001/
            │   │   ├── secoes.parquet
            │   │   ├── analises.parquet
            │   │   └── fluxos.parquet
            │   └── ...
            ├── SP/
            └── ...

```

Os códigos são ilustrativos.

Ao abrir a aplicação, o navegador recebe apenas o catálogo de municípios. Depois que o usuário escolhe um município, carrega seus Parquets, não a base nacional inteira.

Eu evitaria milhares de arquivos minúsculos por indicador. Uma alternativa é ter somente um ou dois Parquets por município, com tipagem explícita, e arquivos maiores por UF quando for necessário comparar muitas cidades.

### DuckDB-Wasm no navegador

O acesso pode seguir este padrão:

```

import * as duckdb from "@duckdb/duckdb-wasm";

// db já inicializado com o bundle/worker do DuckDB-Wasm
const conn = await db.connect();

const path = `/data/2026/presidente/municipios/SC/00001/secoes.parquet`;

await db.registerFileURL(
  "secoes.parquet",
  path,
  duckdb.DuckDBDataProtocol.HTTP,
  false
);

const result = await conn.query(`
  SELECT
    zona,
    secao,
    candidato_a_1,
    candidato_a_2,
    candidato_b_1,
    candidato_b_2
  FROM 'secoes.parquet'
  ORDER BY zona, secao
`);

const sections = result.toArray();

```

O caminho deve vir de um catálogo validado, e não de uma string arbitrária do usuário. A infraestrutura estática também precisa permitir CORS e leituras HTTP parciais quando aplicável.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://duckdb.org\&sz=32)

DuckDB



### E o webR?

[webR](https://docs.r-wasm.org/webr/latest/?utm_source=chatgpt.com) executa código R em WebAssembly dentro do navegador, mas eu não o escolheria como peça principal deste produto.

O motivo: você quer pré-computar as análises, não refazer a inferência ecológica em cada dispositivo.

Usaria DuckDB-Wasm para consultas, filtros, comparações e agregações leves. O webR só faria sentido para uma funcionalidade adicional, como permitir que usuários avançados executem pequenas simulações próprias em R.

Isso mantém o site rápido e utilizável inclusive em celulares.

## 10. Como imagino a experiência do site

OBSERVATÓRIO ELEITORAL

Eleição presidencial · 2026

Lebon Régis — SC

Zona 77 · 30 seções eleitorais

Ganho A

# +604

votos

Ganho B

# +236

votos

Participação

# +253

votantes

ResumoSeçõesFluxosCenáriosQualidade

Auditoria e reprodutibilidade

Manifesto dos arquivos TSE, data da coleta, cobertura das seções, testes de reconciliação, versão do modelo e diagnósticos de convergência.

Wireframe conceitual com os dados divulgados para Lebon Régis. Não é uma aplicação conectada aos dados.

Na implementação, eu acrescentaria duas experiências especialmente úteis.

Comparação entre municípios: selecionar Lebon Régis e outra cidade, normalizar os indicadores por 100 eleitores aptos e verificar se os padrões são semelhantes.

Contextualização estatística: mostrar se o município está próximo ou distante do comportamento de municípios comparáveis na mesma UF, faixa populacional ou perfil eleitoral. Isso ajuda a evitar interpretações exageradas de uma única correlação local.

Os gráficos de horários das urnas ficariam em uma aba adicional, quando houver cobertura confiável dos logs. Esses registros permitem estudar o momento de votação, mas não identificar o candidato escolhido em cada evento.

## 11. Estratégia de desenvolvimento

Eu dividiria a construção em quatro entregas progressivas.

| Etapa                            | Escopo                                                                         | Resultado                                   |
| -------------------------------- | ------------------------------------------------------------------------------ | ------------------------------------------- |
| 1. Reproduzir Lebon Régis        | Carregar ambos os turnos, conferir seções e produzir os indicadores observados | Base factual validada                       |
| 2. Implementar o motor ecológico | Limites matemáticos, modelo probabilístico, Sankey e sensibilidade             | Reproduzir e melhorar o método da thread    |
| 3. Generalizar para o Brasil     | Pipeline por UF, parametrização de eleições, particionamento e catálogo        | Parquets para todos os municípios elegíveis |
| 4. Publicar o site               | Busca municipal, comparações, visualizações, metodologia e auditoria           | Site estático com DuckDB-Wasm               |

Eu começaria a etapa 1 usando os BUs originais de Lebon Régis e, paralelamente, os dados históricos de 2022 como um teste completo de dois turnos para a infraestrutura nacional. Assim, eventuais atrasos de publicação dos pacotes de 2026 não bloqueiam o desenvolvimento.

A cobertura nacional precisa ser tolerante a falhas: um município sem dados completos do segundo turno deve aparecer como incompleto, não receber uma estimativa fabricada. Municípios com poucas seções devem ter diagnósticos explícitos de baixa identificabilidade.

## 12. Minha avaliação final

Ingestão nacional de resultados em R: viável.

Parquets municipais pré-computados: muito adequado.

Site estático usando DuckDB-Wasm: adequado.

Inferir exatamente como indivíduos transferiram seus votos: não identificável apenas com dados agregados.

Reproduzir os fluxos numéricos exatos do autor: depende de informações metodológicas ainda não publicadas.

Minha escolha seria construir não apenas um reprodutor da thread, mas um observatório de dinâmica eleitoral com inferência ecológica transparente, no qual o usuário consegue descobrir o que aconteceu em seu município, explorar explicações possíveis e entender até onde os dados permitem chegar.

A decisão arquitetural mais importante é esta: R faz a computação científica e publica um produto de dados versionado; DuckDB-Wasm oferece uma interface interativa sobre esses resultados, sem precisar recalcular modelos pesados nem manter um backend.

Isso também deixa o projeto reutilizável para eleições presidenciais futuras e, com adaptações, disputas estaduais e municipais com segundo turno.