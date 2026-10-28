# Motor bayesiano principal "dm-homog" (05 §5.2).
#
# Modelo: taxas de transição homogêneas no município (P, uma linha por origem); as margens de destino de
# cada unidade seguem uma Dirichlet-multinomial com média (composição de origem da unidade) %*% P e
# sobredispersão phi, limitada a [0,5; 1e5] (acima disso a DM é praticamente multinomial e o lgamma
# perde precisão). Prior Dirichlet(alpha) nas linhas de P (alpha = 2: ~2 pseudo-votos por célula) e
# log(phi) ~ N(log 50, 3). N -> S é zero estrutural.
#
# Amostragem: MAP por L-BFGS-B a partir de 3 inícios; covariância de Laplace no MAP; piloto de passeio
# aleatório que estima a covariância empírica da proposta; >= 4 cadeias de passeio aleatório com essa
# proposta, iniciadas em torno do MAP e estendidas por rodadas até R-hat/ESS ou orçamento. O núcleo
# (log-posterior e cadeia) é C++ (dm_homog.cpp, Rcpp).
#
# Escala: acima de `max_unidades_ajuste` unidades, a verossimilhança é avaliada em grupos de unidades de
# composição parecida (ec_group_units(), mesma regra do lphom: ordena pela participação de A e depois
# de abstenção no 1º turno e soma unidades consecutivas). Sob homogeneidade, somar unidades preserva P.
#
# Contagens publicadas: para cada amostra de P, a tabela interna de cada unidade ORIGINAL é obtida por
# ajuste proporcional iterativo (IPF) às duas margens da unidade, a partir da semente o_ir * P[r, c];
# a contagem municipal é a soma dessas tabelas. Assim as contagens fecham as margens de origem e de
# destino e ficam dentro dos limites de Fréchet por construção. A estimativa publicada é a média
# posterior dessas contagens; R-hat e ESS são calculados sobre elas.

ec_main_model_id <- "dm-homog"
ec_main_version <- function() "dm-homog-1.0.0"

# ---------------------------------------------------------------- utilitários de amostras
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
  nm <- colnames(all)[keep]
  list(rhat_max = max(rh, na.rm = TRUE), ess_min = min(es, na.rm = TRUE),
       worst_cell = if (is.null(nm)) NA_character_ else nm[which.max(rh)])
}

# ---------------------------------------------------------------- núcleo C++
ec_dm_cpp <- local({
  loaded <- FALSE
  function() {
    if (loaded && exists("dm_rw_chain_cpp", mode = "function")) return(invisible(TRUE))
    root <- getOption("caderno.repo_root", ".")
    src <- file.path(root, "R", "ecological", "dm_homog.cpp")
    if (!file.exists(src)) src <- file.path("R", "ecological", "dm_homog.cpp")
    cache <- Sys.getenv("CADERNO_RCPP_CACHE", file.path(tools::R_user_dir("cadernoeleitoral", "cache"), "rcpp"))
    dir.create(cache, recursive = TRUE, showWarnings = FALSE)
    # Workers do crew compartilham o cache: só um compila por vez (trava por diretório); os demais
    # esperam e depois só carregam a biblioteca já compilada.
    lock <- file.path(cache, "compile.lock")
    waited <- 0
    while (!dir.create(lock, showWarnings = FALSE) && waited < 600) {
      Sys.sleep(1)
      waited <- waited + 1
    }
    on.exit(unlink(lock, recursive = TRUE), add = TRUE)
    Rcpp::sourceCpp(src, cacheDir = cache, env = globalenv(), verbose = FALSE)
    loaded <<- TRUE
    invisible(TRUE)
  }
})

# Matriz de posições dos parâmetros: >= 0 índice (base 0) em theta, -1 referência da linha, -2 zero estrutural.
ec_dm_positions <- function(cells) {
  pos <- matrix(-2L, nrow(cells), ncol(cells))
  k <- 0L
  for (r in seq_len(nrow(cells))) {
    free <- which(cells[r, ])
    if (!length(free)) next
    pos[r, free[length(free)]] <- -1L
    for (c in free[-length(free)]) {
      pos[r, c] <- k
      k <- k + 1L
    }
  }
  list(pos = pos, n_free = k)
}

ec_dm_theta_to_P <- function(theta, pos) {
  E <- matrix(-Inf, nrow(pos), ncol(pos))
  E[pos == -1L] <- 0
  free <- pos >= 0L
  E[free] <- theta[pos[free] + 1L]
  E <- E - apply(E, 1, max)
  P <- exp(E)
  P / rowSums(P)
}

# Ajuste proporcional iterativo vetorizado: semente n x R x C, margens de linha (n x R) e coluna (n x C).
ec_ipf <- function(seed_arr, rows, cols, iters = 50, tol = 1e-7) {
  x <- seed_arr
  for (it in seq_len(iters)) {
    rs <- rowSums(x, dims = 2)
    x <- x * array(ifelse(rs > 0, rows / rs, 0), dim(x))
    cs <- colSums(aperm(x, c(2, 1, 3)))
    fac <- ifelse(cs > 0, cols / cs, 0)
    x <- x * aperm(array(fac, c(dim(x)[1], dim(x)[3], dim(x)[2])), c(1, 3, 2))
    if (max(abs(rowSums(x, dims = 2) - rows)) < tol) break
  }
  x
}

# Contagens municipais (vetor na ordem de ec_cell_grid()) para uma matriz P, via IPF nas unidades originais.
ec_dm_counts_for_P <- function(P, Oa, Da, cells, act) {
  n <- nrow(Oa)
  R <- ncol(Oa)
  C <- ncol(Da)
  seed_arr <- array(0, c(n, R, C))
  for (r in seq_len(R)) seed_arr[, r, ] <- outer(Oa[, r], P[r, ])
  seed_arr <- seed_arr + 1e-9 * array(rep(cells * 1, each = n), dim(seed_arr))
  tab <- ec_ipf(seed_arr, Oa, Da)
  M <- colSums(tab, dims = 1)
  dimnames(M) <- list(act$origins, act$destinations)
  ec_matrix_to_long(M, "v")$v
}

# ---------------------------------------------------------------- ajuste
ec_fit_dm_homog <- function(O, D, params, seed, return_chains = FALSE) {
  ec_dm_cpp()
  cfg <- params$execucao$dm_homog
  n_chains <- params$estimacao$cadeias
  budget_s <- params$execucao$orcamento_segundos_por_municipio
  rhat_target <- params$estimacao$rhat_max
  ess_target <- params$estimacao$ess_min
  t0 <- proc.time()[["elapsed"]]
  act <- ec_active_categories(O, D)
  Oa <- O[, act$origins, drop = FALSE]
  Da <- D[, act$destinations, drop = FALSE]
  cells <- ec_allowed_matrix(act$origins, act$destinations)
  pp <- ec_dm_positions(cells)
  d <- pp$n_free + 1L
  gu <- ec_group_units(Oa, Da, cfg$max_unidades_ajuste)
  Og <- gu$O
  Dg <- gu$D
  Ng <- rowSums(Og)
  Xp <- Og / Ng
  lphi_lim <- log(unlist(cfg$phi_limites))
  mu <- log(50)
  sdp <- 3
  lpost <- function(th) dm_logpost_cpp(th, Xp, Dg, Ng, pp$pos, cfg$alpha_prior, lphi_lim[1], lphi_lim[2], mu, sdp)
  nlp <- function(th) { v <- lpost(th); if (is.finite(v)) -v else 1e300 }
  cell_names <- ec_cell_id(ec_cell_grid()$origin, ec_cell_grid()$destination)
  # células usadas no diagnóstico de convergência: as não determinadas pelos limites (05 §5.3/§5.4); nas
  # determinadas a interface mostra o próprio limite, e a estimativa não pesa em nenhuma decisão
  fb <- ec_frechet_sum(O, D)
  W <- ec_matrix_to_long(fb$max - fb$min, "w")$w
  det_lim <- pmax(params$estimacao$largura_determinada$votos_minimo,
                  params$estimacao$largura_determinada$fracao_linha * colSums(O)[ec_cell_grid()$origin])
  check <- W > det_lim
  if (!any(check)) check <- rep(TRUE, length(W))

  # custo previsto: avaliações da log-posterior + IPF das amostras de contagem
  th0 <- c(rep(0, d - 1L), log(50))
  t_eval <- system.time(for (k in 1:50) lpost(th0))[["elapsed"]] / 50
  P0 <- ec_dm_theta_to_P(th0[-d], pp$pos)
  t_ipf <- system.time(ec_dm_counts_for_P(P0, Oa, Da, cells, act))[["elapsed"]]
  evals <- 3 * 500 + 2 * d^2 + cfg$piloto + n_chains * cfg$iteracoes
  predicted <- t_eval * evals + t_ipf * cfg$amostras_contagem
  diag_base <- list(engine = ec_main_model_id, units_fit = nrow(Og), grouped = gu$grouped,
                    predicted_s = round(predicted, 1))
  if (predicted > budget_s) {
    return(list(status = "failed", reason = sprintf("custo previsto %.0f s acima do orçamento de %.0f s", predicted, budget_s),
                runtime_s = proc.time()[["elapsed"]] - t0, diagnostics = diag_base))
  }

  # MAP e covariância de Laplace
  lower <- c(rep(-30, d - 1L), lphi_lim[1])
  upper <- c(rep(30, d - 1L), lphi_lim[2])
  set.seed(seed)
  starts <- list(th0, c(stats::rnorm(d - 1L, 0, 1), log(50)), c(stats::rnorm(d - 1L, 0, 1), log(500)))
  opts <- lapply(starts, function(st) stats::optim(st, nlp, method = "L-BFGS-B", lower = lower, upper = upper,
                                                    control = list(maxit = 3000)))
  vals <- vapply(opts, `[[`, numeric(1), "value")
  map <- opts[[which.min(vals)]]$par
  H <- tryCatch(stats::optimHess(map, nlp), error = function(e) diag(1, d))
  sqrtm <- function(S, floor_ev = 1e-10) {
    e <- eigen((S + t(S)) / 2, symmetric = TRUE)
    e$vectors %*% diag(sqrt(pmax(e$values, floor_ev)), length(e$values))
  }
  eh <- eigen((H + t(H)) / 2, symmetric = TRUE)
  Sig0 <- eh$vectors %*% diag(1 / pmax(eh$values, 1e-2), d) %*% t(eh$vectors)
  sc <- 2.38 / sqrt(d)
  run <- function(theta, L, iters, thin, s) {
    set.seed(s)
    dm_rw_chain_cpp(theta, L, sc, as.integer(iters), as.integer(thin), Xp, Dg, Ng, pp$pos,
                    cfg$alpha_prior, lphi_lim[1], lphi_lim[2], mu, sdp)
  }

  # piloto em 8 segmentos: ajusta a escala da proposta pela aceitação (alvo 0,15–0,45) e, com aceitação
  # razoável, troca a covariância de Laplace pela covariância empírica das amostras do piloto
  L <- sqrtm(Sig0)
  th <- map
  pil <- NULL
  seg <- max(250L, as.integer(cfg$piloto / 8))
  for (q in 1:8) {
    r <- run(th, L, seg, 1, seed + 3L + q)
    acc_q <- r$acc / seg
    th <- r$theta
    if (acc_q < 0.15) {
      L <- L * 0.5
      next
    }
    if (acc_q > 0.45) L <- L * 1.6
    pil <- rbind(pil, r$kept)
    if (q >= 3 && !is.null(pil) && nrow(pil) > 5 * d) {
      S <- stats::cov(pil)
      if (all(is.finite(S)) && sum(diag(S)) > 1e-12) L <- sqrtm(S + diag(1e-10, d))
    }
  }
  pilot_acc <- acc_q
  # ajuste fino da escala global para aceitação entre 0,18 e 0,32 (passeio aleatório em ~25 dimensões)
  for (q in 1:8) {
    r <- run(th, L, 1000L, 1000L, seed + 50L + q)
    acc_q <- r$acc / 1000
    th <- r$theta
    if (acc_q > 0.32) L <- L * 1.3 else if (acc_q < 0.18) L <- L * 0.75 else break
  }
  pilot_acc <- acc_q

  # cadeias estendidas por rodadas. A cada rodada: diagnóstico barato nas contagens esperadas O_r * P[r, c]
  # (todas as amostras); quando ele passa, calcula as contagens por IPF e decide com elas (critério final).
  Orow <- colSums(Oa)
  # posição, na grade completa (ec_cell_grid), de cada célula da matriz ativa (ordem por coluna)
  gidx <- as.vector(outer(match(act$origins, EC_ORIGINS), match(act$destinations, EC_DESTINATIONS),
                          function(o, dd) (o - 1L) * length(EC_DESTINATIONS) + dd))
  expected_counts <- function(m) t(apply(m, 1, function(x) {
    full <- numeric(length(cell_names))
    full[gidx] <- as.vector(Orow * ec_dm_theta_to_P(x[-d], pp$pos))
    full
  }))
  per_chain <- max(2L, floor(cfg$amostras_contagem / n_chains))
  ipf_draws <- function(chains) lapply(chains, function(chm) {
    idx <- unique(round(seq(1, nrow(chm), length.out = min(per_chain, nrow(chm)))))
    out <- t(vapply(idx, function(j) ec_dm_counts_for_P(ec_dm_theta_to_P(chm[j, -d], pp$pos), Oa, Da, cells, act),
                    numeric(length(cell_names))))
    colnames(out) <- cell_names
    out
  })
  state <- lapply(seq_len(n_chains), function(k) {
    set.seed(seed + 1000L * k)
    st <- map + as.vector(L %*% stats::rnorm(d))
    if (!is.finite(lpost(st))) st <- map
    list(theta = st, kept = matrix(NA_real_, 0, d), acc = 0, it = 0, s = seed + 1000L * k)
  })
  rounds <- 0L
  draws <- NULL
  repeat {
    t_r <- proc.time()[["elapsed"]]
    state <- lapply(state, function(stt) {
      r <- run(stt$theta, L, cfg$iteracoes, cfg$thin, stt$s + stt$it)
      list(theta = r$theta, kept = rbind(stt$kept, r$kept), acc = stt$acc + r$acc, it = stt$it + cfg$iteracoes, s = stt$s)
    })
    t_round <- proc.time()[["elapsed"]] - t_r
    rounds <- rounds + 1L
    chains <- lapply(state, function(stt) stt$kept[(floor(nrow(stt$kept) / 2) + 1):nrow(stt$kept), , drop = FALSE])
    conv <- ec_convergence(lapply(chains, function(m) expected_counts(m)[, check, drop = FALSE]))
    last_round <- rounds > cfg$extensoes_max ||
      proc.time()[["elapsed"]] - t0 + t_round * 1.2 + 2 * t_ipf * cfg$amostras_contagem > budget_s
    if ((conv$rhat_max <= rhat_target && conv$ess_min >= ess_target) || last_round) {
      draws <- ipf_draws(chains)
      cconv <- ec_convergence(lapply(draws, function(m) m[, check, drop = FALSE]))
      if ((cconv$rhat_max <= rhat_target && cconv$ess_min >= ess_target) || last_round) break
    }
  }
  acc_rate <- sum(vapply(state, `[[`, numeric(1), "acc")) / sum(vapply(state, `[[`, numeric(1), "it"))
  if (return_chains) attr(draws, "chains") <- list(theta = chains, map = map, map_values = vals, check = check)
  list(status = "ok", draws = draws, check = check, runtime_s = proc.time()[["elapsed"]] - t0,
       diagnostics = c(diag_base, list(acceptance = round(acc_rate, 3), rounds = rounds,
                                       iterations_per_chain = state[[1]]$it, phi_map = signif(exp(map[d]), 4),
                                       pilot_acceptance = round(pilot_acc, 3),
                                       map_spread = signif(diff(range(vals)), 4))))
}

# Interface interna usada por ec_estimate_core(): ajusta e resume (média, intervalo, convergência nas contagens).
ec_fit_main <- function(O, D, params, seed) {
  fit <- ec_fit_dm_homog(O, D, params, seed)
  version <- ec_main_version()
  if (!identical(fit$status, "ok")) {
    return(list(status = "failed", reason = fit$reason, version = version, runtime_s = fit$runtime_s,
                diagnostics = fit$diagnostics))
  }
  conv <- ec_convergence(lapply(fit$draws, function(m) m[, fit$check, drop = FALSE]))
  summ <- ec_draws_to_summary(fit$draws, params$estimacao$intervalo_nivel)
  ok <- is.finite(conv$rhat_max) && conv$rhat_max <= params$estimacao$rhat_max && conv$ess_min >= params$estimacao$ess_min
  list(
    status = if (ok) "ok" else "failed",
    reason = if (ok) NULL else sprintf("sem convergência: R-hat máximo %.3f (célula %s), ESS mínimo %.0f",
                                       conv$rhat_max, conv$worst_cell, conv$ess_min),
    version = version, runtime_s = fit$runtime_s, summary = summ,
    diagnostics = c(fit$diagnostics, list(rhat_max = round(conv$rhat_max, 4), ess_min = round(conv$ess_min, 1),
                                          worst_cell = conv$worst_cell, cells_checked = sum(fit$check)))
  )
}
