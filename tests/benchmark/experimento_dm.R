# EXPERIMENTO (não faz parte do método publicado): motor bayesiano alternativo ao md-bayes do eiPack,
# usado só no benchmark para embasar a proposta do relatório (tests/benchmark/RESULTS.md).
#
# Modelo: taxas homogêneas no município, verossimilhança Dirichlet-multinomial nas margens de destino
# de cada unidade (sobredispersão phi limitada a 1e5), prior Dirichlet(alpha) nas linhas; MAP por
# L-BFGS-B, piloto de passeio aleatório para a covariância da proposta e 4 cadeias de passeio
# aleatório estendidas até R-hat/ESS ou orçamento; contagens municipais por ajuste proporcional
# iterativo (IPF) das tabelas de cada unidade às duas margens, por amostra da posterior.
#
# Uso: source() depois de carregar R/ecological/; chamar ec_fit_md_dm(O, D, exec, seed, budget_s)
# com exec = params$execucao acrescido de cadeias e de dm (ver tests/benchmark/benchmark.R).

# ---------------------------------------------------------------- motor DM (alternativa)
EC_DM_LOGPHI_RANGE <- c(log(0.5), log(1e5))  # acima de 1e5 a DM é praticamente multinomial e o lgamma perde precisão

ec_dm_loglik <- function(theta, Xp, Dm, N, cells, act_R, act_C, alpha = 2) {
  # theta: parâmetros livres das linhas (softmax com a última célula livre como referência) + log(phi)
  lphi <- theta[length(theta)]
  if (lphi < EC_DM_LOGPHI_RANGE[1] || lphi > EC_DM_LOGPHI_RANGE[2]) return(-Inf)
  R <- length(act_R)
  C <- length(act_C)
  P <- ec_dm_theta_to_P(theta, cells, R, C)
  phi <- exp(lphi)
  Q <- Xp %*% P
  Q <- pmax(Q, 1e-12)
  a <- phi * Q
  ll <- sum(lgamma(phi) - lgamma(N + phi)) + sum(lgamma(Dm + a) - lgamma(a))
  # prior: Dirichlet(alpha - 1 + 1) em cada linha: densidade prod(p^(alpha-1)) vezes o jacobiano do softmax
  # (prod p) = prod(p^alpha) no espaço theta; log(phi) ~ N(log 50, 3)
  lp <- alpha * sum(log(pmax(P[cells], 1e-300))) + stats::dnorm(lphi, log(50), 3, log = TRUE)
  ll + lp
}

ec_dm_theta_to_P <- function(theta, cells, R, C) {
  # cells: matriz lógica R x C das células livres; em cada linha a última livre é a referência (0)
  E <- matrix(-Inf, R, C)
  pos <- 1L
  for (r in seq_len(R)) {
    free <- which(cells[r, ])
    E[r, free[length(free)]] <- 0
    if (length(free) > 1) {
      idx <- free[-length(free)]
      E[r, idx] <- theta[pos:(pos + length(idx) - 1L)]
      pos <- pos + length(idx)
    }
  }
  E <- E - apply(E, 1, max)
  P <- exp(E)
  P / rowSums(P)
}

# Ajuste proporcional iterativo vetorizado: tabelas n x R x C semente, margens de linha e coluna.
ec_ipf <- function(seed_arr, rows, cols, iters = 30, tol = 1e-6) {
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

ec_fit_md_dm <- function(O, D, exec, seed, budget_s) {
  act <- ec_active_categories(O, D)
  t0 <- proc.time()[["elapsed"]]
  Oa <- O[, act$origins, drop = FALSE]
  Da <- D[, act$destinations, drop = FALSE]
  R <- ncol(Oa)
  C <- ncol(Da)
  N <- rowSums(Oa)
  Xp <- Oa / N
  cells <- ec_allowed_matrix(act$origins, act$destinations)
  n_par <- sum(pmax(rowSums(cells) - 1, 0)) + 1
  cfg <- exec$dm
  n_chains <- exec$cadeias
  lpost <- function(th) ec_dm_loglik(th, Xp, Da, N, cells, act$origins, act$destinations, alpha = cfg$alpha_prior)
  nlp <- function(th) { v <- lpost(th); if (is.finite(v)) -v else 1e300 }
  # piloto de custo
  th0 <- c(rep(0, n_par - 1), log(50))
  tp <- system.time(for (k in 1:20) lpost(th0))[["elapsed"]] / 20
  n_keep_ipf <- cfg$amostras_contagem
  ipf_cost <- tp * 8 * n_keep_ipf / 10
  predicted <- tp * (n_chains * cfg$iteracoes + cfg$piloto + 3 * 400 + 2 * n_par^2) + ipf_cost
  if (predicted > budget_s) {
    return(list(status = "failed", reason = sprintf("custo previsto %.0f s acima do orçamento de %.0f s", predicted, budget_s),
                runtime_s = proc.time()[["elapsed"]] - t0, predicted_s = predicted))
  }
  # MAP (L-BFGS-B com log(phi) limitado) a partir de pontos iniciais distintos, e covariância de Laplace
  lower <- c(rep(-30, n_par - 1), EC_DM_LOGPHI_RANGE[1])
  upper <- c(rep(30, n_par - 1), EC_DM_LOGPHI_RANGE[2])
  set.seed(seed)
  starts <- list(th0, c(stats::rnorm(n_par - 1, 0, 1), log(50)), c(stats::rnorm(n_par - 1, 0, 1), log(500)))
  opts <- lapply(starts, function(st) stats::optim(st, nlp, method = "L-BFGS-B", lower = lower, upper = upper,
                                                    control = list(maxit = 3000)))
  vals <- vapply(opts, `[[`, numeric(1), "value")
  map <- opts[[which.min(vals)]]$par
  map_spread <- diff(range(vals))
  H <- tryCatch(stats::optimHess(map, nlp), error = function(e) diag(1, n_par))
  ev <- eigen((H + t(H)) / 2, symmetric = TRUE)
  ev$values <- pmax(ev$values, 1e-2)  # direções planas: variância de proposta limitada a 100
  Sig0 <- ev$vectors %*% diag(1 / ev$values, n_par) %*% t(ev$vectors)
  Sig0 <- (Sig0 + t(Sig0)) / 2
  sqrtm <- function(S) {
    e <- eigen((S + t(S)) / 2, symmetric = TRUE)
    e$vectors %*% diag(sqrt(pmax(e$values, 1e-10)), length(e$values))
  }
  sc <- 2.38 / sqrt(n_par)
  # 1) piloto: passeio aleatório a partir do MAP; a covariância empírica vira a proposta das cadeias
  set.seed(seed + 3L)
  L <- sqrtm(Sig0)
  th <- map
  lp <- lpost(th)
  pilot <- matrix(NA_real_, cfg$piloto, n_par)
  for (it in seq_len(cfg$piloto)) {
    prop <- th + sc * as.vector(L %*% stats::rnorm(n_par))
    lpp <- lpost(prop)
    if (is.finite(lpp) && log(stats::runif(1)) < lpp - lp) { th <- prop; lp <- lpp }
    pilot[it, ] <- th
    if (it %in% floor(cfg$piloto * c(0.25, 0.5))) L <- sqrtm(stats::cov(pilot[seq_len(it), , drop = FALSE]) + diag(1e-8, n_par))
  }
  L <- sqrtm(stats::cov(pilot[floor(cfg$piloto / 2):cfg$piloto, , drop = FALSE]) + diag(1e-8, n_par))
  # 2) cadeias de passeio aleatório com proposta fixa; estendidas enquanto não convergem e houver orçamento
  P_of <- function(m) t(apply(m, 1, function(x) ec_dm_theta_to_P(x, cells, R, C)[cells]))
  state <- lapply(seq_len(n_chains), function(k) {
    set.seed(seed + 1000L * k)
    st <- map + as.vector(L %*% stats::rnorm(n_par))
    if (!is.finite(lpost(st))) st <- map
    list(th = st, lp = lpost(st), kept = matrix(NA_real_, 0, n_par), acc = 0, it = 0, seed = seed + 1000L * k)
  })
  advance <- function(stt, iters) {
    set.seed(stt$seed + stt$it)
    th <- stt$th
    lp <- stt$lp
    kept <- matrix(NA_real_, floor(iters / cfg$thin), n_par)
    acc <- 0
    for (it in seq_len(iters)) {
      prop <- th + sc * as.vector(L %*% stats::rnorm(n_par))
      lpp <- lpost(prop)
      if (is.finite(lpp) && log(stats::runif(1)) < lpp - lp) { th <- prop; lp <- lpp; acc <- acc + 1 }
      if (it %% cfg$thin == 0) kept[it / cfg$thin, ] <- th
    }
    list(th = th, lp = lp, kept = rbind(stt$kept, kept), acc = stt$acc + acc, it = stt$it + iters, seed = stt$seed)
  }
  rounds <- 0
  t_round <- NA_real_
  repeat {
    t_r <- proc.time()[["elapsed"]]
    state <- lapply(state, advance, iters = cfg$iteracoes)
    t_round <- proc.time()[["elapsed"]] - t_r
    rounds <- rounds + 1
    # descarta a primeira metade de cada cadeia como aquecimento
    chains <- lapply(state, function(stt) stt$kept[(floor(nrow(stt$kept) / 2) + 1):nrow(stt$kept), , drop = FALSE])
    conv <- ec_convergence(lapply(chains, P_of))
    ok <- conv$rhat_max <= cfg$rhat_alvo && conv$ess_min >= cfg$ess_alvo
    elapsed <- proc.time()[["elapsed"]] - t0
    if (ok || rounds >= cfg$extensoes_max + 1 || elapsed + t_round * 1.2 > budget_s) break
  }
  acc_rate <- sum(vapply(state, `[[`, numeric(1), "acc")) / sum(vapply(state, `[[`, numeric(1), "it"))
  # parâmetros P por amostra -> contagens municipais via IPF por unidade (subamostra de draws)
  all_theta <- do.call(rbind, chains)
  chain_of <- rep(seq_len(n_chains), vapply(chains, nrow, integer(1)))
  # mesma quantidade de amostras por cadeia, igualmente espaçadas, para os diagnósticos nas contagens
  per_chain <- max(2L, floor(n_keep_ipf / n_chains))
  pick <- unlist(lapply(seq_len(n_chains), function(k) {
    idx <- which(chain_of == k)
    idx[unique(round(seq(1, length(idx), length.out = min(per_chain, length(idx)))))]
  }))
  cell_names <- ec_cell_id(ec_cell_grid()$origin, ec_cell_grid()$destination)
  counts <- matrix(0, length(pick), length(cell_names), dimnames = list(NULL, cell_names))
  for (s in seq_along(pick)) {
    P <- ec_dm_theta_to_P(all_theta[pick[s], ], cells, R, C)
    seed_arr <- array(0, c(nrow(Oa), R, C))
    for (r in seq_len(R)) seed_arr[, r, ] <- outer(Oa[, r], P[r, ])
    tab <- ec_ipf(seed_arr + 1e-9 * array(rep(cells, each = nrow(Oa)), dim(seed_arr)), Oa, Da)
    M <- apply(tab, c(2, 3), sum)
    dimnames(M) <- list(act$origins, act$destinations)
    long <- ec_matrix_to_long(M, "v")
    counts[s, ] <- long$v
  }
  draws <- split.data.frame(counts, chain_of[pick])
  # diagnóstico de convergência nos parâmetros de taxa (P) de todas as amostras salvas
  p_draws <- lapply(chains, function(chm) {
    t(apply(chm, 1, function(th) as.vector(ec_dm_theta_to_P(th, cells, R, C)[cells])))
  })
  list(status = "ok", draws = draws, conv_draws = p_draws, runtime_s = proc.time()[["elapsed"]] - t0, predicted_s = predicted,
       map_spread = map_spread, phi_map = exp(map[n_par]), acc_rate = acc_rate, rounds = rounds,
       iterations_per_chain = state[[1]]$it)
}

