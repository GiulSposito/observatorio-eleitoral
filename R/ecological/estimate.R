# Estimação ecológica por município (05 §5): métodos, grau de identificação, checagem preditiva e
# regras de publicação. Interface pública: ec_estimate().

ec_flow_columns <- c("origin", "destination", "model_id", "model_version", "assumption_id", "estimate_votes",
                     "estimate_statistic", "interval_low", "interval_high", "interval_type", "interval_level",
                     "method_range_low", "method_range_high", "bounds_min", "bounds_max", "identification_ratio",
                     "identification_class", "model_status")

ec_empty_flows <- function() {
  tibble::tibble(
    origin = character(), destination = character(), model_id = character(), model_version = character(),
    assumption_id = character(), estimate_votes = double(), estimate_statistic = character(),
    interval_low = double(), interval_high = double(), interval_type = character(), interval_level = double(),
    method_range_low = double(), method_range_high = double(), bounds_min = double(), bounds_max = double(),
    identification_ratio = double(), identification_class = character(), model_status = character()
  )
}

ec_empty_diag <- function() structure(list(), names = character())

ec_fit_ecolrxc <- function(O, D) {
  act <- ec_active_categories(O, D)
  t0 <- proc.time()[["elapsed"]]
  fit <- tryCatch(suppressMessages(suppressWarnings(
    ecolRxC::ecolRxC(as.data.frame(O[, act$origins, drop = FALSE]), as.data.frame(D[, act$destinations, drop = FALSE]),
                     census.changes = "raw")
  )), error = function(e) e)
  if (inherits(fit, "error")) return(list(status = "failed", reason = conditionMessage(fit), runtime_s = proc.time()[["elapsed"]] - t0))
  V <- as.matrix(fit$VTM.votes)[seq_along(act$origins), seq_along(act$destinations), drop = FALSE]
  dimnames(V) <- list(act$origins, act$destinations)
  full <- matrix(0, length(EC_ORIGINS), length(EC_DESTINATIONS), dimnames = list(EC_ORIGINS, EC_DESTINATIONS))
  full[act$origins, act$destinations] <- V
  list(status = "ok", counts = full, runtime_s = proc.time()[["elapsed"]] - t0)
}

# Classes de identificação (05 §5.4) a partir dos vetores por célula (ordem de ec_cell_grid()).
ec_identification <- function(W, P_width, F_width, row_total, est_params) {
  det_lim <- pmax(est_params$largura_determinada$votos_minimo, est_params$largura_determinada$fracao_linha * row_total)
  R <- ifelse(W > 0, pmax(P_width, F_width, na.rm = TRUE) / W, NA_real_)
  cls <- ifelse(W <= det_lim, "determined",
         ifelse(R <= est_params$r_estimado, "estimated",
         ifelse(R <= est_params$r_fraco, "weak", "not_identified")))
  list(ratio = R, class = cls)
}

ec_change_mass_share <- function(origin, destination, estimate, cls) {
  change <- !(ec_cell_id(origin, destination) %in% EC_RETENTION)
  mass <- sum(estimate[change])
  if (mass <= 0) return(1)
  sum(estimate[change & cls %in% c("determined", "estimated")]) / mass
}

# Núcleo sem as regras de publicação: usado por ec_estimate() e pela calibração.
ec_estimate_core <- function(O, D, params, seed) {
  est <- params$estimacao
  exec <- params$execucao
  grid <- ec_cell_grid()
  fb <- ec_frechet_sum(O, D)
  bmin <- ec_matrix_to_long(fb$min, "v")$v
  bmax <- ec_matrix_to_long(fb$max, "v")$v

  md <- ec_fit_md(O, D, params, seed)
  lp <- ec_fit_lphom(O, D)
  use_ecx <- isTRUE(exec$usar_ecolrxc) && nrow(O) <= exec$ecolrxc_max_unidades
  ecx <- if (use_ecx) ec_fit_ecolrxc(O, D) else list(status = "skipped", runtime_s = 0)

  methods <- list(
    list(method_id = "md-bayes", version = md$version, status = md$status, runtime_s = round(md$runtime_s, 2),
         diagnostics = c(md$diagnostics, if (!is.null(md$reason)) list(reason = md$reason))),
    list(method_id = "lphom", version = ec_lphom_version(), status = lp$status, runtime_s = round(lp$runtime_s, 2),
         diagnostics = if (!is.null(lp$reason)) list(reason = lp$reason) else ec_empty_diag()),
    list(method_id = "ecolrxc", version = paste0("ecolRxC-", as.character(utils::packageVersion("ecolRxC"))),
         status = ecx$status, runtime_s = round(ecx$runtime_s, 2),
         diagnostics = if (!is.null(ecx$reason)) list(reason = ecx$reason) else ec_empty_diag())
  )
  out <- list(methods = methods, md = md, bounds_min = bmin, bounds_max = bmax)
  if (!identical(md$status, "ok")) {
    out$status <- "failed"
    out$reason <- paste("md-bayes:", md$reason)
    return(out)
  }
  points <- list(md$summary$mean)
  if (identical(lp$status, "ok")) points[[length(points) + 1]] <- ec_matrix_to_long(lp$counts, "v")$v
  if (identical(ecx$status, "ok")) points[[length(points) + 1]] <- ec_matrix_to_long(ecx$counts, "v")$v
  if (length(points) < 2) {
    out$status <- "failed"
    out$reason <- "menos de dois métodos com solução"
    return(out)
  }
  pm <- do.call(cbind, points)
  row_total <- colSums(O)[grid$origin]
  idf <- ec_identification(
    W = bmax - bmin, P_width = md$summary$high - md$summary$low,
    F_width = apply(pm, 1, max) - apply(pm, 1, min), row_total = row_total, est_params = est
  )
  tol <- pmax(1, 0.005 * row_total)
  outside <- md$summary$mean < bmin - tol | md$summary$mean > bmax + tol
  out$status <- if (any(outside)) "failed" else "ok"
  if (any(outside)) out$reason <- sprintf("estimativa fora dos limites determinísticos em %d célula(s)", sum(outside))
  out$cells <- tibble::tibble(
    origin = grid$origin, destination = grid$destination,
    estimate_votes = md$summary$mean,
    interval_low = pmax(md$summary$low, bmin), interval_high = pmin(md$summary$high, bmax),
    method_range_low = apply(pm, 1, min), method_range_high = apply(pm, 1, max),
    bounds_min = bmin, bounds_max = bmax,
    identification_ratio = idf$ratio, identification_class = idf$class
  )
  out
}

# Interface pública (R/README.md). units: unidades de UM município com in_transition_analysis.
ec_estimate <- function(units, params, seed, context = list(eligible_share_used = NA_real_)) {
  est <- params$estimacao
  n <- if (is.null(units)) 0L else nrow(units)
  calib <- params$calibration_id
  model <- function(status, reason = NULL, methods = list(), pc = NULL, share = NULL) {
    list(status = status, reason_unavailable = reason, methods = methods, predictive_check = pc,
         identified_change_share = share, n_units_used = as.integer(n), calibration_id = calib)
  }
  share_used <- context$eligible_share_used
  if (n < est$n_secoes_min) {
    return(list(flows = ec_empty_flows(), status = "insufficient_data",
                model = model("insufficient_data", sprintf("Menos de %d seções comparáveis (%d).", est$n_secoes_min, n))))
  }
  if (!is.null(share_used) && !is.na(share_used) && share_used < params$cobertura_minima) {
    return(list(flows = ec_empty_flows(), status = "insufficient_data",
                model = model("insufficient_data", sprintf("Seções comparáveis cobrem %.0f%% dos aptos; mínimo de %.0f%%.",
                                                           100 * share_used, 100 * params$cobertura_minima))))
  }
  m <- ec_margins(units)
  core <- ec_estimate_core(m$O, m$D, params, seed)
  if (!identical(core$status, "ok")) {
    return(list(flows = ec_empty_flows(), status = "failed", model = model("failed", core$reason, core$methods)))
  }
  pc <- ec_predictive_check(m$O, m$D, est$k_folds, seed + 17L)
  pc$passed <- pc$model_error <= est$ganho_preditivo_min * pc$null_error
  pc$model_error <- round(pc$model_error, 5)
  pc$null_error <- round(pc$null_error, 5)
  cells <- core$cells
  share <- ec_change_mass_share(cells$origin, cells$destination, cells$estimate_votes, cells$identification_class)
  status <- if (isTRUE(pc$passed) && share >= est$massa_identificada_min) "ready" else "partial"
  flows <- cells |>
    dplyr::mutate(
      model_id = "md-bayes", model_version = core$md$version,
      assumption_id = "homogeneidade-municipal+pop-liquida-minima",
      estimate_statistic = "posterior_mean", interval_type = "credible_interval",
      interval_level = est$intervalo_nivel, model_status = status
    )
  flows <- flows[, ec_flow_columns]
  list(flows = flows, status = status, model = model(status, NULL, core$methods, pc, round(share, 4)))
}
