# Gold: totais municipais (observado), conta contábil (só exibição) e unidades para o método.
#
# Os totais somam todas as seções instaladas do município (03 §7). A conta
# ΔA + ΔB = O₁ + ΔC − ΔI é aritmética dentro de cada turno (05 §2): é publicada para explicar os
# totais e nunca usada como verificação entre turnos.

build_municipal_totals <- function(con, secoes_path, municipios_path) {
  DBI::dbExecute(con, sprintf("CREATE OR REPLACE VIEW sm AS SELECT * FROM read_parquet(%s)", sql_quote_path(secoes_path)))
  DBI::dbExecute(con, sprintf("CREATE OR REPLACE VIEW mu AS SELECT * FROM read_parquet(%s)", sql_quote_path(municipios_path)))
  DBI::dbGetQuery(con, "
    WITH t AS (
      SELECT uf, municipio_tse,
        count(*)::INTEGER AS sections_total,
        count(*) FILTER (WHERE installed)::INTEGER AS sections_installed,
        count(*) FILTER (WHERE comparison_status = 'matched')::INTEGER AS units_paired,
        count(*) FILTER (WHERE in_transition_analysis)::INTEGER AS units_in_transition_analysis,
        sum(eligible_t1)::BIGINT AS eligible_1, sum(eligible_t2)::BIGINT AS eligible_2,
        sum(turnout_t1)::BIGINT AS turnout_1, sum(turnout_t2)::BIGINT AS turnout_2,
        sum(abstention_t1)::BIGINT AS abstention_1, sum(abstention_t2)::BIGINT AS abstention_2,
        sum(candidate_a_t1)::BIGINT AS a_1, sum(candidate_a_t2)::BIGINT AS a_2,
        sum(candidate_b_t1)::BIGINT AS b_1, sum(candidate_b_t2)::BIGINT AS b_2,
        sum(others_t1)::BIGINT AS other_1,
        sum(blank_t1)::BIGINT AS blank_1, sum(blank_t2)::BIGINT AS blank_2,
        sum(null_t1)::BIGINT AS null_1, sum(null_t2)::BIGINT AS null_2,
        sum(invalid_t1)::BIGINT AS invalid_1, sum(invalid_t2)::BIGINT AS invalid_2,
        sum(eligible_t1) FILTER (WHERE in_transition_analysis)::BIGINT AS eligible_1_used,
        count(*) FILTER (WHERE population_status = 'closed')::INTEGER AS pop_closed,
        count(*) FILTER (WHERE population_status = 'net_change')::INTEGER AS pop_net_change,
        count(*) FILTER (WHERE population_status = 'excluded_population')::INTEGER AS pop_excluded,
        count(*) FILTER (WHERE exclusion_reason = 'not_installed')::INTEGER AS ex_not_installed,
        count(*) FILTER (WHERE exclusion_reason = 'integrity_failed')::INTEGER AS ex_integrity_failed,
        count(*) FILTER (WHERE exclusion_reason = 'unmatched')::INTEGER AS ex_unmatched,
        count(*) FILTER (WHERE exclusion_reason = 'transit_section')::INTEGER AS ex_transit_section,
        count(*) FILTER (WHERE exclusion_reason = 'special_section')::INTEGER AS ex_special_section,
        count(*) FILTER (WHERE exclusion_reason = 'population_change_above_tau')::INTEGER AS ex_population_change_above_tau,
        count(*) FILTER (WHERE exclusion_reason = 'possible_aggregation')::INTEGER AS ex_possible_aggregation
      FROM sm GROUP BY uf, municipio_tse
    )
    SELECT t.*, mu.name,
      a_1 + b_1 + other_1 AS valid_1, a_2 + b_2 AS valid_2,
      CASE WHEN eligible_1 > 0 THEN eligible_1_used::DOUBLE / eligible_1 END AS eligible_share_used
    FROM t LEFT JOIN mu USING (uf, municipio_tse)
    ORDER BY uf, municipio_tse")
}

# Unidades (R/README.md, "Interface entre dados e método").
build_units_sql <- function(secoes_path) {
  sprintf("
    SELECT election_id, uf, municipio_tse, comparison_unit_id, population_status,
      candidate_a_t1 AS o_A, candidate_b_t1 AS o_B, others_t1 AS o_O, invalid_t1 AS o_I, abstention_t1 AS o_X,
      greatest(eligible_net_change, 0)::INTEGER AS o_N,
      candidate_a_t2 AS d_A, candidate_b_t2 AS d_B, invalid_t2 AS d_I, abstention_t2 AS d_X,
      greatest(-eligible_net_change, 0)::INTEGER AS d_S,
      eligible_t1, eligible_t2
    FROM read_parquet(%s)
    WHERE in_transition_analysis
    ORDER BY uf, municipio_tse, comparison_unit_id", sql_quote_path(secoes_path))
}

assert_units_balance <- function(units) {
  o <- units$o_A + units$o_B + units$o_O + units$o_I + units$o_X + units$o_N
  d <- units$d_A + units$d_B + units$d_I + units$d_X + units$d_S
  bad <- which(o != d | is.na(o) | is.na(d))
  if (length(bad)) stop("unidades sem balanço origem = destino: ", length(bad), " linhas (ex.: ",
                        units$comparison_unit_id[bad[1]], ")", call. = FALSE)
  invisible(units)
}

build_gold_accounting <- function(cfg, gold_sections, silver_paths) {
  out_dir <- layer_dir("gold", cfg$election_id)
  paths <- c(totais = file.path(out_dir, "municipal_totals.parquet"),
             units = file.path(out_dir, "units.parquet"))
  with_db(function(con) {
    tot <- build_municipal_totals(con, gold_sections[["secoes"]], silver_paths[["municipios"]])
    duckdb::duckdb_register(con, "tot_df", tot)
    DBI::dbExecute(con, sprintf("COPY (SELECT * FROM tot_df) TO %s (FORMAT parquet)", sql_quote_path(paths[["totais"]])))
    units <- tibble::as_tibble(DBI::dbGetQuery(con, build_units_sql(gold_sections[["secoes"]])))
    assert_units_balance(units)
    others_t2 <- DBI::dbGetQuery(con, sprintf(
      "SELECT count(*) AS n FROM read_parquet(%s) WHERE in_transition_analysis AND candidate_a_t2 + candidate_b_t2 + invalid_t2 <> turnout_t2",
      sql_quote_path(gold_sections[["secoes"]])))$n
    if (others_t2 > 0) stop("2º turno com votos fora de A, B e I em ", others_t2, " unidades", call. = FALSE)
    DBI::dbExecute(con, sprintf("COPY (%s) TO %s (FORMAT parquet, COMPRESSION zstd)",
                                build_units_sql(gold_sections[["secoes"]]), sql_quote_path(paths[["units"]])))
  })
  log_msg("gold (totais e unidades) gravada em ", out_dir)
  paths
}
