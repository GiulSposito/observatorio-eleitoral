# Web bundle — JSON por município (03 §6, §7, §12): resumo.json, qualidade.json, manifest.json.
# Funções puras: recebem linhas/listas já preparadas e devolvem listas prontas para serializar.

EXCLUSION_REASONS <- c("not_installed", "integrity_failed", "unmatched", "transit_section",
                       "special_section", "population_change_above_tau", "possible_aggregation")

int_or_null <- function(x) if (length(x) == 0L || is.na(x)) NULL else as.integer(x)
num_or_null <- function(x) if (length(x) == 0L || is.na(x)) NULL else as.numeric(x)

round_totals <- function(t, r) {
  other <- if (r == 1L) t$other_1 else 0
  list(
    eligible = int_or_null(t[[paste0("eligible_", r)]]),
    turnout = int_or_null(t[[paste0("turnout_", r)]]),
    abstention = int_or_null(t[[paste0("abstention_", r)]]),
    valid = int_or_null(t[[paste0("valid_", r)]]),
    other = int_or_null(other),
    blank = int_or_null(t[[paste0("blank_", r)]]),
    null = int_or_null(t[[paste0("null_", r)]]),
    invalid = int_or_null(t[[paste0("invalid_", r)]])
  )
}

build_resumo <- function(t, finalists, validation_status, ctx) {
  a1 <- t$a_1; a2 <- t$a_2; b1 <- t$b_1; b2 <- t$b_2
  d_turnout <- t$turnout_2 - t$turnout_1
  d_invalid <- t$invalid_2 - t$invalid_1
  d_finalists <- (a2 - a1) + (b2 - b1)
  fa <- finalists[finalists$slot == "A", ]; fb <- finalists[finalists$slot == "B", ]
  list(
    schema_version = ctx$schema_version, release_id = ctx$release_id, election_id = ctx$election_id,
    status = "ready", validation_status = validation_status,
    location = list(municipio_tse = t$municipio_tse, uf = t$uf, name = t$name, display_name = display_name(t$name)),
    finalists = list(
      list(slot = "A", number = fa$number, name = fa$name, round_1_votes = int_or_null(a1),
           round_2_votes = int_or_null(a2), delta_votes = int_or_null(a2 - a1)),
      list(slot = "B", number = fb$number, name = fb$name, round_1_votes = int_or_null(b1),
           round_2_votes = int_or_null(b2), delta_votes = int_or_null(b2 - b1))
    ),
    totals = list(round_1 = round_totals(t, 1L), round_2 = round_totals(t, 2L)),
    accounting = list(
      other_round_1 = int_or_null(t$other_1),
      delta_turnout = int_or_null(d_turnout),
      delta_invalid = int_or_null(d_invalid),
      delta_valid = int_or_null(t$valid_2 - t$valid_1),
      delta_finalists = int_or_null(d_finalists),
      identity_residual = int_or_null(d_finalists - (t$other_1 + d_turnout - d_invalid)),
      scope = "all_sections", evidence_type = "observed"
    ),
    coverage = list(
      sections_total = as.integer(t$sections_total),
      sections_installed = as.integer(t$sections_installed),
      units_in_transition_analysis = as.integer(t$units_in_transition_analysis),
      eligible_share_used = num_or_null(round(t$eligible_share_used, 4))
    ),
    display_notes = I(character())
  )
}

normalize_model <- function(m, n_units, calibration_id) {
  methods <- m$methods
  if (is.null(methods)) methods <- list()
  methods <- lapply(methods, function(x) list(
    method_id = x$method_id, version = x$version, status = x$status,
    runtime_s = num_or_null(x$runtime_s),
    diagnostics = if (length(x$diagnostics)) x$diagnostics else empty_object()))
  pc <- m$predictive_check
  list(
    status = m$status,
    reason_unavailable = na_null(m$reason_unavailable),
    methods = I(methods),
    predictive_check = if (is.null(pc)) NULL else list(
      k_folds = as.integer(pc$k_folds), model_error = as.numeric(pc$model_error),
      null_error = as.numeric(pc$null_error), passed = isTRUE(pc$passed)),
    identified_change_share = num_or_null(m$identified_change_share),
    n_units_used = as.integer(m$n_units_used %||% n_units),
    calibration_id = na_null(m$calibration_id %||% calibration_id)
  )
}

build_qualidade <- function(t, checks, model, validation_status, ctx) {
  excl <- list()
  for (r in EXCLUSION_REASONS) {
    n <- t[[paste0("ex_", r)]]
    if (!is.na(n) && n > 0) excl[[r]] <- as.integer(n)
  }
  if (!length(excl)) excl <- empty_object()
  chk <- lapply(seq_len(nrow(checks)), function(i) {
    x <- list(id = checks$check_id[i], family = checks$family[i], passed = isTRUE(checks$passed[i]),
              scope = checks$scope[i], count_failed = as.integer(checks$count_failed[i]))
    if (checks$family[i] == "official_totals") x$explanation_code <- na_null(checks$explanation_code[i])
    x
  })
  list(
    schema_version = ctx$schema_version, release_id = ctx$release_id, election_id = ctx$election_id,
    municipio_tse = t$municipio_tse, computed_at = ctx$generated_at, pipeline_git_sha = ctx$git_sha,
    method_version = ctx$method_version, validation_status = validation_status,
    section_coverage = list(
      sections_total = as.integer(t$sections_total), sections_installed = as.integer(t$sections_installed),
      units_paired = as.integer(t$units_paired),
      units_in_transition_analysis = as.integer(t$units_in_transition_analysis),
      eligible_share_used = num_or_null(round(t$eligible_share_used, 4)),
      excluded_by_reason = excl, net_change_tolerance_rule = ctx$tau_rule
    ),
    population = list(closed = as.integer(t$pop_closed), net_change = as.integer(t$pop_net_change),
                      excluded_population = as.integer(t$pop_excluded)),
    checks = I(chk),
    model = normalize_model(model, t$units_in_transition_analysis, ctx$calibration_id)
  )
}

feature_from_bounds <- function(status_vec) {
  if (!length(status_vec)) return("unavailable")
  if (all(status_vec == "feasible")) "ready"
  else if (all(status_vec == "insufficient_data")) "insufficient_data"
  else "partial"
}

build_manifest <- function(t, features, assets, sources, validation_status, ctx) {
  list(
    schema_version = ctx$schema_version, release_id = ctx$release_id, election_id = ctx$election_id,
    municipio_tse = t$municipio_tse, uf = t$uf, name = t$name, generated_at = ctx$generated_at,
    validation_status = validation_status,
    features = features,
    assets = assets,
    sources = sources,
    pipeline_git_sha = ctx$git_sha, method_version = ctx$method_version
  )
}

sources_for_manifest <- function(prov) {
  lapply(seq_len(nrow(prov)), function(i) list(
    provider = prov$provider[i], dataset = prov$dataset[i], file = prov$file[i],
    source_url = prov$source_url[i], collected_at = prov$collected_at[i],
    source_sha256 = prov$source_sha256[i], bytes = as.integer(prov$bytes[i])))
}
