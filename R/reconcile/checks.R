# Verificações V1, V2 e V3, tipos de seção e classes de população (docs/05-metodo-analitico.md §2–3).
#
# Tudo em SQL (DuckDB) sobre a silver. Saídas na gold:
#   secoes_mart.parquet   uma linha por unidade, colunas de contract/marts.yml (secoes) + auxiliares
#   checks.parquet        verificações por município (família, id, passou, falhas, explicação)
#
# Tipos de seção (05 §3.1): os arquivos do TSE não marcam seções de trânsito nem especiais. O tipo é
# inferido pelo nome do local de votação (nos dois turnos):
#   transit  "TRÂNSITO"/"TRANSITO" ou "(VT)" no nome do local;
#   special  estabelecimentos prisionais e socioeducativos (penitenciária, presídio, CDP, cadeia, ...);
#   unknown  sem marcação no nome, mas com |D| > τ (padrão de seção de trânsito não declarada);
#   regular  o restante.

TRANSIT_RE <- "TR[AÂ]NSITO|\\(VT\\)"
SPECIAL_RE <- paste0(
  "PENITENCI|PRES[IÍ]DIO|PRISIONAL|\\bCDP\\b|DETEN[CÇ][AÃ]O|SOCIOEDUC|FUNDA[CÇ][AÃ]O CASA|",
  "\\bCADEIA\\b|INTERNA[CÇ][AÃ]O|\\bCASE\\b|RESSOCIALIZA|COMPLEXO PENAL|COLONIA PENAL|COLÔNIA PENAL"
)

# Constrói a tabela de seções (unidades) a partir da silver.
build_section_table <- function(con, silver_path, params) {
  p <- params$populacao
  DBI::dbExecute(con, sprintf("CREATE OR REPLACE VIEW st AS SELECT * FROM read_parquet(%s)",
                              sql_quote_path(silver_path)))
  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TABLE sec AS
    WITH r AS (
      SELECT *,
        installed AND NOT annulled AS usable,
        CASE WHEN installed THEN
          comparecimento = nominais + brancos + nulos + legenda + anulados_sep END AS v1_turnout,
        CASE WHEN installed THEN aptos = comparecimento + abstencoes END AS v1_eligible,
        CASE WHEN installed THEN
          least(aptos, comparecimento, abstencoes, nominais, brancos, nulos) >= 0 AND comparecimento <= aptos END AS v1_nonneg,
        CASE WHEN installed THEN
          in_detail_file AND in_votes_file
          AND votes_a + votes_b + votes_other + votes_null_tech = nominais
          AND votes_blank_file = brancos AND votes_null_file = nulos END AS v1_files,
        regexp_matches(upper(coalesce(polling_place_name, '')), '%s') AS kw_transit,
        regexp_matches(upper(coalesce(polling_place_name, '')), '%s') AS kw_special
      FROM st
    ),
    t1 AS (SELECT * FROM r WHERE turno = 1),
    t2 AS (SELECT * FROM r WHERE turno = 2)
    SELECT
      coalesce(t1.uf, t2.uf) AS uf,
      coalesce(t1.municipio_tse, t2.municipio_tse) AS municipio_tse,
      coalesce(t1.zona, t2.zona) AS zona,
      coalesce(t1.secao, t2.secao) AS secao,
      t1.uf IS NOT NULL AND t2.uf IS NOT NULL AS paired,
      coalesce(t1.polling_place_id, t2.polling_place_id) AS polling_place_id,
      coalesce(t1.polling_place_name, t2.polling_place_name) AS polling_place_name,
      CASE WHEN t1.uf IS NOT NULL AND t2.uf IS NOT NULL THEN t1.polling_place_id <> t2.polling_place_id END AS location_changed,
      coalesce(t1.usable, false) AND coalesce(t2.usable, false) AS installed,
      coalesce(t1.kw_transit, false) OR coalesce(t2.kw_transit, false) AS kw_transit,
      coalesce(t1.kw_special, false) OR coalesce(t2.kw_special, false) AS kw_special,
      coalesce(t1.kw_transit, false) <> coalesce(t2.kw_transit, false)
        OR coalesce(t1.kw_special, false) <> coalesce(t2.kw_special, false) AS type_changed,
      coalesce(t1.v1_turnout, true) AND coalesce(t2.v1_turnout, true) AS v1_turnout,
      coalesce(t1.v1_eligible, true) AND coalesce(t2.v1_eligible, true) AS v1_eligible,
      coalesce(t1.v1_nonneg, true) AND coalesce(t2.v1_nonneg, true) AS v1_nonneg,
      coalesce(t1.v1_files, true) AND coalesce(t2.v1_files, true) AS v1_files,
      t1.aptos AS eligible_t1, t2.aptos AS eligible_t2,
      t1.comparecimento AS turnout_t1, t2.comparecimento AS turnout_t2,
      t1.abstencoes AS abstention_t1, t2.abstencoes AS abstention_t2,
      t1.votes_a AS candidate_a_t1, t2.votes_a AS candidate_a_t2,
      t1.votes_b AS candidate_b_t1, t2.votes_b AS candidate_b_t2,
      t1.votes_other AS others_t1, t2.votes_other AS others_t2,
      t1.brancos AS blank_t1, t1.nulos + t1.votes_null_tech AS null_t1,
      t2.brancos AS blank_t2, t2.nulos + t2.votes_null_tech AS null_t2,
      t1.votes_null_tech AS null_tech_t1, t2.votes_null_tech AS null_tech_t2
    FROM t1 FULL OUTER JOIN t2 USING (uf, municipio_tse, zona, secao)
  ", TRANSIT_RE, SPECIAL_RE))

  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TABLE sec2 AS
    WITH s AS (
      SELECT *,
        v1_turnout AND v1_eligible AND v1_nonneg AND v1_files AS v1_ok,
        CASE WHEN paired AND installed THEN eligible_t2 - eligible_t1 END AS d,
        greatest(%d, floor(%f * eligible_t1))::INTEGER AS tau
      FROM sec
    ), c AS (
      SELECT *,
        CASE WHEN d IS NULL THEN NULL
             WHEN d = 0 THEN 'closed'
             WHEN abs(d) <= tau THEN 'net_change'
             ELSE 'excluded_population' END AS population_status,
        CASE WHEN kw_transit THEN 'transit'
             WHEN kw_special THEN 'special'
             WHEN d IS NOT NULL AND abs(d) > tau THEN 'unknown'
             ELSE 'regular' END AS section_type
      FROM s
    )
    SELECT *,
      CASE
        WHEN NOT installed THEN 'not_installed'
        WHEN NOT v1_ok THEN 'integrity_failed'
        WHEN NOT paired THEN 'unmatched'
        WHEN section_type = 'transit' THEN 'transit_section'
        WHEN section_type = 'special' THEN 'special_section'
        WHEN population_status = 'excluded_population' THEN 'population_change_above_tau'
        WHEN eligible_t1 > 0 AND turnout_t1 = 0 AND turnout_t2 = 0 THEN 'possible_aggregation'
        ELSE NULL END AS exclusion_reason
    FROM c
  ", as.integer(p$tau_minimo_eleitores), as.numeric(p$tau_fracao)))
  invisible(TRUE)
}

# Colunas do mart `secoes` (contract/marts.yml), mais auxiliares usados nas etapas seguintes.
section_mart_sql <- function(election_id) {
  sprintf("
    SELECT
      '%s' AS election_id, uf, municipio_tse, zona, secao,
      municipio_tse || '-' || zona || '-' || secao AS comparison_unit_id,
      'section' AS unit_type,
      CASE WHEN paired THEN 'matched' ELSE 'unmatched' END AS comparison_status,
      section_type, polling_place_id, polling_place_name, location_changed,
      CASE WHEN NOT installed OR v1_ok THEN 'passed' ELSE 'failed' END AS integrity_status,
      installed,
      CASE WHEN installed THEN eligible_t1 END::INTEGER AS eligible_t1,
      CASE WHEN installed THEN eligible_t2 END::INTEGER AS eligible_t2,
      CASE WHEN installed THEN turnout_t1 END::INTEGER AS turnout_t1,
      CASE WHEN installed THEN turnout_t2 END::INTEGER AS turnout_t2,
      CASE WHEN installed THEN abstention_t1 END::INTEGER AS abstention_t1,
      CASE WHEN installed THEN abstention_t2 END::INTEGER AS abstention_t2,
      CASE WHEN installed THEN candidate_a_t1 END::INTEGER AS candidate_a_t1,
      CASE WHEN installed THEN candidate_a_t2 END::INTEGER AS candidate_a_t2,
      CASE WHEN installed THEN candidate_b_t1 END::INTEGER AS candidate_b_t1,
      CASE WHEN installed THEN candidate_b_t2 END::INTEGER AS candidate_b_t2,
      CASE WHEN installed THEN others_t1 END::INTEGER AS others_t1,
      CASE WHEN installed THEN blank_t1 END::INTEGER AS blank_t1,
      CASE WHEN installed THEN null_t1 END::INTEGER AS null_t1,
      CASE WHEN installed THEN blank_t2 END::INTEGER AS blank_t2,
      CASE WHEN installed THEN null_t2 END::INTEGER AS null_t2,
      CASE WHEN installed THEN blank_t1 + null_t1 END::INTEGER AS invalid_t1,
      CASE WHEN installed THEN blank_t2 + null_t2 END::INTEGER AS invalid_t2,
      CASE WHEN installed AND paired THEN turnout_t2 - turnout_t1 END::INTEGER AS delta_turnout,
      CASE WHEN installed AND paired THEN candidate_a_t2 - candidate_a_t1 END::INTEGER AS delta_a,
      CASE WHEN installed AND paired THEN candidate_b_t2 - candidate_b_t1 END::INTEGER AS delta_b,
      CASE WHEN installed AND paired THEN (blank_t2 + null_t2) - (blank_t1 + null_t1) END::INTEGER AS delta_invalid,
      d::INTEGER AS eligible_net_change,
      population_status,
      exclusion_reason IS NULL AS in_transition_analysis,
      exclusion_reason,
      -- auxiliares (não publicados)
      tau::INTEGER AS tau, type_changed, null_tech_t1, null_tech_t2,
      v1_turnout, v1_eligible, v1_nonneg, v1_files
    FROM sec2", election_id)
}

# V3: confronto com os totais oficiais por município (votação por candidato e detalhe por município/zona).
official_totals_checks <- function(con, cfg, extracted, finalists) {
  a <- finalists$number[finalists$slot == "A"]; b <- finalists$number[finalists$slot == "B"]
  excl <- paste0("'", cfg$excluir_ufs, "'", collapse = ", ")
  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TABLE off_cand AS
    SELECT lpad(CD_MUNICIPIO, 5, '0') AS municipio_tse, NR_TURNO::INTEGER AS turno,
           sum(CASE WHEN NR_CANDIDATO = '%s' THEN QT_VOTOS_NOMINAIS::BIGINT ELSE 0 END) AS a,
           sum(CASE WHEN NR_CANDIDATO = '%s' THEN QT_VOTOS_NOMINAIS::BIGINT ELSE 0 END) AS b,
           sum(CASE WHEN NR_CANDIDATO NOT IN ('%s', '%s') AND NM_TIPO_DESTINACAO_VOTOS = 'Válido'
                    THEN QT_VOTOS_NOMINAIS::BIGINT ELSE 0 END) AS other
      FROM %s WHERE CD_CARGO = '%s' AND SG_UF NOT IN (%s) GROUP BY ALL",
    a, b, a, b, csv_reader(extracted[["votacao_candidato_munzona"]]), cfg$cd_cargo, excl))
  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TABLE off_det AS
    SELECT lpad(CD_MUNICIPIO, 5, '0') AS municipio_tse, NR_TURNO::INTEGER AS turno,
           sum(QT_APTOS::BIGINT) AS aptos, sum(QT_COMPARECIMENTO::BIGINT) AS comparecimento,
           sum(QT_VOTOS_BRANCOS::BIGINT) AS brancos, sum(QT_TOTAL_VOTOS_NULOS::BIGINT) AS nulos
      FROM %s WHERE CD_CARGO = '%s' AND SG_UF NOT IN (%s) GROUP BY ALL",
    csv_reader(extracted[["detalhe_votacao_munzona"]]), cfg$cd_cargo, excl))

  DBI::dbExecute(con, "
    CREATE OR REPLACE TABLE sec_tot AS
    SELECT municipio_tse, t.turno,
           sum(CASE WHEN t.turno = 1 THEN candidate_a_t1 ELSE candidate_a_t2 END) AS a,
           sum(CASE WHEN t.turno = 1 THEN candidate_b_t1 ELSE candidate_b_t2 END) AS b,
           sum(CASE WHEN t.turno = 1 THEN others_t1 ELSE others_t2 END) AS other,
           sum(CASE WHEN t.turno = 1 THEN eligible_t1 ELSE eligible_t2 END) AS aptos,
           sum(CASE WHEN t.turno = 1 THEN turnout_t1 ELSE turnout_t2 END) AS comparecimento,
           sum(CASE WHEN t.turno = 1 THEN blank_t1 ELSE blank_t2 END) AS brancos,
           sum(CASE WHEN t.turno = 1 THEN null_t1 ELSE null_t2 END) AS nulos
      FROM sec2, (VALUES (1), (2)) t(turno)
     WHERE installed
     GROUP BY ALL")

  rounds_with_detail <- DBI::dbGetQuery(con, "SELECT DISTINCT turno FROM off_det ORDER BY 1")$turno

  cand <- DBI::dbGetQuery(con, "
    SELECT s.municipio_tse, s.turno,
           (coalesce(s.a, 0) <> coalesce(o.a, -1))::INT + (coalesce(s.b, 0) <> coalesce(o.b, -1))::INT +
           (coalesce(s.other, 0) <> coalesce(o.other, -1))::INT AS n_diff
      FROM sec_tot s LEFT JOIN off_cand o USING (municipio_tse, turno)")
  cand$check_id <- paste0("official_totals.candidates_round_", cand$turno)

  det <- DBI::dbGetQuery(con, "
    SELECT s.municipio_tse, s.turno,
           (coalesce(s.aptos, 0) <> coalesce(o.aptos, -1))::INT + (coalesce(s.comparecimento, 0) <> coalesce(o.comparecimento, -1))::INT +
           (coalesce(s.brancos, 0) <> coalesce(o.brancos, -1))::INT + (coalesce(s.nulos, 0) <> coalesce(o.nulos, -1))::INT AS n_diff
      FROM sec_tot s LEFT JOIN off_det o USING (municipio_tse, turno)")
  det <- det[det$turno %in% rounds_with_detail, , drop = FALSE]
  det$check_id <- paste0("official_totals.turnout_round_", det$turno)

  out <- dplyr::bind_rows(cand, det)
  tibble::tibble(
    municipio_tse = out$municipio_tse,
    check_id = out$check_id,
    family = "official_totals",
    passed = out$n_diff == 0,
    scope = "municipality",
    count_failed = as.integer(out$n_diff),
    explanation_code = NA_character_
  )
}

# Verificações V1 e V2 agregadas por município.
section_checks <- function(con) {
  df <- DBI::dbGetQuery(con, "
    SELECT municipio_tse,
      count(*) FILTER (WHERE installed AND NOT v1_turnout) AS f_turnout,
      count(*) FILTER (WHERE installed AND NOT v1_eligible) AS f_eligible,
      count(*) FILTER (WHERE installed AND NOT v1_nonneg) AS f_nonneg,
      count(*) FILTER (WHERE installed AND NOT v1_files) AS f_files,
      count(*) FILTER (WHERE NOT paired) AS f_pairing,
      count(*) FILTER (WHERE type_changed) AS f_type
    FROM sec2 GROUP BY 1")
  spec <- tibble::tribble(
    ~col,         ~check_id,                                             ~family,          ~scope,
    "f_turnout",  "integrity.turnout_equals_votes",                      "integrity",      "sections",
    "f_eligible", "integrity.eligible_equals_turnout_plus_abstention",   "integrity",      "sections",
    "f_nonneg",   "integrity.non_negative_counts",                       "integrity",      "sections",
    "f_files",    "integrity.section_files_agree",                       "integrity",      "sections",
    "f_pairing",  "harmonization.pairing_one_to_one",                    "harmonization",  "units",
    "f_type",     "harmonization.section_type_stable",                   "harmonization",  "units"
  )
  dplyr::bind_rows(lapply(seq_len(nrow(spec)), function(i) {
    n <- as.integer(df[[spec$col[i]]])
    tibble::tibble(municipio_tse = df$municipio_tse, check_id = spec$check_id[i], family = spec$family[i],
                   passed = n == 0L, scope = spec$scope[i], count_failed = n, explanation_code = NA_character_)
  }))
}

# validation_status por município (03 §2).
validation_status_from_checks <- function(checks) {
  checks |>
    dplyr::group_by(municipio_tse) |>
    dplyr::summarise(
      validation_status = dplyr::case_when(
        any(family == "official_totals" & !passed & is.na(explanation_code)) ~ "failed",
        any(family == "integrity" & !passed) ~ "partial",
        any(family == "official_totals" & !passed & !is.na(explanation_code)) ~ "partial",
        TRUE ~ "passed"
      ),
      .groups = "drop"
    )
}

# Gold: seções classificadas + verificações. Devolve os caminhos gravados.
build_gold_sections <- function(cfg, silver_paths, extracted, params) {
  out_dir <- layer_dir("gold", cfg$election_id)
  paths <- c(secoes = file.path(out_dir, "secoes_mart.parquet"),
             checks = file.path(out_dir, "checks.parquet"))
  fin <- read_finalists(silver_paths[["finalistas"]])
  with_db(function(con) {
    build_section_table(con, silver_paths[["secao_turno"]], params)
    DBI::dbExecute(con, sprintf("COPY (%s ORDER BY uf, municipio_tse, zona, secao) TO %s (FORMAT parquet, COMPRESSION zstd)",
                                section_mart_sql(cfg$election_id), sql_quote_path(paths[["secoes"]])))
    checks <- dplyr::bind_rows(section_checks(con), official_totals_checks(con, cfg, extracted, fin)) |>
      dplyr::arrange(municipio_tse, check_id)
    duckdb::duckdb_register(con, "checks_df", checks)
    DBI::dbExecute(con, sprintf("COPY (SELECT * FROM checks_df) TO %s (FORMAT parquet)", sql_quote_path(paths[["checks"]])))
  })
  log_msg("gold (seções e verificações) gravada em ", out_dir)
  paths
}
