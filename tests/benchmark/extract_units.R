# Script de apoio ao benchmark e à calibração do método (não é a camada oficial de dados).
#
# Monta, com DuckDB, a tabela nacional de unidades no formato de R/README.md a partir dos CSV
# do TSE já descompactados. A camada oficial (R/normalize, R/reconcile) é responsabilidade do
# pipeline de dados; aqui só aplicamos as regras mínimas para medir custo:
#   - exterior (ZZ) fora; seções não instaladas fora;
#   - classes de população de 05 §3.2 com tau = max(2, 1% de E1);
#   - sem identificação de seções de trânsito/especiais (fica para a camada oficial).
#
# Uso: Rscript tests/benchmark/extract_units.R <dir_csv> <arquivo_saida.parquet>

suppressPackageStartupMessages({
  library(DBI)
})

args <- commandArgs(trailingOnly = TRUE)
dir_csv <- args[[1]]
out <- args[[2]]

con <- dbConnect(duckdb::duckdb())
on.exit(dbDisconnect(con, shutdown = TRUE))

csv_opts <- "delim=';', header=true, quote='\"', encoding='latin-1', all_varchar=true"
votos <- file.path(dir_csv, "votacao_secao_2026_BR.csv")
detalhe <- file.path(dir_csv, "detalhe_votacao_secao_2026_BR.csv")

dbExecute(con, sprintf("
CREATE TABLE votos AS
SELECT SG_UF AS uf, CD_MUNICIPIO AS municipio_tse, NR_ZONA AS zona, NR_SECAO AS secao,
       CAST(NR_TURNO AS INTEGER) AS turno, NR_VOTAVEL AS votavel, CAST(QT_VOTOS AS INTEGER) AS votos
FROM read_csv('%s', %s)
WHERE DS_CARGO = 'Presidente' AND SG_UF <> 'ZZ'", votos, csv_opts))

dbExecute(con, sprintf("
CREATE TABLE det AS
SELECT SG_UF AS uf, CD_MUNICIPIO AS municipio_tse, NR_ZONA AS zona, NR_SECAO AS secao,
       CAST(NR_TURNO AS INTEGER) AS turno, CAST(QT_APTOS AS INTEGER) AS aptos,
       CAST(QT_COMPARECIMENTO AS INTEGER) AS comp, ST_SECAO_INSTALADA AS instalada
FROM read_csv('%s', %s)
WHERE DS_CARGO = 'Presidente' AND SG_UF <> 'ZZ'", detalhe, csv_opts))

dbExecute(con, "
CREATE TABLE agg AS
SELECT uf, municipio_tse, zona, secao, turno,
       SUM(CASE WHEN votavel = '13' THEN votos ELSE 0 END) AS a,
       SUM(CASE WHEN votavel = '22' THEN votos ELSE 0 END) AS b,
       SUM(CASE WHEN votavel IN ('95','96') THEN votos ELSE 0 END) AS i,
       SUM(CASE WHEN votavel NOT IN ('13','22','95','96') THEN votos ELSE 0 END) AS o
FROM votos GROUP BY ALL")

dbExecute(con, sprintf("
COPY (
WITH s AS (
  SELECT d1.uf, d1.municipio_tse, d1.zona, d1.secao,
         d1.aptos AS e1, d2.aptos AS e2, d1.comp AS c1, d2.comp AS c2,
         d1.instalada = 'Sim' AND d2.instalada = 'Sim' AS inst,
         coalesce(v1.a,0) AS a1, coalesce(v1.b,0) AS b1, coalesce(v1.o,0) AS o1, coalesce(v1.i,0) AS i1,
         coalesce(v2.a,0) AS a2, coalesce(v2.b,0) AS b2, coalesce(v2.i,0) AS i2
  FROM det d1
  JOIN det d2 ON d1.uf=d2.uf AND d1.municipio_tse=d2.municipio_tse AND d1.zona=d2.zona AND d1.secao=d2.secao AND d2.turno=2
  LEFT JOIN agg v1 ON v1.uf=d1.uf AND v1.municipio_tse=d1.municipio_tse AND v1.zona=d1.zona AND v1.secao=d1.secao AND v1.turno=1
  LEFT JOIN agg v2 ON v2.uf=d1.uf AND v2.municipio_tse=d1.municipio_tse AND v2.zona=d1.zona AND v2.secao=d1.secao AND v2.turno=2
  WHERE d1.turno = 1
)
SELECT '2026-presidente' AS election_id, uf, municipio_tse,
       municipio_tse || '-' || zona || '-' || secao AS comparison_unit_id, zona, secao,
       CASE WHEN e2 = e1 THEN 'closed' ELSE 'net_change' END AS population_status,
       a1 AS o_A, b1 AS o_B, o1 AS o_O, i1 AS o_I, e1 - c1 AS o_X, greatest(e2 - e1, 0) AS o_N,
       a2 AS d_A, b2 AS d_B, i2 AS d_I, e2 - c2 AS d_X, greatest(e1 - e2, 0) AS d_S,
       e1 AS eligible_t1
FROM s
WHERE inst AND abs(e2 - e1) <= greatest(2, floor(0.01 * e1))
ORDER BY uf, municipio_tse, zona, secao
) TO '%s' (FORMAT parquet, COMPRESSION zstd)", out))

res <- dbGetQuery(con, sprintf("
SELECT count(*) AS units, count(DISTINCT municipio_tse) AS municipios,
       sum(CASE WHEN o_A+o_B+o_O+o_I+o_X+o_N <> d_A+d_B+d_I+d_X+d_S THEN 1 ELSE 0 END) AS desbalanceadas
FROM read_parquet('%s')", out))
print(res)
