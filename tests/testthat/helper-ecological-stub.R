# Stub do método ecológico (R/ecological/ é do subagente B). Usado só nos testes da camada de dados
# e em execuções locais com CADERNO_ECOLOGICAL_STUB=1. Nunca publicar uma release feita com o stub:
# a estimação fica `unavailable` e os limites de cenário são aproximados.

if (!exists("ec_bounds", mode = "function") || isTRUE(getOption("caderno.force_stub"))) {

  .stub_origins <- c("A", "B", "O", "I", "X", "N")
  .stub_destinations <- c("A", "B", "I", "X", "S")

  ec_bounds <- function(units, scenario = "base", assumptions = NULL) {
    grid <- expand.grid(origin = .stub_origins, destination = .stub_destinations, stringsAsFactors = FALSE)
    if (nrow(units) == 0L) {
      return(tibble::tibble(origin = grid$origin, destination = grid$destination,
                            min_votes = NA_real_, max_votes = NA_real_, status = "insufficient_data",
                            units_used = 0L, units_infeasible = 0L,
                            method_id = if (scenario == "base") "frechet" else "transport-lp"))
    }
    tot <- rowSums(units[, paste0("o_", .stub_origins)])
    mins <- maxs <- numeric(nrow(grid))
    for (k in seq_len(nrow(grid))) {
      r <- units[[paste0("o_", grid$origin[k])]]; c <- units[[paste0("d_", grid$destination[k])]]
      mins[k] <- sum(pmax(0, r + c - tot)); maxs[k] <- sum(pmin(r, c))
      if (scenario != "base" && paste(grid$origin[k], grid$destination[k]) %in% c("A B", "B A")) {
        mins[k] <- 0; maxs[k] <- 0
      }
    }
    tibble::tibble(origin = grid$origin, destination = grid$destination, min_votes = mins, max_votes = maxs,
                   status = "feasible", units_used = nrow(units), units_infeasible = 0L,
                   method_id = if (scenario == "base") "frechet" else "transport-lp")
  }

  ec_estimate <- function(units, params, seed, context = list()) {
    list(
      flows = NULL,
      status = "unavailable",
      model = list(
        status = "unavailable",
        reason_unavailable = "Estimação não executada neste build (stub de desenvolvimento).",
        methods = list(),
        predictive_check = NULL,
        identified_change_share = NULL,
        n_units_used = nrow(units),
        calibration_id = NULL
      )
    )
  }

  ec_calibrate <- function(margins_t1, params, seed) {
    list(report = tibble::tibble(), thresholds = list(), calibration_id = NULL,
         status = "not_run", decision = "Calibração não executada (stub de desenvolvimento).")
  }
}
