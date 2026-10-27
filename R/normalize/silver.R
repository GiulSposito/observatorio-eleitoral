# Silver: seção × turno a partir dos CSV do TSE (votação por seção + detalhe por seção).
#
# Saídas em <raiz>/silver/<election_id>/:
#   secao_turno.parquet  uma linha por seção instalada ou não × turno (exterior fora)
#   finalistas.json      os dois votáveis do 2º turno, com slot A/B pela regra nacional
#   municipios.parquet   código TSE, UF e nome oficial
#
# Votos nominais para candidatos sem destinação "Válido" na totalização oficial (arquivo de votação por
# município e zona) são nulos técnicos: o TSE os soma aos nulos. Em 2026, 1º turno, é o número 28
# (5.123 votos). Eles entram em `votes_null_tech` e na categoria I, nunca em "demais candidatos".
#
# Identificadores ficam como texto com zeros à esquerda: município com 5 dígitos, zona e seção com 4.

csv_reader <- function(path) {
  sprintf(
    "read_csv(%s, delim = ';', header = true, quote = '\"', encoding = 'latin-1', all_varchar = true)",
    sql_quote_path(path)
  )
}

extract_sources <- function(cfg, sources) {
  dest <- file.path(layer_dir("bronze", cfg$election_id), "extracted")
  out <- vapply(seq_len(nrow(sources)), function(i) {
    zip_extract_member(sources$local_path[i], sources$member[i], dest)
  }, character(1))
  names(out) <- sources$source_key
  out
}

# Finalistas: votáveis do 2º turno que não são branco nem nulo. Slot A = menor número de urna.
derive_finalists <- function(con, cfg) {
  df <- DBI::dbGetQuery(con, sprintf(
    "SELECT NR_VOTAVEL AS number, any_value(NM_VOTAVEL) AS name
       FROM vot WHERE NR_TURNO = '2' AND NR_VOTAVEL NOT IN ('%s', '%s')
      GROUP BY NR_VOTAVEL", cfg$votavel_branco, cfg$votavel_nulo))
  if (nrow(df) != 2L) stop("esperados 2 finalistas no 2º turno; encontrados ", nrow(df), call. = FALSE)
  df <- df[order(as.integer(df$number)), ]
  df$slot <- c("A", "B")
  tibble::as_tibble(df[, c("slot", "number", "name")])
}

build_silver <- function(cfg, extracted) {
  out_dir <- layer_dir("silver", cfg$election_id)
  paths <- c(
    secao_turno = file.path(out_dir, "secao_turno.parquet"),
    finalistas = file.path(out_dir, "finalistas.json"),
    municipios = file.path(out_dir, "municipios.parquet")
  )
  excl <- paste0("'", cfg$excluir_ufs, "'", collapse = ", ")
  with_db(function(con) {
    DBI::dbExecute(con, sprintf(
      "CREATE VIEW vot AS SELECT * FROM %s WHERE CD_CARGO = '%s' AND SG_UF NOT IN (%s)",
      csv_reader(extracted[["votacao_secao"]]), cfg$cd_cargo, excl))
    DBI::dbExecute(con, sprintf(
      "CREATE VIEW det AS SELECT * FROM %s WHERE CD_CARGO = '%s' AND SG_UF NOT IN (%s)",
      csv_reader(extracted[["detalhe_votacao_secao"]]), cfg$cd_cargo, excl))

    DBI::dbExecute(con, sprintf(
      "CREATE TABLE valid_cand AS
         SELECT DISTINCT NR_TURNO::INTEGER AS turno, NR_CANDIDATO AS number
           FROM %s WHERE CD_CARGO = '%s' AND NM_TIPO_DESTINACAO_VOTOS = 'Válido'",
      csv_reader(extracted[["votacao_candidato_munzona"]]), cfg$cd_cargo))

    fin <- derive_finalists(con, cfg)
    a <- fin$number[fin$slot == "A"]; b <- fin$number[fin$slot == "B"]
    br <- cfg$votavel_branco; nu <- cfg$votavel_nulo

    DBI::dbExecute(con, sprintf("
      CREATE TABLE votes AS
      WITH v AS (
        SELECT vot.*, vc.number IS NOT NULL AS is_valid_cand
          FROM vot LEFT JOIN valid_cand vc ON vc.turno = vot.NR_TURNO::INTEGER AND vc.number = vot.NR_VOTAVEL
      )
      SELECT SG_UF AS uf, lpad(CD_MUNICIPIO, 5, '0') AS municipio_tse, lpad(NR_ZONA, 4, '0') AS zona,
             lpad(NR_SECAO, 4, '0') AS secao, NR_TURNO::INTEGER AS turno,
             sum(CASE WHEN NR_VOTAVEL = '%1$s' THEN QT_VOTOS::INTEGER ELSE 0 END)::INTEGER AS votes_a,
             sum(CASE WHEN NR_VOTAVEL = '%2$s' THEN QT_VOTOS::INTEGER ELSE 0 END)::INTEGER AS votes_b,
             sum(CASE WHEN NR_VOTAVEL NOT IN ('%1$s', '%2$s', '%3$s', '%4$s') AND is_valid_cand THEN QT_VOTOS::INTEGER ELSE 0 END)::INTEGER AS votes_other,
             sum(CASE WHEN NR_VOTAVEL NOT IN ('%1$s', '%2$s', '%3$s', '%4$s') AND NOT is_valid_cand THEN QT_VOTOS::INTEGER ELSE 0 END)::INTEGER AS votes_null_tech,
             sum(CASE WHEN NR_VOTAVEL = '%3$s' THEN QT_VOTOS::INTEGER ELSE 0 END)::INTEGER AS votes_blank_file,
             sum(CASE WHEN NR_VOTAVEL = '%4$s' THEN QT_VOTOS::INTEGER ELSE 0 END)::INTEGER AS votes_null_file,
             count(*)::INTEGER AS vote_rows
        FROM v GROUP BY ALL", a, b, br, nu))

    DBI::dbExecute(con, "
      CREATE TABLE detail AS
      SELECT SG_UF AS uf, lpad(CD_MUNICIPIO, 5, '0') AS municipio_tse, any_value(NM_MUNICIPIO) AS nm_municipio,
             lpad(NR_ZONA, 4, '0') AS zona, lpad(NR_SECAO, 4, '0') AS secao, NR_TURNO::INTEGER AS turno,
             any_value(QT_APTOS)::INTEGER AS aptos,
             any_value(QT_COMPARECIMENTO)::INTEGER AS comparecimento,
             any_value(QT_ABSTENCOES)::INTEGER AS abstencoes,
             any_value(QT_VOTOS_NOMINAIS)::INTEGER AS nominais,
             any_value(QT_VOTOS_BRANCOS)::INTEGER AS brancos,
             any_value(QT_VOTOS_NULOS)::INTEGER AS nulos,
             any_value(QT_VOTOS_LEGENDA)::INTEGER AS legenda,
             any_value(QT_VOTOS_ANULADOS_APU_SEP)::INTEGER AS anulados_sep,
             any_value(NR_LOCAL_VOTACAO) AS polling_place_id,
             any_value(NM_LOCAL_VOTACAO) AS polling_place_name,
             any_value(ST_SECAO_INSTALADA) = 'Sim' AS installed,
             any_value(ST_SECAO_ANULADA) = 'Sim' AS annulled,
             any_value(DS_ORIGEM_VOTO) AS vote_origin,
             count(*)::INTEGER AS detail_rows
        FROM det GROUP BY uf, municipio_tse, zona, secao, turno")

    DBI::dbExecute(con, sprintf("
      COPY (
        SELECT coalesce(d.uf, v.uf) AS uf, coalesce(d.municipio_tse, v.municipio_tse) AS municipio_tse,
               d.nm_municipio, coalesce(d.zona, v.zona) AS zona, coalesce(d.secao, v.secao) AS secao,
               coalesce(d.turno, v.turno) AS turno,
               d.aptos, d.comparecimento, d.abstencoes, d.nominais, d.brancos, d.nulos, d.legenda, d.anulados_sep,
               d.polling_place_id, d.polling_place_name, d.installed, d.annulled, d.vote_origin, d.detail_rows,
               coalesce(v.votes_a, 0)::INTEGER AS votes_a, coalesce(v.votes_b, 0)::INTEGER AS votes_b,
               coalesce(v.votes_other, 0)::INTEGER AS votes_other,
               coalesce(v.votes_null_tech, 0)::INTEGER AS votes_null_tech,
               coalesce(v.votes_blank_file, 0)::INTEGER AS votes_blank_file,
               coalesce(v.votes_null_file, 0)::INTEGER AS votes_null_file,
               coalesce(v.vote_rows, 0)::INTEGER AS vote_rows,
               d.uf IS NOT NULL AS in_detail_file, v.uf IS NOT NULL AS in_votes_file
          FROM detail d FULL OUTER JOIN votes v USING (uf, municipio_tse, zona, secao, turno)
         ORDER BY uf, municipio_tse, zona, secao, turno
      ) TO %s (FORMAT parquet, COMPRESSION zstd)", sql_quote_path(paths[["secao_turno"]])))

    DBI::dbExecute(con, sprintf("
      COPY (SELECT uf, municipio_tse, any_value(nm_municipio) AS name FROM detail GROUP BY ALL ORDER BY ALL)
      TO %s (FORMAT parquet)", sql_quote_path(paths[["municipios"]])))

    jsonlite::write_json(
      list(election_id = cfg$election_id, slot_rule = cfg$slot_rule, finalists = fin),
      paths[["finalistas"]], auto_unbox = TRUE, pretty = TRUE)
  })
  log_msg("silver gravada em ", out_dir)
  paths
}

read_finalists <- function(path) {
  x <- jsonlite::read_json(path, simplifyVector = TRUE)
  tibble::as_tibble(x$finalists)
}
