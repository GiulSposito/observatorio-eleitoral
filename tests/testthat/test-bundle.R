fake_sources <- function() {
  tibble::tibble(provider = "TSE", dataset = "Votação por seção eleitoral 2026 (sintético)",
                 file = "votacao_secao.csv", source_url = "https://cdn.tse.jus.br/estatistica/sead/odsele/votacao_secao/x.zip",
                 collected_at = "2026-10-27T12:00:00Z", source_sha256 = strrep("a", 64), bytes = 123)
}

build_synthetic_release <- function(r) {
  assumptions <- read_assumptions()
  calibration <- calibrate_method(r$gold[["units"]], r$params, "teste")
  validation <- validation_status_from_checks(read_parquet_df(r$gold[["checks"]]))
  ufs <- sort(unique(read_parquet_df(r$gold[["totais"]])$uf))
  eco <- unlist(lapply(ufs, run_ecological_uf, units_path = r$gold[["units"]], totals_path = r$gold[["totais"]],
                       validation = validation, calibration = calibration, assumptions = assumptions, cfg = r$cfg))
  out_root <- file.path(data_root(), "publicado")
  web_dir <- file.path(data_root(), "web_data")
  res <- build_web_bundle(r$cfg, r$gold, eco, calibration, fake_sources(), r$silver, assumptions,
                          out_root = out_root, web_dir = web_dir, generated_at = "2026-10-27T18:00:00Z")
  c(res, list(out_root = out_root, web_dir = web_dir))
}

test_that("build_web_bundle gera release válida, promove latest.json e copia para web/data", {
  skip_if_not(exists("ec_bounds", mode = "function"))
  with_temp_data_root({
    r <- run_synthetic_gold()
    res <- build_synthetic_release(r)
    expect_equal(res$release_id, "2026-presidente-20261027T180000Z")
    expect_true(file.exists(file.path(res$out_root, "latest.json")))
    expect_true(validate_web_bundle(res$out_root))
    expect_true(validate_web_bundle(res$web_dir))
    cat <- jsonlite::read_json(file.path(res$release_dir, "catalogo.json"))
    expect_equal(length(cat$municipalities), 3L)
    expect_equal(vapply(cat$election$finalists, `[[`, "", "number"), c("13", "22"))
    pub <- setNames(vapply(cat$municipalities, `[[`, "", "publication_status"),
                    vapply(cat$municipalities, `[[`, "", "municipio_tse"))
    expect_equal(pub[["30005"]], "partial")
    expect_equal(pub[["01007"]], "ready")
    res_go <- jsonlite::read_json(file.path(res$release_dir, "2026-presidente/municipios/GO/01007/resumo.json"))
    expect_equal(res_go$accounting$identity_residual, 0L)
    expect_equal(res_go$location$display_name, "Bom Destino")
    expect_false(dir.exists(file.path(res$out_root, "releases", paste0(res$release_id, ".staging"))))
  })
})

test_that("validador rejeita asset adulterado", {
  skip_if_not(exists("ec_bounds", mode = "function"))
  with_temp_data_root({
    r <- run_synthetic_gold()
    res <- build_synthetic_release(r)
    f <- file.path(res$release_dir, "2026-presidente/municipios/GO/01007/resumo.json")
    txt <- readLines(f, warn = FALSE)
    writeLines(sub("\"status\":\"ready\"", "\"status\":\"ready\" ", txt), f)
    expect_error(validate_web_bundle(res$out_root), "bytes divergentes|sha256 divergente")
  })
})

test_that("o bundle sintético DEMO das fixtures passa no contrato e é recusado como produção", {
  root <- file.path(getOption("caderno.repo_root"), "tests", "fixtures", "bundle")
  skip_if_not(file.exists(file.path(root, "latest.json")))
  expect_true(validate_web_bundle(root, allow_demo = TRUE))
  expect_error(validate_web_bundle(root, allow_demo = FALSE), "demonstração")
})

test_that("write_mart aplica tipos e ordenação do contrato", {
  with_temp_data_root({
    df <- tibble::tibble(
      election_id = "2026-presidente", uf = "GO", municipio_tse = c("00002", "00001"), scenario_id = "base",
      assumption_id = "pop-liquida-minima", status = "feasible", units_used = c(3, 4), units_infeasible = 0)
    path <- file.path(data_root(), "c.parquet")
    with_db(function(con) write_mart_df(con, "cenarios", df, path))
    out <- read_parquet_df(path)
    expect_equal(out$municipio_tse, c("00001", "00002"))
    expect_type(out$units_used, "integer")
  })
})
