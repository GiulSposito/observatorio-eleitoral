# Limites determinísticos (05 §4).
#
# - Cenário "base": limites de Fréchet (Duncan-Davis) em fórmula fechada por unidade, somados.
# - Cenários com células zeradas (ex.: "sem-troca-finalistas"): solução exata do problema de
#   transporte por unidade via condições de Gale–Hall (vetorizada em todas as unidades). É o mesmo
#   ótimo do LP, sem chamar um solver por célula; ec_bounds_lp_unit() é o oráculo nos testes.
# - Restrições que não sejam "célula = 0" caem no LP por unidade (lpSolve), mais lento.

ec_bounds_method_version <- "bounds-1.0.0"

# Limites de Fréchet por unidade, somados. Devolve matrizes 6 x 5 (min e max).
ec_frechet_sum <- function(O, D) {
  tot <- rowSums(O)
  lo <- matrix(0, ncol(O), ncol(D), dimnames = list(colnames(O), colnames(D)))
  hi <- lo
  for (i in seq_len(ncol(O))) {
    for (j in seq_len(ncol(D))) {
      r <- O[, i]
      c <- D[, j]
      lo[i, j] <- sum(pmax(0, r + c - tot))
      hi[i, j] <- sum(pmin(r, c))
    }
  }
  # N -> S é zero estrutural; com pop-liquida-minima nenhuma unidade tem N e S ao mesmo tempo,
  # então Fréchet já dá zero ali. Forçamos para não depender disso.
  lo["N", "S"] <- 0
  hi["N", "S"] <- 0
  list(min = lo, max = hi)
}

# Limites exatos por unidade com células proibidas (Gale–Hall).
# E: matriz lógica 6 x 5 de células permitidas. Devolve min/max por unidade (arrays n x 6 x 5)
# e a viabilidade de cada unidade.
ec_bounds_gale <- function(O, D, E) {
  n <- nrow(O)
  R <- ncol(O)
  C <- ncol(D)
  subsets <- as.matrix(expand.grid(rep(list(c(FALSE, TRUE)), R)))[-1, , drop = FALSE]  # sem o vazio
  rS <- O %*% t(subsets * 1)  # n x (2^R - 1)
  nbr <- function(Eused) {
    # vizinhança de cada subconjunto de linhas: colunas alcançáveis
    (subsets * 1) %*% (Eused * 1) > 0
  }
  feasible_with <- function(Eused, Rm, Dm) {
    Nb <- nbr(Eused)
    rs <- Rm %*% t(subsets * 1)
    cs <- Dm %*% t(Nb * 1)
    rowSums(rs > cs + 1e-9) == 0
  }
  unit_feasible <- feasible_with(E, O, D)

  lo <- array(0, c(n, R, C), dimnames = list(NULL, colnames(O), colnames(D)))
  hi <- array(0, c(n, R, C), dimnames = list(NULL, colnames(O), colnames(D)))
  for (i in seq_len(R)) {
    for (j in seq_len(C)) {
      if (!E[i, j]) next
      E2 <- E
      E2[i, j] <- FALSE
      Nb <- nbr(E2)
      cN <- D %*% t(Nb * 1)                       # n x subsets
      inS <- subsets[, i]                         # i pertence a S?
      jN <- Nb[, j]                               # j pertence a N(S) sem a célula (i, j)?
      a <- as.integer(jN) - as.integer(inS)
      tlo <- rep(0, n)
      thi <- pmin(O[, i], D[, j])
      ok <- rep(TRUE, n)
      for (s in seq_len(nrow(subsets))) {
        slack <- cN[, s] - rS[, s]
        if (a[s] == 1L) {
          thi <- pmin(thi, slack)
        } else if (a[s] == -1L) {
          tlo <- pmax(tlo, -slack)
        } else {
          ok <- ok & slack >= -1e-9
        }
      }
      ok <- ok & tlo <= thi + 1e-9 & unit_feasible
      lo[, i, j] <- ifelse(ok, tlo, NA_real_)
      hi[, i, j] <- ifelse(ok, thi, NA_real_)
    }
  }
  list(min = lo, max = hi, feasible = unit_feasible)
}

# Oráculo: LP por unidade com lpSolve (min e max de cada célula). constraints é uma lista de
# list(origin, destination, value) com igualdades. Usado em testes e para restrições não nulas.
ec_bounds_lp_unit <- function(o, d, constraints = list()) {
  R <- length(o)
  C <- length(d)
  nv <- R * C
  idx <- function(i, j) (j - 1) * R + i
  A <- rbind(
    t(sapply(seq_len(R), function(i) { v <- numeric(nv); v[idx(i, seq_len(C))] <- 1; v })),
    t(sapply(seq_len(C), function(j) { v <- numeric(nv); v[idx(seq_len(R), j)] <- 1; v }))
  )
  rhs <- c(o, d)
  dirs <- rep("=", R + C)
  for (z in constraints) {
    i <- match(z$origin, names(o))
    j <- match(z$destination, names(d))
    if (is.na(i) || is.na(j)) next
    v <- numeric(nv)
    v[idx(i, j)] <- 1
    A <- rbind(A, v)
    rhs <- c(rhs, z$value)
    dirs <- c(dirs, "=")
  }
  lo <- hi <- matrix(NA_real_, R, C, dimnames = list(names(o), names(d)))
  for (i in seq_len(R)) for (j in seq_len(C)) {
    obj <- numeric(nv)
    obj[idx(i, j)] <- 1
    rmin <- lpSolve::lp("min", obj, A, dirs, rhs)
    if (rmin$status != 0) return(list(min = lo, max = hi, feasible = FALSE))
    rmax <- lpSolve::lp("max", obj, A, dirs, rhs)
    lo[i, j] <- rmin$objval
    hi[i, j] <- rmax$objval
  }
  list(min = lo, max = hi, feasible = TRUE)
}

ec_scenario_constraints <- function(scenario, assumptions) {
  if (identical(scenario, "base")) return(list(constraints = list(), assumption_id = "pop-liquida-minima"))
  sc <- Filter(function(s) identical(s$id, scenario), assumptions$scenarios)
  if (!length(sc)) stop("ec_bounds: cenário desconhecido: ", scenario, call. = FALSE)
  list(constraints = sc[[1]]$constraints %||% list(), assumption_id = sc[[1]]$assumption_id)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

# Interface pública (R/README.md).
ec_bounds <- function(units, scenario = "base", assumptions = NULL) {
  grid <- ec_cell_grid()
  empty <- function(status, n_used = 0L, n_inf = 0L) {
    grid$min_votes <- NA_real_
    grid$max_votes <- NA_real_
    grid$status <- status
    grid$units_used <- as.integer(n_used)
    grid$units_infeasible <- as.integer(n_inf)
    grid$method_id <- if (identical(scenario, "base")) "frechet" else "transport-lp"
    tibble::as_tibble(grid)
  }
  if (is.null(units) || nrow(units) == 0) return(empty("insufficient_data"))
  m <- ec_margins(units)
  O <- m$O
  D <- m$D

  if (identical(scenario, "base")) {
    fb <- ec_frechet_sum(O, D)
    grid$min_votes <- ec_matrix_to_long(fb$min, "v")$v
    grid$max_votes <- ec_matrix_to_long(fb$max, "v")$v
    grid$status <- "feasible"
    grid$units_used <- nrow(O)
    grid$units_infeasible <- 0L
    grid$method_id <- "frechet"
    return(tibble::as_tibble(grid))
  }

  sc <- ec_scenario_constraints(scenario, assumptions)
  cons <- sc$constraints
  zero_only <- all(vapply(cons, function(z) isTRUE(all.equal(z$value, 0)), logical(1)))
  if (zero_only) {
    forbidden <- lapply(cons, function(z) c(z$origin, z$destination))
    E <- ec_allowed_matrix(forbidden = forbidden)
    g <- ec_bounds_gale(O, D, E)
    n_inf <- sum(!g$feasible)
    if (n_inf > 0) return(empty("infeasible", nrow(O), n_inf))
    lo <- apply(g$min, c(2, 3), sum)
    hi <- apply(g$max, c(2, 3), sum)
    lo[!E] <- 0
    hi[!E] <- 0
  } else {
    lo <- hi <- matrix(0, ncol(O), ncol(D), dimnames = list(colnames(O), colnames(D)))
    n_inf <- 0L
    for (k in seq_len(nrow(O))) {
      r <- ec_bounds_lp_unit(O[k, ], D[k, ], c(cons, lapply(EC_STRUCTURAL_ZEROS, function(z) list(origin = z[1], destination = z[2], value = 0))))
      if (!r$feasible) { n_inf <- n_inf + 1L; next }
      lo <- lo + r$min
      hi <- hi + r$max
    }
    if (n_inf > 0) return(empty("infeasible", nrow(O), n_inf))
  }
  grid$min_votes <- ec_matrix_to_long(lo, "v")$v
  grid$max_votes <- ec_matrix_to_long(hi, "v")$v
  grid$status <- "feasible"
  grid$units_used <- nrow(O)
  grid$units_infeasible <- 0L
  grid$method_id <- "transport-lp"
  tibble::as_tibble(grid)
}
