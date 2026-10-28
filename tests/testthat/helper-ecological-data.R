# Dados sintéticos para os testes do método (o código de R/ é carregado por helper-00-load.R).

# Gera unidades sintéticas com matriz de transição conhecida (processo G1, homogêneo).
ec_test_units <- function(n, P = NULL, sizes = 250:400, seed = 1, with_population = FALSE) {
  set.seed(seed)
  if (is.null(P)) {
    P <- rbind(
      A = c(0.92, 0.02, 0.02, 0.04, 0), B = c(0.02, 0.92, 0.02, 0.04, 0),
      O = c(0.35, 0.35, 0.12, 0.18, 0), I = c(0.20, 0.20, 0.40, 0.20, 0),
      X = c(0.08, 0.08, 0.02, 0.82, 0), N = c(0.30, 0.30, 0.05, 0.35, 0)
    )
    colnames(P) <- EC_DESTINATIONS
  }
  rows <- lapply(seq_len(n), function(k) {
    e1 <- sample(sizes, 1)
    comp <- c(0.35, 0.33, 0.07, 0.05, 0.20) * stats::runif(5, 0.5, 1.5)
    o <- as.vector(stats::rmultinom(1, e1, comp))
    names(o) <- c("A", "B", "O", "I", "X")
    dnet <- if (with_population) sample(c(0, 0, 0, 1, -1, 2), 1) else 0
    o <- c(o, N = max(0, dnet))
    flows <- t(sapply(EC_ORIGINS, function(i) as.vector(stats::rmultinom(1, o[[i]], P[i, ]))))
    colnames(flows) <- EC_DESTINATIONS
    if (dnet < 0) {
      # saída líquida: |D| eleitores do 1º turno deixam o cadastro (vão para S)
      for (q in seq_len(-dnet)) {
        cand <- which(flows[, "X"] > 0 & rownames(flows) != "N")
        r <- if (length(cand)) cand[1] else which(rowSums(flows) > 0)[1]
        cc <- if (flows[r, "X"] > 0) "X" else names(which(flows[r, ] > 0))[1]
        flows[r, cc] <- flows[r, cc] - 1
        flows[r, "S"] <- flows[r, "S"] + 1
      }
    }
    d <- colSums(flows)
    list(o = o, d = d, flows = flows)
  })
  units <- tibble::tibble(
    election_id = "2026-presidente", uf = "GO", municipio_tse = "00000",
    comparison_unit_id = sprintf("00000-0001-%04d", seq_len(n)),
    population_status = "closed"
  )
  for (k in EC_ORIGINS) units[[paste0("o_", k)]] <- vapply(rows, function(r) as.integer(r$o[[k]]), integer(1))
  for (k in EC_DESTINATIONS) units[[paste0("d_", k)]] <- vapply(rows, function(r) as.integer(r$d[[k]]), integer(1))
  units$population_status <- ifelse(units$o_N > 0 | units$d_S > 0, "net_change", "closed")
  truth <- Reduce(`+`, lapply(rows, `[[`, "flows"))
  attr(units, "truth") <- truth
  units
}

ec_test_params <- function() {
  p <- yaml::read_yaml(file.path(testthat::test_path(), "..", "..", "config", "metodo.yml"))
  p
}
