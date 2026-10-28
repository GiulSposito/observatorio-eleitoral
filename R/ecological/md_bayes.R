# Motor bayesiano "md-bayes" (05 §5.2): Multinomial-Dirichlet hierárquico de Rosen et al. (2001) via
# eiPack::ei.MD.bayes. A estimativa publicada é a média posterior de Cell.counts (contagens municipais
# somadas nas unidades); R-hat e ESS são calculados sobre essas contagens, que é o que se publica.
#
# Antes de ajustar:
# - categorias com margem municipal zero saem do ajuste e voltam como zeros;
# - categorias de população (N, S) com margem quase zero são fundidas com a abstenção (X) do mesmo
#   turno, porque linhas e colunas minúsculas misturam mal e não têm informação própria. Depois do
#   ajuste, as células da categoria fundida são repartidas na proporção das margens (N herda as
#   taxas de X na origem; S recebe a parte proporcional da coluna X no destino). Essa repartição é
#   declarada em diagnostics$merged e as células continuam sujeitas aos limites determinísticos.

ec_md_version <- function() paste0("eiPack-", as.character(utils::packageVersion("eiPack")))

ec_draws_to_summary <- function(draws_list, level) {
  all <- do.call(rbind, draws_list)
  a <- (1 - level) / 2
  list(
    mean = colMeans(all),
    low = apply(all, 2, stats::quantile, probs = a, names = FALSE),
    high = apply(all, 2, stats::quantile, probs = 1 - a, names = FALSE)
  )
}

# R-hat (Gelman-Rubin, univariado) e ESS somado entre cadeias, nas células com variância posterior.
ec_convergence <- function(draws_list) {
  all <- do.call(rbind, draws_list)
  keep <- which(apply(all, 2, stats::var) > 1e-8)
  if (!length(keep)) return(list(rhat_max = 1, ess_min = Inf, worst_cell = NA_character_))
  ml <- coda::mcmc.list(lapply(draws_list, function(x) coda::mcmc(x[, keep, drop = FALSE])))
  rh <- tryCatch(coda::gelman.diag(ml, autoburnin = FALSE, multivariate = FALSE)$psrf[, 1],
                 error = function(e) rep(Inf, length(keep)))
  es <- coda::effectiveSize(ml)
  list(rhat_max = max(rh, na.rm = TRUE), ess_min = min(es, na.rm = TRUE),
       worst_cell = colnames(all)[keep][which.max(rh)])
}

# Fusão de categorias de população quase vazias com a abstenção do mesmo turno.
ec_merge_small_population <- function(O, D, min_share) {
  tot <- sum(O)
  merged <- character()
  O2 <- O
  D2 <- D
  if (sum(O[, "N"]) > 0 && sum(O[, "N"]) / tot < min_share) {
    O2[, "X"] <- O2[, "X"] + O2[, "N"]
    O2[, "N"] <- 0
    merged <- c(merged, "N>X")
  }
  if (sum(D[, "S"]) > 0 && sum(D[, "S"]) / tot < min_share) {
    D2[, "X"] <- D2[, "X"] + D2[, "S"]
    D2[, "S"] <- 0
    merged <- c(merged, "S>X")
  }
  list(O = O2, D = D2, merged = merged)
}

# Reparte, em cada amostra, as células fundidas de volta nas categorias originais (proporcional às margens).
ec_unmerge_draws <- function(draws, O, D, merged) {
  cells <- colnames(draws)
  if ("N>X" %in% merged) {
    f <- sum(O[, "N"]) / (sum(O[, "N"]) + sum(O[, "X"]))
    for (d in EC_DESTINATIONS) {
      xc <- ec_cell_id("X", d)
      nc <- ec_cell_id("N", d)
      draws[, nc] <- draws[, xc] * f
      draws[, xc] <- draws[, xc] * (1 - f)
    }
  }
  if ("S>X" %in% merged) {
    g <- sum(D[, "S"]) / (sum(D[, "S"]) + sum(D[, "X"]))
    for (o in EC_ORIGINS) {
      if (o == "N") next  # N -> S é zero estrutural
      xc <- ec_cell_id(o, "X")
      sc <- ec_cell_id(o, "S")
      draws[, sc] <- draws[, xc] * g
      draws[, xc] <- draws[, xc] * (1 - g)
    }
  }
  draws[, cells, drop = FALSE]
}

ec_fit_md_eipack <- function(O, D, params, seed) {
  exec <- params$execucao
  cfg <- exec$eipack
  n_chains <- params$estimacao$cadeias
  budget_s <- exec$orcamento_segundos_por_municipio
  t0 <- proc.time()[["elapsed"]]
  mg <- ec_merge_small_population(O, D, cfg$fundir_populacao_abaixo_de)
  act <- ec_active_categories(mg$O, mg$D)
  df <- data.frame(mg$O[, act$origins, drop = FALSE], mg$D[, act$destinations, drop = FALSE])
  names(df) <- c(paste0("o_", act$origins), paste0("d_", act$destinations))
  f <- stats::as.formula(sprintf("cbind(%s) ~ cbind(%s)",
                                 paste0("d_", act$destinations, collapse = ", "),
                                 paste0("o_", act$origins, collapse = ", ")))
  lam <- c(cfg$lambda1, cfg$lambda2)
  # piloto para prever o custo antes de rodar tudo
  set.seed(seed)
  tp <- system.time(suppressWarnings(eiPack::ei.MD.bayes(f, data = df, sample = 10, thin = 1, burnin = 190,
                                                         lambda1 = lam[1], lambda2 = lam[2], ret.beta = "d")))[["elapsed"]]
  per_iter <- tp / 200
  tune_iters <- if (isTRUE(cfg$tune)) cfg$ntunes * cfg$tune_draws else 0
  predicted <- per_iter * (tune_iters + n_chains * (cfg$burnin + cfg$amostras * cfg$thin))
  diag_base <- list(engine = "eipack", predicted_s = round(predicted, 1), merged = I(mg$merged),
                    lambda1 = lam[1], lambda2 = lam[2], burnin = cfg$burnin, thin = cfg$thin, samples = cfg$amostras)
  if (predicted > budget_s) {
    return(list(status = "failed", reason = sprintf("custo previsto %.0f s acima do orçamento de %.0f s", predicted, budget_s),
                runtime_s = proc.time()[["elapsed"]] - t0, diagnostics = diag_base))
  }
  tn <- if (isTRUE(cfg$tune)) {
    set.seed(seed + 1L)
    suppressWarnings(eiPack::tuneMD(f, data = df, ntunes = cfg$ntunes, totaldraws = cfg$tune_draws,
                                    lambda1 = lam[1], lambda2 = lam[2]))
  } else NULL
  cell_names <- ec_cell_id(ec_cell_grid()$origin, ec_cell_grid()$destination)
  draws <- lapply(seq_len(n_chains), function(k) {
    set.seed(seed + 1000L * k)
    fit <- suppressWarnings(eiPack::ei.MD.bayes(f, data = df, sample = cfg$amostras, thin = cfg$thin, burnin = cfg$burnin,
                                                lambda1 = lam[1], lambda2 = lam[2], tune.list = tn,
                                                ret.beta = "d", ret.mcmc = TRUE))
    cc <- as.matrix(fit$draws$Cell.counts)
    # nomes "ccount.o_A.d_A" -> "A>A"
    parts <- strsplit(sub("^ccount\\.", "", colnames(cc)), ".", fixed = TRUE)
    colnames(cc) <- vapply(parts, function(p) ec_cell_id(sub("^o_", "", p[1]), sub("^d_", "", p[2])), character(1))
    full <- matrix(0, nrow(cc), length(cell_names), dimnames = list(NULL, cell_names))
    full[, colnames(cc)] <- cc
    ec_unmerge_draws(full, O, D, mg$merged)
  })
  list(status = "ok", draws = draws, runtime_s = proc.time()[["elapsed"]] - t0, diagnostics = diag_base)
}

# Interface interna usada por ec_estimate(): roda o eiPack e resume (média, intervalo, convergência).
ec_fit_md <- function(O, D, params, seed) {
  fit <- ec_fit_md_eipack(O, D, params, seed)
  version <- ec_md_version()
  if (!identical(fit$status, "ok")) {
    return(list(status = "failed", reason = fit$reason, version = version, runtime_s = fit$runtime_s,
                diagnostics = fit$diagnostics))
  }
  conv <- ec_convergence(fit$draws)
  summ <- ec_draws_to_summary(fit$draws, params$estimacao$intervalo_nivel)
  ok <- is.finite(conv$rhat_max) && conv$rhat_max <= params$estimacao$rhat_max && conv$ess_min >= params$estimacao$ess_min
  list(
    status = if (ok) "ok" else "failed",
    reason = if (ok) NULL else sprintf("sem convergência: R-hat máximo %.3f (célula %s), ESS mínimo %.0f",
                                       conv$rhat_max, conv$worst_cell, conv$ess_min),
    version = version, runtime_s = fit$runtime_s, summary = summ,
    diagnostics = c(fit$diagnostics, list(rhat_max = round(conv$rhat_max, 4), ess_min = round(conv$ess_min, 1),
                                          worst_cell = conv$worst_cell))
  )
}
