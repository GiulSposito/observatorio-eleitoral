# Orquestra as funções de R/ecological/ (ec_bounds, ec_estimate, ec_calibrate; R/README.md) sobre as
# unidades da gold, por UF. A camada de dados só chama a interface; o método é do módulo ecológico.

ensure_ecological <- function() {
  have <- all(vapply(c("ec_bounds", "ec_estimate", "ec_calibrate"), exists, logical(1), mode = "function"))
  if (have) return(invisible("module"))
  if (identical(Sys.getenv("CADERNO_ECOLOGICAL_STUB"), "1")) {
    source(file.path(repo_root(), "tests", "testthat", "helper-ecological-stub.R"), local = globalenv())
    log_msg("AVISO: usando o stub ecológico (CADERNO_ECOLOGICAL_STUB=1); release não publicável")
    return(invisible("stub"))
  }
  stop("funções ec_bounds/ec_estimate/ec_calibrate ausentes (R/ecological/). ",
       "Para rodar só a parte observada, defina CADERNO_ECOLOGICAL_STUB=1.", call. = FALSE)
}

ecological_mode <- function() {
  if (identical(Sys.getenv("CADERNO_ECOLOGICAL_STUB"), "1") &&
      !file.exists(file.path(repo_root(), "R", "ecological"))) "stub" else "module"
}

# Namespace das seeds: estável entre releases do mesmo método (ver relatório: proposta de ajuste ao
# R/README.md, que fala em release_id).
seed_namespace <- function(cfg, params) paste(cfg$election_id, params$method_version, sep = "|")

calibrate_method <- function(units_path, params, namespace) {
  ensure_ecological()
  units <- read_parquet_df(units_path)
  res <- ec_calibrate(units, params, seed_for(namespace, "BR", "calibration"))
  calibrated <- params
  if (length(res$thresholds)) {
    for (k in names(res$thresholds)) calibrated$estimacao[[k]] <- res$thresholds[[k]]
  }
  list(result = res, params = calibrated)
}

unit_cols <- c("comparison_unit_id", "population_status",
               "o_A", "o_B", "o_O", "o_I", "o_X", "o_N", "d_A", "d_B", "d_I", "d_X", "d_S")

run_ecological_uf <- function(uf, units_path, totals_path, validation, calibration, assumptions, cfg) {
  ensure_ecological()
  params <- calibration$params
  namespace <- seed_namespace(cfg, params)
  method_version <- params$method_version
  units <- read_parquet_df(units_path, where = sprintf("uf = '%s'", uf))
  totals <- read_parquet_df(totals_path, where = sprintf("uf = '%s'", uf))
  scenarios <- assumptions$scenarios

  run_mun <- function(i) {
    lim <- list(); cen <- list(); flo <- NULL
    mun <- totals$municipio_tse[i]
    share <- totals$eligible_share_used[i]
    u <- units[units$municipio_tse == mun, c("election_id", "uf", "municipio_tse", unit_cols), drop = FALSE]

    for (sc in scenarios) {
      b <- ec_bounds(u, scenario = sc$id, assumptions = assumptions)
      b <- tibble::as_tibble(b)
      b$election_id <- cfg$election_id; b$uf <- uf; b$municipio_tse <- mun
      b$scenario_id <- sc$id; b$assumption_id <- sc$assumption_id
      b$eligible_share_used <- share; b$method_version <- method_version
      lim[[length(lim) + 1L]] <- b
      cen[[length(cen) + 1L]] <- tibble::tibble(
        election_id = cfg$election_id, uf = uf, municipio_tse = mun, scenario_id = sc$id,
        assumption_id = sc$assumption_id,
        status = if (all(b$status == "feasible")) "feasible" else if (any(b$status == "infeasible")) "infeasible" else "insufficient_data",
        units_used = as.integer(max(b$units_used)), units_infeasible = as.integer(max(b$units_infeasible)))
    }

    vstat <- validation$validation_status[validation$municipio_tse == mun]
    if (identical(vstat, "failed")) {
      est <- list(flows = NULL, status = "unavailable",
                  model = list(status = "unavailable",
                               reason_unavailable = "Os totais do município divergem dos totais oficiais sem explicação registrada.",
                               methods = list(), predictive_check = NULL, identified_change_share = NULL,
                               n_units_used = nrow(u), calibration_id = calibration$result$calibration_id))
    } else {
      est <- tryCatch(
        ec_estimate(u, params, seed_for(namespace, mun, "dm-homog"), context = list(eligible_share_used = share)),
        error = function(e) list(flows = NULL, status = "failed",
                                 model = list(status = "failed", reason_unavailable = conditionMessage(e),
                                              methods = list(), predictive_check = NULL,
                                              identified_change_share = NULL, n_units_used = nrow(u),
                                              calibration_id = calibration$result$calibration_id)))
    }
    est$model$status <- est$status
    if (est$status %in% c("ready", "partial") && !is.null(est$flows) && nrow(est$flows) > 0L) {
      flo <- tibble::as_tibble(est$flows)
      flo$election_id <- cfg$election_id; flo$uf <- uf; flo$municipio_tse <- mun
    }
    list(lim = dplyr::bind_rows(lim), cen = dplyr::bind_rows(cen), flo = flo, model = est$model)
  }
  # Municípios maiores primeiro, para equilibrar os processos; o resultado volta à ordem original.
  n_units <- vapply(totals$municipio_tse, function(m) sum(units$municipio_tse == m), integer(1))
  idx <- order(-n_units)
  res <- ec_parallel_map(idx, run_mun, calibration$params$execucao$workers %||% 1L)[order(idx)]
  lim <- lapply(res, `[[`, "lim"); cen <- lapply(res, `[[`, "cen"); flo <- lapply(res, `[[`, "flo")
  models <- stats::setNames(lapply(res, `[[`, "model"), totals$municipio_tse)

  out_dir <- layer_dir("gold", cfg$election_id, "eco", paste0("uf=", uf))
  paths <- c(limites = file.path(out_dir, "limites.parquet"),
             cenarios = file.path(out_dir, "cenarios.parquet"),
             fluxos = file.path(out_dir, "fluxos.parquet"),
             models = file.path(out_dir, "models.json"))
  write_df_parquet(dplyr::bind_rows(lim), paths[["limites"]])
  write_df_parquet(dplyr::bind_rows(cen), paths[["cenarios"]])
  fl <- dplyr::bind_rows(flo)
  if (nrow(fl) > 0L) write_df_parquet(fl, paths[["fluxos"]]) else unlink(paths[["fluxos"]])
  jsonlite::write_json(models, paths[["models"]], auto_unbox = TRUE, null = "null", na = "null", digits = NA)
  paths[file.exists(paths)]
}

write_df_parquet <- function(df, path) {
  with_db(function(con) {
    duckdb::duckdb_register(con, "df_out", df)
    DBI::dbExecute(con, sprintf("COPY (SELECT * FROM df_out) TO %s (FORMAT parquet, COMPRESSION zstd)", sql_quote_path(path)))
  })
  path
}
