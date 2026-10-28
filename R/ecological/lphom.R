# Programação linear sob homogeneidade (lphom; Pavía e Romero) e checagem preditiva (05 §5.5).

ec_lphom_version <- function() paste0("lphom-", as.character(utils::packageVersion("lphom")))

# O LP do lphom é denso e estoura a memória com milhares de unidades. Acima de max_units, as unidades
# são somadas em grupos de composição parecida (ordenadas pela participação de A e de abstenção no 1º
# turno); sob homogeneidade, somar unidades preserva a relação linear que o lphom ajusta.
ec_group_units <- function(O, D, max_units) {
  n <- nrow(O)
  if (n <= max_units) return(list(O = O, D = D, grouped = FALSE))
  tot <- rowSums(O)
  ord <- order(round(O[, "A"] / pmax(tot, 1), 2), O[, "X"] / pmax(tot, 1))
  g <- integer(n)
  g[ord] <- ceiling(seq_len(n) * max_units / n)
  list(O = rowsum(O, g), D = rowsum(D, g), grouped = TRUE)
}

# Ajusta lphom só nas categorias ativas. Devolve a matriz de proporções completa (6 x 5, linhas
# somando 1 nas origens ativas) e a matriz de contagens municipais.
ec_fit_lphom <- function(O, D, max_units = 800L) {
  counts_rows <- colSums(O)
  gu <- ec_group_units(O, D, max_units)
  O <- gu$O
  D <- gu$D
  act <- ec_active_categories(O, D)
  t0 <- proc.time()[["elapsed"]]
  Oa <- O[, act$origins, drop = FALSE]
  Da <- D[, act$destinations, drop = FALSE]
  sz <- list()
  for (z in EC_STRUCTURAL_ZEROS) {
    i <- match(z[1], act$origins)
    j <- match(z[2], act$destinations)
    if (!is.na(i) && !is.na(j)) sz[[length(sz) + 1]] <- c(i, j)
  }
  if (length(act$origins) < 2 || length(act$destinations) < 2) {
    # problema degenerado: um único destino/origem determina tudo
    P <- matrix(0, length(act$origins), length(act$destinations), dimnames = list(act$origins, act$destinations))
    P[] <- rep(colSums(Da) / sum(Da), each = nrow(P))
  } else {
    fit <- tryCatch(
      suppressMessages(lphom::lphom(as.data.frame(Oa), as.data.frame(Da), new_and_exit_voters = "simultaneous",
                                    structural_zeros = if (length(sz)) sz else NULL, verbose = FALSE)),
      error = function(e) e
    )
    if (inherits(fit, "error")) {
      return(list(status = "failed", reason = conditionMessage(fit), runtime_s = proc.time()[["elapsed"]] - t0))
    }
    P <- as.matrix(fit$VTM)[seq_along(act$origins), seq_along(act$destinations), drop = FALSE]
    dimnames(P) <- list(act$origins, act$destinations)
    P[P < 0] <- 0
    P <- P / rowSums(P)
  }
  full <- matrix(0, length(EC_ORIGINS), length(EC_DESTINATIONS), dimnames = list(EC_ORIGINS, EC_DESTINATIONS))
  full[act$origins, act$destinations] <- P
  counts <- counts_rows[EC_ORIGINS] * full
  list(status = "ok", P = full, counts = counts, runtime_s = proc.time()[["elapsed"]] - t0, grouped = gu$grouped)
}

# Validação cruzada em k grupos de unidades: ajusta lphom sem o grupo e prevê a distribuição
# do 2º turno de cada unidade deixada de fora a partir da composição do 1º turno.
# Erro = índice de dissimilaridade ponderado por aptos; nulo = distribuição municipal do 2º turno
# nas unidades de treino.
ec_predictive_check <- function(O, D, k_folds, seed) {
  n <- nrow(O)
  set.seed(seed)
  fold <- sample(rep(seq_len(k_folds), length.out = n))
  err_model <- 0
  err_null <- 0
  for (f in seq_len(k_folds)) {
    tr <- fold != f
    te <- !tr
    fit <- ec_fit_lphom(O[tr, , drop = FALSE], D[tr, , drop = FALSE])
    share_null <- colSums(D[tr, , drop = FALSE]) / sum(D[tr, , drop = FALSE])
    P <- if (identical(fit$status, "ok")) fit$P else matrix(share_null, length(EC_ORIGINS), length(EC_DESTINATIONS), byrow = TRUE)
    # origens sem dados no treino: prevê com a distribuição nula
    empty <- rowSums(P) == 0
    if (any(empty)) P[empty, ] <- matrix(share_null, sum(empty), length(share_null), byrow = TRUE)
    pred <- O[te, , drop = FALSE] %*% P
    nul <- outer(rowSums(O[te, , drop = FALSE]), share_null)
    err_model <- err_model + sum(abs(pred - D[te, , drop = FALSE]))
    err_null <- err_null + sum(abs(nul - D[te, , drop = FALSE]))
  }
  total <- 2 * sum(O)
  list(k_folds = as.integer(k_folds), model_error = err_model / total, null_error = err_null / total)
}
