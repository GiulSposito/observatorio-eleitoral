# Benchmark do método (subagente B). Uso, a partir da raiz:
#   CADERNO_DATA_DIR=<raiz de dados> Rscript tests/benchmark/benchmark.R <etapa> [args]
# Etapas:
#   bounds            tempo nacional de ec_bounds (base e sem-troca-finalistas) e do LP por unidade
#   md <n_por_estrato> [burnin thin amostras lambda1 lambda2]
#                     md-bayes (eiPack) numa amostra estratificada por porte: convergência e tempo
#   pilot <municipio> custo previsto do md-bayes e tempo de lphom/validação cruzada num município
#   ecolrxc <municipio> tempo do ecolRxC
#   calib <n_por_estrato>  calibração reduzida
#   dm <municipio> [iteracoes]  experimento do motor alternativo (tests/benchmark/experimento_dm.R)
# Resultados em tests/benchmark/results/.

suppressPackageStartupMessages({
  library(DBI)
  library(dplyr)
})
for (f in sort(list.files("R", pattern = "[.]R$", recursive = TRUE, full.names = TRUE))) source(f, local = globalenv())

args <- commandArgs(trailingOnly = TRUE)
stage <- args[[1]]
data_dir <- Sys.getenv("CADERNO_DATA_DIR", "data")
units_path <- file.path(data_dir, "gold", "2026-presidente", "units.parquet")
out_dir <- "tests/benchmark/results"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
params <- yaml::read_yaml("config/metodo.yml")
assumptions <- yaml::read_yaml("config/assumptions.yml")

read_units <- function(where = NULL) {
  con <- dbConnect(duckdb::duckdb())
  on.exit(dbDisconnect(con, shutdown = TRUE))
  q <- sprintf("SELECT * FROM read_parquet('%s')%s", units_path, if (is.null(where)) "" else paste(" WHERE", where))
  tibble::as_tibble(dbGetQuery(con, q))
}

append_csv <- function(df, name) {
  path <- file.path(out_dir, name)
  utils::write.table(df, path, sep = ",", row.names = FALSE, col.names = !file.exists(path), append = file.exists(path))
}

stratified_sample <- function(units, per_stratum, seed, breaks = c(15, 30, 60, 150, 500, 2000, 1e6)) {
  n <- units |> count(municipio_tse, uf, name = "n")
  n$stratum <- as.character(cut(n$n, breaks = breaks, right = FALSE, dig.lab = 7))
  n <- n[!is.na(n$stratum), ]
  set.seed(seed)
  n |> group_by(stratum) |> slice_sample(n = per_stratum) |> ungroup() |> arrange(n)
}

if (stage == "bounds") {
  u <- read_units()
  by_mun <- split(u, u$municipio_tse)
  t_base <- system.time(invisible(lapply(by_mun, ec_bounds, scenario = "base")))[["elapsed"]]
  t_sc <- system.time(invisible(lapply(by_mun, ec_bounds, scenario = "sem-troca-finalistas", assumptions = assumptions)))[["elapsed"]]
  sc <- lapply(by_mun, ec_bounds, scenario = "sem-troca-finalistas", assumptions = assumptions)
  infeasible <- sum(vapply(sc, function(b) any(b$status == "infeasible"), logical(1)))
  units_inf <- sum(vapply(sc, function(b) max(b$units_infeasible), numeric(1)))
  # LP por unidade (lpSolve, 60 LPs por unidade) numa amostra, para comparar
  set.seed(1)
  smp <- u[sample.int(nrow(u), 200), ]
  m <- ec_margins(smp)
  cons <- list(list(origin = "A", destination = "B", value = 0), list(origin = "B", destination = "A", value = 0),
               list(origin = "N", destination = "S", value = 0))
  t_lp <- system.time(for (k in seq_len(nrow(smp))) ec_bounds_lp_unit(m$O[k, ], m$D[k, ], cons))[["elapsed"]]
  res <- tibble::tibble(units = nrow(u), municipios = length(by_mun), t_base_s = t_base, t_scenario_gale_s = t_sc,
                        municipios_infeasible = infeasible, units_infeasible = units_inf,
                        t_lp_per_unit_s = t_lp / nrow(smp), t_lp_national_est_s = t_lp / nrow(smp) * nrow(u))
  print(res)
  append_csv(res, "bounds.csv")
}

if (stage == "md") {
  per <- as.integer(args[[2]])
  if (length(args) >= 7) {
    params$execucao$eipack$burnin <- as.integer(args[[3]])
    params$execucao$eipack$thin <- as.integer(args[[4]])
    params$execucao$eipack$amostras <- as.integer(args[[5]])
    params$execucao$eipack$lambda1 <- as.numeric(args[[6]])
    params$execucao$eipack$lambda2 <- as.numeric(args[[7]])
  }
  label <- paste(params$execucao$eipack[c("burnin", "thin", "amostras", "lambda1", "lambda2")], collapse = "/")
  max_units <- if (length(args) >= 8) as.integer(args[[8]]) else 1999L
  u <- read_units()
  smp <- stratified_sample(u, per, seed = 20261027)
  smp <- smp[smp$n <= max_units, ]
  for (i in seq_len(nrow(smp))) {
    um <- u[u$municipio_tse == smp$municipio_tse[i], ]
    m <- ec_margins(um)
    seed <- seed_for("2026-presidente|metodo-1.0.0", smp$municipio_tse[i], "md-bayes")
    fit <- ec_fit_md(m$O, m$D, params, seed)
    row <- tibble::tibble(config = label, municipio_tse = smp$municipio_tse[i], uf = smp$uf[i], n_units = smp$n[i],
                          stratum = smp$stratum[i], status = fit$status,
                          rhat_max = fit$diagnostics$rhat_max %||% NA_real_, ess_min = fit$diagnostics$ess_min %||% NA_real_,
                          worst_cell = fit$diagnostics$worst_cell %||% NA_character_,
                          merged = paste(fit$diagnostics$merged, collapse = ";"),
                          predicted_s = fit$diagnostics$predicted_s, runtime_s = round(fit$runtime_s, 1))
    print(row)
    append_csv(row, "md_bayes.csv")
  }
}

if (stage == "pilot") {
  mun <- args[[2]]
  um <- read_units(sprintf("municipio_tse = '%s'", mun))
  m <- ec_margins(um)
  act <- ec_active_categories(m$O, m$D)
  df <- data.frame(m$O[, act$origins], m$D[, act$destinations])
  names(df) <- c(paste0("o_", act$origins), paste0("d_", act$destinations))
  f <- stats::as.formula(sprintf("cbind(%s) ~ cbind(%s)", paste0("d_", act$destinations, collapse = ","), paste0("o_", act$origins, collapse = ",")))
  t200 <- system.time(suppressWarnings(eiPack::ei.MD.bayes(f, data = df, sample = 10, thin = 1, burnin = 190, ret.beta = "d")))[["elapsed"]]
  cfg <- params$execucao$eipack
  iters <- cfg$ntunes * cfg$tune_draws + params$estimacao$cadeias * (cfg$burnin + cfg$amostras * cfg$thin)
  t_lp <- system.time(lp <- ec_fit_lphom(m$O, m$D))[["elapsed"]]
  t_cv <- system.time(pc <- ec_predictive_check(m$O, m$D, params$estimacao$k_folds, 1))[["elapsed"]]
  res <- tibble::tibble(municipio_tse = mun, n_units = nrow(um), eipack_s_per_iter = t200 / 200,
                        eipack_us_per_unit_iter = 1e6 * t200 / 200 / nrow(um), md_predicted_s = t200 / 200 * iters,
                        lphom_s = t_lp, cv_s = t_cv, cv_model = pc$model_error, cv_null = pc$null_error)
  print(res)
  append_csv(res, "pilot.csv")
}

if (stage == "ecolrxc") {
  mun <- args[[2]]
  um <- read_units(sprintf("municipio_tse = '%s'", mun))
  m <- ec_margins(um)
  t <- system.time(r <- ec_fit_ecolrxc(m$O, m$D))[["elapsed"]]
  res <- tibble::tibble(municipio_tse = mun, n_units = nrow(um), status = r$status, runtime_s = t)
  print(res)
  append_csv(res, "ecolrxc.csv")
}

if (stage == "calib") {
  params$calibracao$municipios_por_estrato <- as.integer(args[[2]])
  if (length(args) >= 3) params$calibracao$estratos <- as.numeric(strsplit(args[[3]], ",")[[1]])
  if (length(args) >= 4) params$calibracao$max_unidades <- as.integer(args[[4]])
  u <- read_units()
  res <- ec_calibrate(u, params, seed = 20261025L)
  cat("status:", res$status, "\n", res$decision, "\n runtime:", res$runtime_s, "\n")
  print(res$report)
  print(attr(res$report, "grid"))
  fits <- attr(res$report, "fits")
  if (!is.null(fits)) append_csv(fits, "calibration_fits.csv")
  append_csv(res$report, "calibration_report.csv")
  if (!is.null(attr(res$report, "grid"))) append_csv(attr(res$report, "grid"), "calibration_grid.csv")
}

if (stage == "dm") {
  source("tests/benchmark/experimento_dm.R")
  mun <- args[[2]]
  um <- read_units(sprintf("municipio_tse = '%s'", mun))
  m <- ec_margins(um)
  exec <- list(cadeias = 4, dm = list(alpha_prior = 2, piloto = 4000, iteracoes = if (length(args) >= 3) as.integer(args[[3]]) else 25000,
                                      thin = 10, extensoes_max = 3, amostras_contagem = 400, rhat_alvo = 1.01, ess_alvo = 400))
  fit <- ec_fit_md_dm(m$O, m$D, exec, 11L, 1e6)
  conv <- ec_convergence(fit$conv_draws)
  res <- tibble::tibble(municipio_tse = mun, n_units = nrow(um), rhat_max = conv$rhat_max, ess_min = conv$ess_min,
                        acceptance = fit$acc_rate, rounds = fit$rounds, iterations_per_chain = fit$iterations_per_chain,
                        runtime_s = fit$runtime_s)
  print(res)
  append_csv(res, "dm_experiment.csv")
}
