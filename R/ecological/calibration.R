# Calibração por simulação (05 §5.6).
#
# Usa só as margens do 1º turno (o_A..o_X) de municípios reais de 2026, estratificados por número de
# unidades; o 2º turno é gerado com matrizes conhecidas sob quatro processos:
#   G1 taxas homogêneas; G2 taxas que variam com a composição da unidade; G3 taxas que variam por zona;
#   G4 = G2 + mudança líquida de aptos (pseudo-categorias N/S).
# Roda o mesmo núcleo de estimação (ec_estimate_core) e mede, por célula, cobertura do intervalo e erro.
# Escolhe r_estimado (maior limiar com cobertura >= alvo em G2–G4 nas células "estimated"), r_fraco
# (maior limiar com cobertura >= cobertura_fraca), ambos dentro da faixa de tamanho validada, e essa faixa
# [n_secoes_min, n_secoes_max): estratos contíguos cuja cobertura das células estimated atinge o alvo
# (ec_calibration_range). Se nada atingir o alvo, status "failed" e a decisão é publicar só limites.

ec_calibration_base_P <- function() {
  P0 <- rbind(
    A = c(0.92, 0.02, 0.02, 0.04),
    B = c(0.02, 0.92, 0.02, 0.04),
    O = c(0.35, 0.35, 0.12, 0.18),
    I = c(0.20, 0.20, 0.40, 0.20),
    X = c(0.08, 0.08, 0.02, 0.82)
  )
  colnames(P0) <- c("A", "B", "I", "X")
  P0
}

ec_rdirichlet <- function(alpha) {
  g <- stats::rgamma(length(alpha), alpha)
  g / sum(g)
}

ec_softmax_shift <- function(p, shift) {
  lp <- log(pmax(p, 1e-12)) + shift
  e <- exp(lp - max(lp))
  e / sum(e)
}

# Gera o 2º turno de um município a partir das margens reais do 1º turno.
ec_simulate_t2 <- function(u1, process, seed, kappa = 40, beta = 0.6, zone_sd = 0.5, pop_share = 0.12) {
  set.seed(seed)
  P0 <- ec_calibration_base_P()
  Ptrue <- t(apply(P0, 1, function(p) ec_rdirichlet(kappa * p)))
  colnames(Ptrue) <- colnames(P0)
  n <- nrow(u1)
  o <- as.matrix(u1[, paste0("o_", c("A", "B", "O", "I", "X"))])
  colnames(o) <- c("A", "B", "O", "I", "X")
  shareA <- (o[, "A"] + 0.5) / (o[, "A"] + o[, "B"] + 1)
  z <- as.vector(scale(stats::qlogis(shareA)))
  z[!is.finite(z)] <- 0
  zona <- vapply(strsplit(u1$comparison_unit_id, "-", fixed = TRUE), function(p) p[2], character(1))
  zeff <- stats::rnorm(length(unique(zona)), 0, zone_sd)
  names(zeff) <- unique(zona)
  heter_rows <- c("O", "I", "X")
  flows <- array(0, c(n, length(EC_ORIGINS), length(EC_DESTINATIONS)), dimnames = list(NULL, EC_ORIGINS, EC_DESTINATIONS))
  for (i in seq_len(n)) {
    for (r in c("A", "B", "O", "I", "X")) {
      p <- Ptrue[r, ]
      if (process %in% c("G2", "G4") && r %in% heter_rows) p <- ec_softmax_shift(p, c(beta * z[i], -beta * z[i], 0, 0))
      if (process == "G3" && r %in% heter_rows) {
        u <- zeff[[zona[i]]]
        p <- ec_softmax_shift(p, c(u, -u, 0, u / 2))
      }
      flows[i, r, c("A", "B", "I", "X")] <- as.vector(stats::rmultinom(1, o[i, r], p))
    }
  }
  if (process == "G4") {
    pick <- which(stats::runif(n) < pop_share)
    for (i in pick) {
      d <- sample(c(-2L, -1L, 1L, 2L), 1)
      if (d > 0) {
        flows[i, "N", c("A", "B", "I", "X")] <- as.vector(stats::rmultinom(1, d, c(0.3, 0.3, 0.05, 0.35)))
      } else {
        for (q in seq_len(-d)) {
          cand <- which(flows[i, c("A", "B", "O", "I", "X"), "X"] > 0)
          if (!length(cand)) break
          r <- c("A", "B", "O", "I", "X")[cand[sample.int(length(cand), 1)]]
          flows[i, r, "X"] <- flows[i, r, "X"] - 1
          flows[i, r, "S"] <- flows[i, r, "S"] + 1
        }
      }
    }
  }
  units <- tibble::tibble(comparison_unit_id = u1$comparison_unit_id)
  for (k in EC_ORIGINS) units[[paste0("o_", k)]] <- as.integer(rowSums(flows[, k, , drop = FALSE]))
  for (k in EC_DESTINATIONS) units[[paste0("d_", k)]] <- as.integer(rowSums(flows[, , k, drop = FALSE]))
  units$population_status <- ifelse(units$o_N > 0 | units$d_S > 0, "net_change", "closed")
  list(units = units, truth = apply(flows, c(2, 3), sum))
}

ec_calibration_strata <- function(n, breaks) {
  k <- length(breaks)
  labels <- c(if (k > 1) paste0(breaks[-k], "-", breaks[-1] - 1), paste0(breaks[k], "+"))
  cut(n, breaks = c(breaks, Inf), right = FALSE, dig.lab = 6, labels = labels)
}

# Interface pública (R/README.md): margins_t1 é a tabela nacional de unidades (só as margens do 1º
# turno são usadas).
ec_calibrate <- function(margins_t1, params, seed) {
  cal <- params$calibracao
  est <- params$estimacao
  t_start <- proc.time()[["elapsed"]]
  calibration_id <- paste0("cal-2026-presidente-", substr(digest::digest(list(params$method_version, seed, cal), algo = "xxhash32"), 1, 8))
  counts <- stats::aggregate(list(n = rep(1L, nrow(margins_t1))), list(municipio_tse = margins_t1$municipio_tse), sum)
  breaks <- unlist(cal$estratos)
  counts <- counts[counts$n >= min(breaks) & counts$n <= cal$max_unidades, , drop = FALSE]
  empty_report <- tibble::tibble(process = character(), stratum = character(), fits = integer(), converged = integer(),
                                 cells_estimated = integer(), coverage_estimated = double(), mae_estimated = double())
  if (!nrow(counts)) {
    return(list(report = empty_report, thresholds = list(calibration_id = calibration_id, calibration_status = "failed"),
                calibration_id = calibration_id,
                status = "failed", decision = "Sem municípios elegíveis para calibrar: publicar só limites.",
                runtime_s = proc.time()[["elapsed"]] - t_start))
  }
  counts$stratum <- as.character(ec_calibration_strata(counts$n, breaks))
  set.seed(seed)
  sample_mun <- do.call(rbind, lapply(split(counts, counts$stratum), function(s) {
    s[sample.int(nrow(s), min(nrow(s), cal$municipios_por_estrato)), , drop = FALSE]
  }))

  # Cada ajuste tem semente própria (seed + k), então rodar em paralelo não muda o resultado.
  procs <- unlist(cal$processos)
  tasks <- expand.grid(g = seq_along(procs), i = seq_len(nrow(sample_mun)))
  tasks$k <- seq_len(nrow(tasks))
  run_task <- function(t) {
    i <- tasks$i[t]; g <- procs[tasks$g[t]]; k <- tasks$k[t]
    mun <- sample_mun$municipio_tse[i]
    u1 <- margins_t1[margins_t1$municipio_tse == mun, , drop = FALSE]
    sim <- ec_simulate_t2(u1, g, seed + k)
    m <- ec_margins(sim$units)
    core <- ec_estimate_core(m$O, m$D, params, seed + 1000L + k)
    pc_pass <- NA
    if (identical(core$status, "ok")) {
      pc <- ec_predictive_check(m$O, m$D, est$k_folds, seed + 2000L + k)
      pc_pass <- pc$model_error <= est$ganho_preditivo_min * pc$null_error
    }
    fit <- tibble::tibble(municipio_tse = mun, n_units = nrow(u1), stratum = sample_mun$stratum[i], process = g,
                          status = core$status, reason = core$reason %||% NA_character_,
                          rhat_max = core$md$diagnostics$rhat_max %||% NA_real_,
                          predictive_pass = pc_pass, runtime_s = core$md$runtime_s %||% NA_real_)
    cell <- NULL
    if (identical(core$status, "ok")) {
      cc <- core$cells
      truth <- mapply(function(o, d) sim$truth[o, d], cc$origin, cc$destination)
      row_total <- colSums(m$O)[cc$origin]
      det_lim <- pmax(est$largura_determinada$votos_minimo, est$largura_determinada$fracao_linha * row_total)
      cell <- tibble::tibble(
        municipio_tse = mun, stratum = sample_mun$stratum[i], process = g,
        origin = cc$origin, destination = cc$destination, truth = truth,
        estimate = cc$estimate_votes, low = cc$interval_low, high = cc$interval_high,
        W = cc$bounds_max - cc$bounds_min, R = cc$identification_ratio,
        determined = (cc$bounds_max - cc$bounds_min) <= det_lim,
        covered = truth >= cc$interval_low - 0.5 & truth <= cc$interval_high + 0.5,
        abs_err = abs(cc$estimate_votes - truth)
      )
    }
    list(fit = fit, cells = cell)
  }
  out <- ec_parallel_map(seq_len(nrow(tasks)), run_task, params$execucao$workers %||% 1L)
  fits <- dplyr::bind_rows(lapply(out, `[[`, "fit"))
  cells <- dplyr::bind_rows(lapply(out, `[[`, "cells"))
  if (!nrow(cells)) {
    cells <- tibble::tibble(municipio_tse = character(), stratum = character(), process = character(), origin = character(),
                            destination = character(), truth = double(), estimate = double(), low = double(), high = double(),
                            W = double(), R = double(), determined = logical(), covered = logical(), abs_err = double())
  }

  hetero <- c("G2", "G3", "G4")
  grid <- unlist(cal$grade_r)
  pool <- cells[!cells$determined & !is.na(cells$R) & cells$R <= max(grid) & cells$process %in% hetero, , drop = FALSE]
  # Faixa de tamanho validada: os limiares de R só valem dentro dela (pool restrito)
  size_range <- ec_calibration_range(pool, cal$cobertura_alvo)
  pool <- pool[ec_stratum_lower(pool$stratum) >= size_range$n_min & ec_stratum_lower(pool$stratum) < size_range$n_max, ,
               drop = FALSE]
  grid_tab <- tibble::tibble(
    r = grid,
    cells = vapply(grid, function(t) sum(pool$R <= t), integer(1)),
    coverage = vapply(grid, function(t) { x <- pool$covered[pool$R <= t]; if (length(x)) mean(x) else NA_real_ }, numeric(1))
  )
  ok_est <- grid_tab$r[!is.na(grid_tab$coverage) & grid_tab$coverage >= cal$cobertura_alvo & grid_tab$cells >= cal$min_celulas]
  ok_weak <- grid_tab$r[!is.na(grid_tab$coverage) & grid_tab$coverage >= cal$cobertura_fraca & grid_tab$cells >= cal$min_celulas]

  report_for <- function(r_est) {
    if (!nrow(fits)) return(empty_report)
    keys <- unique(fits[, c("process", "stratum")])
    dplyr::bind_rows(lapply(seq_len(nrow(keys)), function(j) {
      f <- fits[fits$process == keys$process[j] & fits$stratum == keys$stratum[j], ]
      cl <- if (nrow(cells)) cells[cells$process == keys$process[j] & cells$stratum == keys$stratum[j] &
                                     !cells$determined & !is.na(cells$R) & cells$R <= r_est, ] else cells
      tibble::tibble(process = keys$process[j], stratum = keys$stratum[j], fits = nrow(f),
                     converged = sum(f$status == "ok"), cells_estimated = nrow(cl),
                     coverage_estimated = if (nrow(cl)) mean(cl$covered) else NA_real_,
                     mae_estimated = if (nrow(cl)) mean(cl$abs_err) else NA_real_)
    }))
  }

  if (!length(ok_est)) {
    conv_rate <- if (nrow(fits)) mean(fits$status == "ok") else 0
    report <- report_for(est$r_estimado)
    attr(report, "grid") <- grid_tab
    attr(report, "fits") <- fits
    return(list(
      report = report, thresholds = list(calibration_id = calibration_id, calibration_status = "failed"),
      calibration_id = calibration_id, status = "failed",
      decision = sprintf(paste0("Nenhum limiar atinge cobertura de %.0f%% nas células estimadas (G2–G4); ",
                                "o motor principal convergiu em %.0f%% dos ajustes simulados. Publicar só limites."),
                         100 * cal$cobertura_alvo, 100 * conv_rate),
      runtime_s = proc.time()[["elapsed"]] - t_start
    ))
  }
  r_est <- max(ok_est)
  r_weak <- max(c(r_est, ok_weak[ok_weak >= r_est]))
  report <- report_for(r_est)
  n_min <- max(est$n_secoes_min, size_range$n_min)
  n_max <- size_range$n_max
  attr(report, "grid") <- grid_tab
  attr(report, "fits") <- fits
  list(
    report = report,
    thresholds = list(r_estimado = r_est, r_fraco = r_weak, n_secoes_min = n_min,
                      n_secoes_max = if (is.finite(n_max)) n_max else NULL,
                      calibration_id = calibration_id, calibration_status = "passed"),
    calibration_id = calibration_id, status = "passed",
    decision = sprintf("r_estimado = %.2f, r_fraco = %.2f, n_secoes_min = %d%s (cobertura-alvo %.0f%% em G2–G4).",
                       r_est, r_weak, as.integer(n_min),
                       if (is.finite(n_max)) sprintf(", n_secoes_max = %d", as.integer(n_max)) else "",
                       100 * cal$cobertura_alvo),
    runtime_s = proc.time()[["elapsed"]] - t_start
  )
}

ec_stratum_lower <- function(stratum) as.numeric(sub("[-+].*$", "", stratum))

# Faixa de tamanho em que a estimação foi validada (05 §5.6): estratos contíguos, a partir do primeiro
# que atinge a cobertura-alvo nas células estimadas de G2–G4, até o primeiro que não atinge (exclusivo).
# Estrato sem célula estimada não conta como validado. Sem estrato validado: n_min = n_max = Inf.
ec_calibration_range <- function(pool, alvo) {
  if (!nrow(pool)) return(list(n_min = Inf, n_max = Inf))
  cov <- tapply(pool$covered, pool$stratum, mean)
  lower <- ec_stratum_lower(names(cov))
  ord <- order(lower)
  good <- cov[ord] >= alvo
  if (!any(good)) return(list(n_min = Inf, n_max = Inf))
  first <- which(good)[1]
  after <- which(!good & seq_along(good) > first)
  list(n_min = lower[ord][first], n_max = if (length(after)) lower[ord][after[1]] else Inf)
}

# lapply com processos bifurcados quando workers > 1 (mclapply não existe no Windows).
ec_parallel_map <- function(x, f, workers) {
  if (workers > 1L && .Platform$OS.type == "unix") {
    # o aviso genérico do mclapply sobre erros é substituído pelo erro do próprio processo
    out <- withCallingHandlers(
      parallel::mclapply(x, f, mc.cores = workers, mc.preschedule = FALSE),
      warning = function(w) if (grepl("resulted in an error", conditionMessage(w))) invokeRestart("muffleWarning"))
    bad <- vapply(out, inherits, logical(1), "try-error")
    if (any(bad)) stop(conditionMessage(attr(out[[which(bad)[1]]], "condition")))
    out
  } else {
    lapply(x, f)
  }
}
