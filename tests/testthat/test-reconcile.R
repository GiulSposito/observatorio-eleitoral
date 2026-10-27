sec_of <- function(sm, mun, secao) sm[sm$municipio_tse == mun & sm$secao == secao, ]

test_that("classes de população seguem tau = max(2, 1% de E1)", {
  expect_equal(population_tau(c(100, 200, 300, 1000)), c(2L, 2L, 3L, 10L))
  with_temp_data_root({
    r <- run_synthetic_gold()
    sm <- read_parquet_df(r$gold[["secoes"]])
    expect_equal(sec_of(sm, "01007", "0001")$population_status, "closed")
    expect_equal(sec_of(sm, "01007", "0002")$population_status, "net_change")
    s3 <- sec_of(sm, "01007", "0003")
    expect_equal(s3$population_status, "excluded_population")
    expect_equal(s3$exclusion_reason, "population_change_above_tau")
    expect_equal(s3$section_type, "unknown")
    expect_false(s3$in_transition_analysis)
  })
})

test_that("seções de trânsito e especiais saem da análise de transição pelo nome do local", {
  with_temp_data_root({
    r <- run_synthetic_gold()
    sm <- read_parquet_df(r$gold[["secoes"]])
    tr <- sec_of(sm, "30005", "0005"); sp <- sec_of(sm, "30005", "0006")
    expect_equal(tr$section_type, "transit"); expect_equal(tr$exclusion_reason, "transit_section")
    expect_equal(sp$section_type, "special"); expect_equal(sp$exclusion_reason, "special_section")
    expect_true(sec_of(sm, "30005", "0008")$in_transition_analysis)
  })
})

test_that("V1: comparecimento diferente da soma dos votos marca a seção e o município", {
  with_temp_data_root({
    r <- run_synthetic_gold()
    sm <- read_parquet_df(r$gold[["secoes"]])
    bad <- sec_of(sm, "30005", "0007")
    expect_equal(bad$integrity_status, "failed")
    expect_equal(bad$exclusion_reason, "integrity_failed")
    checks <- read_parquet_df(r$gold[["checks"]])
    ck <- checks[checks$municipio_tse == "30005" & checks$check_id == "integrity.turnout_equals_votes", ]
    expect_false(ck$passed); expect_equal(ck$count_failed, 1L)
    vs <- validation_status_from_checks(checks)
    expect_equal(vs$validation_status[vs$municipio_tse == "30005"], "partial")
    expect_equal(vs$validation_status[vs$municipio_tse == "01007"], "passed")
  })
})

test_that("V2: seção presente só num turno fica unmatched, sem deltas", {
  secs <- default_sections()
  only_t1 <- syn_section("MG", "20001", "BOM DESTINO", "101", "13", 150, 150, v1(50, 50, 10), v2(55, 55))
  with_temp_data_root({
    r <- run_synthetic_gold(c(secs, list(only_t1)), skip_votes = "20001 101 13 2")
    # o detalhe também precisa faltar no 2º turno: remove a linha e reconstrói
    det <- read.csv2(r$extracted[["detalhe_votacao_secao"]], fileEncoding = "latin1", colClasses = "character")
    det <- det[!(det$CD_MUNICIPIO == "20001" & det$NR_SECAO == "13" & det$NR_TURNO == "2"), ]
    write_tse_csv(det, r$extracted[["detalhe_votacao_secao"]])
    sp <- build_silver(r$cfg, r$extracted)
    build_gold_sections(r$cfg, sp, r$extracted, r$params)
    sm <- read_parquet_df(gold_paths(r$cfg)[["secoes"]])
    u <- sec_of(sm, "20001", "0013")
    expect_equal(u$comparison_status, "unmatched")
    expect_false(u$in_transition_analysis)
    expect_true(is.na(u$delta_a))
    checks <- read_parquet_df(gold_paths(r$cfg)[["checks"]])
    ck <- checks[checks$municipio_tse == "20001" & checks$check_id == "harmonization.pairing_one_to_one", ]
    expect_false(ck$passed)
  })
})

test_that("V3: divergência com o total oficial reprova o município", {
  bump <- function(cand) {
    k <- cand$CD_MUNICIPIO == "20001" & cand$NR_TURNO == "2" & cand$NR_CANDIDATO == "13"
    cand$QT_VOTOS_NOMINAIS[k] <- as.character(as.integer(cand$QT_VOTOS_NOMINAIS[k]) + 1L)
    cand
  }
  with_temp_data_root({
    r <- run_synthetic_gold(official_override = bump)
    checks <- read_parquet_df(r$gold[["checks"]])
    ck <- checks[checks$municipio_tse == "20001" & checks$check_id == "official_totals.candidates_round_2", ]
    expect_false(ck$passed)
    vs <- validation_status_from_checks(checks)
    expect_equal(vs$validation_status[vs$municipio_tse == "20001"], "failed")
    ok <- checks[checks$municipio_tse == "01007" & grepl("^official_totals", checks$check_id), ]
    expect_true(all(ok$passed))
  })
})

test_that("conta contábil fecha quando V1 passa; resíduo só aparece com falha dentro de um turno", {
  with_temp_data_root({
    r <- run_synthetic_gold()
    tot <- read_parquet_df(r$gold[["totais"]])
    resid <- (tot$a_2 - tot$a_1) + (tot$b_2 - tot$b_1) -
      (tot$other_1 + (tot$turnout_2 - tot$turnout_1) - (tot$invalid_2 - tot$invalid_1))
    names(resid) <- tot$municipio_tse
    expect_equal(unname(resid[c("01007", "20001")]), c(0, 0))
    # 30005 tem uma seção com comparecimento 1 acima da soma dos votos no 2º turno (falha de V1)
    expect_equal(unname(resid[["30005"]]), -1)
  })
})
