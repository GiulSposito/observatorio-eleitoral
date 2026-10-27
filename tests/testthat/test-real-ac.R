# Teste com dados reais do TSE (Acre). Pulado se a raiz de dados (CADERNO_DATA_DIR ou data/) não tiver
# os zips de 2026. Lê os CSV extraídos da raiz real e grava silver/gold num diretório temporário.

test_that("dados reais do AC passam em V1, V2 e V3 e têm unidades balanceadas", {
  real_root <- data_root()
  cfg <- read_election_config("2026-presidente")
  zips <- file.path(real_root, "bronze", cfg$election_id, vapply(cfg$fontes, function(s) basename(s$url), ""))
  skip_if_not(all(file.exists(zips)), "zips do TSE 2026 ausentes")
  ex_dir <- file.path(real_root, "bronze", cfg$election_id, "extracted")
  ex <- stats::setNames(vapply(seq_along(zips), function(i)
    zip_extract_member(zips[i], cfg$fontes[[i]]$membro, ex_dir), ""), names(cfg$fontes))
  with_temp_data_root({
    params <- read_method_params()
    sp <- build_silver(cfg, ex)
    build_gold_sections(cfg, sp, ex, params)
    build_gold_accounting(cfg, gold_paths(cfg), sp)
    fin <- read_finalists(sp[["finalistas"]])
    expect_equal(fin$number, c("13", "22"))
    sm <- read_parquet_df(gold_paths(cfg)[["secoes"]], where = "uf = 'AC'")
    expect_gt(nrow(sm), 1000)
    expect_true(all(sm$integrity_status == "passed"))
    expect_true(all(sm$comparison_status == "matched"))
    checks <- read_parquet_df(gold_paths(cfg)[["checks"]])
    ac_mun <- unique(sm$municipio_tse)
    expect_equal(length(ac_mun), 22L)
    ck <- checks[checks$municipio_tse %in% ac_mun, ]
    expect_true(all(ck$passed))
    u <- read_parquet_df(gold_paths(cfg)[["units"]], where = "uf = 'AC'")
    expect_true(all(u$o_A + u$o_B + u$o_O + u$o_I + u$o_X + u$o_N == u$d_A + u$d_B + u$d_I + u$d_X + u$d_S))
    expect_gt(nrow(u) / nrow(sm), 0.95)
  })
})
