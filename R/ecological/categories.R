# Categorias da matriz de transição e utilitários de margens (05 §1, 03 §2).

EC_ORIGINS <- c("A", "B", "O", "I", "X", "N")
EC_DESTINATIONS <- c("A", "B", "I", "X", "S")
# Células de retenção: ficam fora da "massa de mudança" (05 §5.7).
EC_RETENTION <- c("A>A", "B>B", "I>I", "X>X")
# Zeros estruturais: quem entrou no cadastro do 2º turno (N) não pode ter saído dele (S).
EC_STRUCTURAL_ZEROS <- list(c("N", "S"))

ec_cell_id <- function(origin, destination) paste0(origin, ">", destination)

ec_cell_grid <- function() {
  g <- expand.grid(destination = EC_DESTINATIONS, origin = EC_ORIGINS, stringsAsFactors = FALSE)
  g[, c("origin", "destination")]
}

# Valida o tibble de unidades de R/README.md e devolve as matrizes de margens.
# O: n x 6 (origens), D: n x 5 (destinos), ambos inteiros com nomes de categoria.
ec_margins <- function(units) {
  o_cols <- paste0("o_", EC_ORIGINS)
  d_cols <- paste0("d_", EC_DESTINATIONS)
  missing <- setdiff(c(o_cols, d_cols), names(units))
  if (length(missing)) stop("ec_margins: colunas ausentes: ", paste(missing, collapse = ", "), call. = FALSE)
  O <- as.matrix(units[, o_cols, drop = FALSE])
  D <- as.matrix(units[, d_cols, drop = FALSE])
  storage.mode(O) <- "double"
  storage.mode(D) <- "double"
  colnames(O) <- EC_ORIGINS
  colnames(D) <- EC_DESTINATIONS
  if (anyNA(O) || anyNA(D)) stop("ec_margins: margens com NA", call. = FALSE)
  if (any(O < 0) || any(D < 0)) stop("ec_margins: margens negativas", call. = FALSE)
  if (any(abs(rowSums(O) - rowSums(D)) > 0)) {
    stop("ec_margins: unidades com totais de origem e destino diferentes", call. = FALSE)
  }
  list(O = O, D = D)
}

# Categorias com margem municipal positiva. As demais saem do ajuste e voltam como zeros
# determinados (diretiva do método: remover margens zero antes de ajustar).
ec_active_categories <- function(O, D) {
  list(
    origins = EC_ORIGINS[colSums(O) > 0],
    destinations = EC_DESTINATIONS[colSums(D) > 0]
  )
}

# Matriz lógica de células permitidas (TRUE = pode ter fluxo) para categorias dadas.
ec_allowed_matrix <- function(origins = EC_ORIGINS, destinations = EC_DESTINATIONS, forbidden = list()) {
  E <- matrix(TRUE, length(origins), length(destinations), dimnames = list(origins, destinations))
  for (z in c(EC_STRUCTURAL_ZEROS, forbidden)) {
    if (z[[1]] %in% origins && z[[2]] %in% destinations) E[z[[1]], z[[2]]] <- FALSE
  }
  E
}

# Converte uma matriz origem x destino (dimnames) em tibble longo na ordem de ec_cell_grid().
ec_matrix_to_long <- function(M, value_name) {
  g <- ec_cell_grid()
  v <- mapply(function(o, d) {
    if (o %in% rownames(M) && d %in% colnames(M)) M[o, d] else 0
  }, g$origin, g$destination)
  g[[value_name]] <- as.numeric(v)
  g
}
