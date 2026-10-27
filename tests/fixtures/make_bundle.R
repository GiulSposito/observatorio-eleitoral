# Gera o bundle sintético DEMO-001 em tests/fixtures/bundle/ (contrato 1.2.0).
#
# DADOS FICTÍCIOS. Municípios, candidatos e números são inventados para desenvolver e testar o site.
# Os limites e as estimativas daqui NÃO são o cálculo do método (R/ecological/): servem só para
# exercitar a interface com valores coerentes com o contrato. Nunca entram em release.
#
# Uso, a partir da raiz do repositório:  Rscript tests/fixtures/make_bundle.R

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(jsonlite)
  library(DBI)
})

set.seed(20261027)

out_root <- "tests/fixtures/bundle"
release_id <- "DEMO-001"
election_id <- "2026-presidente"
schema_version <- "1.2.0"
method_version <- "metodo-1.0.0"
generated_at <- "2026-10-27T18:00:00Z"
git_sha <- "DEMO"
release_base <- file.path("releases", release_id)

origins <- c("A", "B", "O", "I", "X", "N")
destinations <- c("A", "B", "I", "X", "S")

municipios <- tibble::tribble(
  ~municipio_tse, ~uf,  ~name,              ~n_sections, ~model_status,        ~validation_status,
  "00000",        "GO", "CIDADE MODELO",    40,          "ready",              "passed",
  "00001",        "MG", "VALE SERENO",      26,          "partial",            "passed",
  "00002",        "GO", "VALE SERENO",       8,          "insufficient_data",  "passed",
  "00003",        "SC", "PORTO DAS ÁGUAS",  30,          "partial",            "partial"
)

display_name <- function(x) {
  words <- strsplit(tolower(x), " ", fixed = TRUE)[[1]]
  keep_lower <- c("de", "da", "do", "das", "dos", "e")
  words <- ifelse(words %in% keep_lower, words,
                  paste0(toupper(substr(words, 1, 1)), substr(words, 2, nchar(words))))
  paste(words, collapse = " ")
}

# Matriz de transição verdadeira (só da fixture): linhas = origem, colunas = destino.
P <- rbind(
  A = c(0.93, 0.02, 0.02, 0.03, 0),
  B = c(0.03, 0.91, 0.02, 0.04, 0),
  O = c(0.38, 0.40, 0.12, 0.10, 0),
  I = c(0.22, 0.18, 0.45, 0.15, 0),
  X = c(0.10, 0.08, 0.02, 0.80, 0),
  N = c(0.30, 0.30, 0.05, 0.35, 0)
)
colnames(P) <- destinations

draw_sections <- function(m) {
  n <- m$n_sections
  zonas <- sprintf("%04d", sample(c(11, 27, 103), n, replace = TRUE))
  e1 <- sample(220:420, n, replace = TRUE)
  d <- sample(c(0, 0, 0, 0, 0, 0, 1, -1, 2), n, replace = TRUE)
  shares <- t(replicate(n, {
    s <- rgamma(5, shape = c(9, 8, 1.6, 1.2, 4.5))
    s / sum(s)
  }))
  rows <- map_dfr(seq_len(n), function(k) {
    o <- as.integer(stats::rmultinom(1, e1[k], shares[k, ]))
    names(o) <- c("A", "B", "O", "I", "X")
    o_n <- max(0L, d[k])
    o_all <- c(o, N = o_n)
    flows <- t(sapply(names(o_all), function(i) as.integer(stats::rmultinom(1, o_all[[i]], P[i, ]))))
    colnames(flows) <- destinations
    d_cols <- colSums(flows)
    # saída líquida: tira |D| da abstenção do 2º turno quando D < 0 (fixture simples)
    d_s <- max(0L, -d[k])
    d_cols["X"] <- d_cols["X"] - d_s
    d_cols["S"] <- d_s
    blank1 <- as.integer(round(o[["I"]] * 0.4)); blank2 <- as.integer(round(d_cols[["I"]] * 0.4))
    tibble(
      zona = zonas[k], secao = sprintf("%04d", k * 3 + 1),
      eligible_t1 = e1[k], eligible_t2 = e1[k] + d[k],
      candidate_a_t1 = o[["A"]], candidate_b_t1 = o[["B"]], others_t1 = o[["O"]],
      blank_t1 = blank1, null_t1 = o[["I"]] - blank1, invalid_t1 = o[["I"]],
      abstention_t1 = o[["X"]],
      candidate_a_t2 = d_cols[["A"]], candidate_b_t2 = d_cols[["B"]],
      blank_t2 = blank2, null_t2 = d_cols[["I"]] - blank2, invalid_t2 = d_cols[["I"]],
      abstention_t2 = d_cols[["X"]],
      o_N = o_n, d_S = d_s
    )
  })
  rows |>
    mutate(
      turnout_t1 = eligible_t1 - abstention_t1,
      turnout_t2 = eligible_t2 - abstention_t2
    )
}

tau <- function(e1) pmax(2L, as.integer(floor(0.01 * e1)))

build_secoes <- function(m) {
  s <- draw_sections(m) |>
    mutate(
      election_id = election_id, uf = m$uf, municipio_tse = m$municipio_tse,
      comparison_unit_id = paste(municipio_tse, zona, secao, sep = "-"),
      unit_type = "section", comparison_status = "matched",
      section_type = "regular",
      polling_place_id = sprintf("%04d", 1000 + as.integer(zona)),
      polling_place_name = paste("ESCOLA DEMONSTRATIVA", as.integer(zona)),
      location_changed = FALSE, integrity_status = "passed", installed = TRUE
    )
  if (m$municipio_tse == "00003") {
    # exercita exclusões: uma seção de trânsito, uma acima de tau e uma não instalada
    s$section_type[2] <- "transit"
    s$eligible_t2[3] <- s$eligible_t1[3] + 40L
    s$abstention_t2[3] <- s$abstention_t2[3] + 40L
    s$installed[4] <- FALSE
  }
  s <- s |>
    mutate(
      eligible_net_change = eligible_t2 - eligible_t1,
      population_status = case_when(
        eligible_net_change == 0 ~ "closed",
        abs(eligible_net_change) <= tau(eligible_t1) ~ "net_change",
        TRUE ~ "excluded_population"
      ),
      exclusion_reason = case_when(
        !installed ~ "not_installed",
        section_type == "transit" ~ "transit_section",
        population_status == "excluded_population" ~ "population_change_above_tau",
        TRUE ~ NA_character_
      ),
      in_transition_analysis = is.na(exclusion_reason),
      delta_turnout = turnout_t2 - turnout_t1, delta_a = candidate_a_t2 - candidate_a_t1,
      delta_b = candidate_b_t2 - candidate_b_t1, delta_invalid = invalid_t2 - invalid_t1
    )
  count_cols <- c("eligible_t1", "eligible_t2", "turnout_t1", "turnout_t2", "abstention_t1", "abstention_t2",
                  "candidate_a_t1", "candidate_a_t2", "candidate_b_t1", "candidate_b_t2", "others_t1",
                  "blank_t1", "null_t1", "blank_t2", "null_t2", "invalid_t1", "invalid_t2",
                  "delta_turnout", "delta_a", "delta_b", "delta_invalid", "eligible_net_change")
  s[!s$installed, count_cols] <- NA
  s$population_status[!s$installed] <- NA
  s
}

units_of <- function(s) {
  s |>
    filter(in_transition_analysis) |>
    transmute(o_A = candidate_a_t1, o_B = candidate_b_t1, o_O = others_t1, o_I = invalid_t1,
              o_X = abstention_t1, o_N = o_N,
              d_A = candidate_a_t2, d_B = candidate_b_t2, d_I = invalid_t2, d_X = abstention_t2, d_S = d_S)
}

frechet <- function(u) {
  grid <- expand_grid(origin = origins, destination = destinations)
  tot <- rowSums(u[, paste0("o_", origins)])
  pmap_dfr(grid, function(origin, destination) {
    r <- u[[paste0("o_", origin)]]; c <- u[[paste0("d_", destination)]]
    tibble(origin = origin, destination = destination,
           min_votes = sum(pmax(0, r + c - tot)), max_votes = sum(pmin(r, c)))
  })
}

write_parquet <- function(df, path, order_by, select = "*") {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  con <- dbConnect(duckdb::duckdb())
  on.exit(dbDisconnect(con, shutdown = TRUE))
  duckdb::duckdb_register(con, "df", df)
  dbExecute(con, sprintf("COPY (SELECT %s FROM df ORDER BY %s) TO '%s' (FORMAT parquet, COMPRESSION zstd, ROW_GROUP_SIZE 2048)", select,
                         paste(order_by, collapse = ", "), path))
}

write_json_file <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(toJSON(x, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), path, useBytes = TRUE)
}

asset <- function(rel, media_type) {
  path <- file.path(out_root, release_base, rel)
  list(path = rel, media_type = media_type, sha256 = digest::digest(file = path, algo = "sha256"),
       bytes = file.size(path))
}

# ---------------------------------------------------------------- geração
unlink(out_root, recursive = TRUE)
secoes <- municipios |> split(seq_len(nrow(municipios))) |> map(build_secoes)
names(secoes) <- municipios$municipio_tse

limites <- list(); cenarios <- list(); fluxos <- list()
for (k in seq_len(nrow(municipios))) {
  m <- municipios[k, ]
  s <- secoes[[m$municipio_tse]]
  u <- units_of(s)
  e1_all <- sum(s$eligible_t1, na.rm = TRUE)
  share_used <- sum(s$eligible_t1[s$in_transition_analysis]) / e1_all
  base <- frechet(u) |>
    mutate(scenario_id = "base", assumption_id = "pop-liquida-minima", status = "feasible",
           units_used = nrow(u), units_infeasible = 0L, eligible_share_used = share_used,
           method_id = "frechet", method_version = method_version)
  sem_troca <- base |>
    mutate(scenario_id = "sem-troca-finalistas", assumption_id = "pop-liquida-minima+sem-troca-finalistas",
           method_id = "transport-lp",
           min_votes = if_else(paste(origin, destination) %in% c("A B", "B A"), 0, min_votes),
           max_votes = if_else(paste(origin, destination) %in% c("A B", "B A"), 0, max_votes))
  lim <- bind_rows(base, sem_troca) |>
    mutate(election_id = election_id, uf = m$uf, municipio_tse = m$municipio_tse,
           min_votes = as.numeric(min_votes), max_votes = as.numeric(max_votes))
  limites[[k]] <- lim
  cenarios[[k]] <- lim |> distinct(election_id, uf, municipio_tse, scenario_id, assumption_id, status,
                                   units_used, units_infeasible)
  if (m$model_status %in% c("ready", "partial")) {
    o_tot <- colSums(u[, paste0("o_", origins)])
    est <- expand_grid(origin = origins, destination = destinations) |>
      mutate(estimate_votes = map2_dbl(origin, destination, ~ o_tot[[paste0("o_", .x)]] * P[.x, .y])) |>
      left_join(base |> select(origin, destination, bounds_min = min_votes, bounds_max = max_votes),
                by = c("origin", "destination")) |>
      mutate(
        bounds_min = as.numeric(bounds_min), bounds_max = as.numeric(bounds_max),
        w = bounds_max - bounds_min,
        spread = if (m$model_status == "ready") 0.12 else 0.45,
        half = pmax(1, w * spread / 2),
        interval_low = pmax(bounds_min, estimate_votes - half),
        interval_high = pmin(bounds_max, estimate_votes + half),
        estimate_votes = pmin(pmax(estimate_votes, interval_low), interval_high),
        method_range_low = pmax(bounds_min, estimate_votes - half * 0.8),
        method_range_high = pmin(bounds_max, estimate_votes + half * 0.8),
        identification_ratio = if_else(w > 0, (interval_high - interval_low) / w, NA_real_),
        identification_class = case_when(
          w <= pmax(5, 0.01 * bounds_max) ~ "determined",
          identification_ratio <= 0.25 ~ "estimated",
          identification_ratio <= 0.50 ~ "weak",
          TRUE ~ "not_identified"
        ),
        election_id = election_id, uf = m$uf, municipio_tse = m$municipio_tse,
        model_id = "md-bayes", model_version = "eiPack-0.2-2", assumption_id = "homogeneidade-municipal+pop-liquida-minima",
        estimate_statistic = "posterior_mean", interval_type = "credible_interval", interval_level = 0.95,
        model_status = m$model_status
      ) |>
      select(-w, -spread, -half)
    fluxos[[k]] <- est
  }
}

secoes_all <- bind_rows(secoes) |> select(-o_N, -d_S)
limites_all <- bind_rows(limites)
cenarios_all <- bind_rows(cenarios)
fluxos_all <- bind_rows(fluxos)

sec_cols <- c("election_id", "uf", "municipio_tse", "zona", "secao", "comparison_unit_id", "unit_type",
              "comparison_status", "section_type", "polling_place_id", "polling_place_name", "location_changed",
              "integrity_status", "installed", "eligible_t1", "eligible_t2", "turnout_t1", "turnout_t2",
              "abstention_t1", "abstention_t2", "candidate_a_t1", "candidate_a_t2", "candidate_b_t1",
              "candidate_b_t2", "others_t1", "blank_t1", "null_t1", "blank_t2", "null_t2", "invalid_t1",
              "invalid_t2", "delta_turnout", "delta_a", "delta_b", "delta_invalid", "eligible_net_change",
              "population_status", "in_transition_analysis", "exclusion_reason")
int_cols <- sec_cols[grepl("_t[12]$|^delta_|eligible_net_change", sec_cols)]
secoes_all <- secoes_all[, sec_cols] |> mutate(across(all_of(int_cols), as.integer))

lim_cols <- c("election_id", "uf", "municipio_tse", "scenario_id", "assumption_id", "origin", "destination",
              "min_votes", "max_votes", "status", "units_used", "units_infeasible", "eligible_share_used",
              "method_id", "method_version")
limites_all <- limites_all[, lim_cols] |>
  mutate(min_votes = as.integer(round(min_votes)), max_votes = as.integer(round(max_votes)),
         units_used = as.integer(units_used), units_infeasible = as.integer(units_infeasible))
cenarios_all <- cenarios_all |> mutate(units_used = as.integer(units_used), units_infeasible = as.integer(units_infeasible))
flu_cols <- c("election_id", "uf", "municipio_tse", "origin", "destination", "model_id", "model_version",
              "assumption_id", "estimate_votes", "estimate_statistic", "interval_low", "interval_high",
              "interval_type", "interval_level", "method_range_low", "method_range_high", "bounds_min",
              "bounds_max", "identification_ratio", "identification_class", "model_status")
fluxos_all <- fluxos_all[, flu_cols]

for (uf in unique(municipios$uf)) {
  dir_uf <- file.path(out_root, release_base, election_id, paste0("uf=", uf))
  write_parquet(filter(secoes_all, .data$uf == !!uf), file.path(dir_uf, "secoes.parquet"), c("municipio_tse", "zona", "secao"))
  write_parquet(filter(limites_all, .data$uf == !!uf), file.path(dir_uf, "limites.parquet"), c("municipio_tse", "scenario_id", "origin", "destination"),
                select = "* REPLACE (CAST(min_votes AS BIGINT) AS min_votes, CAST(max_votes AS BIGINT) AS max_votes)")
  write_parquet(filter(cenarios_all, .data$uf == !!uf), file.path(dir_uf, "cenarios.parquet"), c("municipio_tse", "scenario_id"))
  write_parquet(filter(fluxos_all, .data$uf == !!uf), file.path(dir_uf, "fluxos_estimados.parquet"), c("municipio_tse", "origin", "destination"))
}

finalists <- list(
  list(slot = "A", number = "13", name = "CANDIDATO A (DEMONSTRAÇÃO)"),
  list(slot = "B", number = "22", name = "CANDIDATO B (DEMONSTRAÇÃO)")
)

catalog_rows <- list()
for (k in seq_len(nrow(municipios))) {
  m <- municipios[k, ]
  s <- secoes[[m$municipio_tse]]
  inst <- s[s$installed, ]
  tot <- function(t) {
    sfx <- paste0("_t", t)
    list(
      eligible = sum(inst[[paste0("eligible", sfx)]]), turnout = sum(inst[[paste0("turnout", sfx)]]),
      abstention = sum(inst[[paste0("abstention", sfx)]]),
      valid = sum(inst[[paste0("candidate_a", sfx)]]) + sum(inst[[paste0("candidate_b", sfx)]]) +
        (if (t == 1) sum(inst$others_t1) else 0L),
      other = if (t == 1) sum(inst$others_t1) else 0L,
      blank = sum(inst[[paste0("blank", sfx)]]), null = sum(inst[[paste0("null", sfx)]]),
      invalid = sum(inst[[paste0("invalid", sfx)]])
    )
  }
  t1 <- tot(1); t2 <- tot(2)
  a1 <- sum(inst$candidate_a_t1); a2 <- sum(inst$candidate_a_t2)
  b1 <- sum(inst$candidate_b_t1); b2 <- sum(inst$candidate_b_t2)
  used <- s[s$in_transition_analysis, ]
  share_used <- sum(used$eligible_t1) / sum(inst$eligible_t1)
  muni_dir <- file.path(election_id, "municipios", m$uf, m$municipio_tse)
  status_summary <- "ready"

  resumo <- list(
    schema_version = schema_version, release_id = release_id, election_id = election_id,
    status = status_summary, validation_status = m$validation_status,
    location = list(municipio_tse = m$municipio_tse, uf = m$uf, name = m$name, display_name = display_name(m$name)),
    finalists = list(
      c(finalists[[1]], list(round_1_votes = a1, round_2_votes = a2, delta_votes = a2 - a1)),
      c(finalists[[2]], list(round_1_votes = b1, round_2_votes = b2, delta_votes = b2 - b1))
    ),
    totals = list(round_1 = t1, round_2 = t2),
    accounting = list(
      other_round_1 = t1$other, delta_turnout = t2$turnout - t1$turnout, delta_invalid = t2$invalid - t1$invalid,
      delta_valid = t2$valid - t1$valid, delta_finalists = (a2 - a1) + (b2 - b1),
      identity_residual = ((a2 - a1) + (b2 - b1)) - (t1$other + (t2$turnout - t1$turnout) - (t2$invalid - t1$invalid)),
      scope = "all_sections", evidence_type = "observed"
    ),
    coverage = list(sections_total = nrow(s), sections_installed = nrow(inst),
                    units_in_transition_analysis = nrow(used), eligible_share_used = round(share_used, 4)),
    display_notes = list("DADOS FICTÍCIOS. Bundle de demonstração para desenvolvimento; não é resultado eleitoral.")
  )
  write_json_file(resumo, file.path(out_root, release_base, muni_dir, "resumo.json"))

  excl <- table(s$exclusion_reason)
  qualidade <- list(
    schema_version = schema_version, release_id = release_id, election_id = election_id,
    municipio_tse = m$municipio_tse, computed_at = generated_at, pipeline_git_sha = git_sha,
    method_version = method_version, validation_status = m$validation_status,
    section_coverage = list(
      sections_total = nrow(s), sections_installed = nrow(inst), units_paired = nrow(s),
      units_in_transition_analysis = nrow(used), eligible_share_used = round(share_used, 4),
      excluded_by_reason = if (length(excl)) as.list(setNames(as.integer(excl), names(excl))) else structure(list(), names = character()),
      net_change_tolerance_rule = "max(2, 1% de E1)"
    ),
    population = list(
      closed = sum(s$population_status == "closed", na.rm = TRUE),
      net_change = sum(s$population_status == "net_change", na.rm = TRUE),
      excluded_population = sum(s$population_status == "excluded_population", na.rm = TRUE)
    ),
    checks = list(
      list(id = "integrity.turnout_equals_votes", family = "integrity", passed = TRUE, scope = "sections", count_failed = 0L),
      list(id = "integrity.eligible_equals_turnout_plus_abstention", family = "integrity", passed = TRUE, scope = "sections", count_failed = 0L),
      list(id = "harmonization.pairing_one_to_one", family = "harmonization", passed = TRUE, scope = "units", count_failed = 0L),
      list(id = "official_totals.round_1", family = "official_totals", passed = TRUE, scope = "municipality", count_failed = 0L, explanation_code = NULL),
      list(id = "official_totals.round_2", family = "official_totals", passed = m$validation_status == "passed", scope = "municipality",
           count_failed = if (m$validation_status == "passed") 0L else 1L,
           explanation_code = if (m$validation_status == "passed") NULL else "demo_explained_divergence")
    ),
    model = list(
      status = m$model_status,
      reason_unavailable = if (m$model_status == "insufficient_data") "Menos de 15 seções comparáveis." else NULL,
      methods = if (m$model_status %in% c("ready", "partial")) list(
        list(method_id = "md-bayes", version = "eiPack-0.2-2", status = "ok", runtime_s = 3.2, diagnostics = list(rhat_max = 1.004, ess_min = 900)),
        list(method_id = "lphom", version = "lphom-0.3.5-7", status = "ok", runtime_s = 0.2, diagnostics = setNames(list(), character()))
      ) else list(),
      predictive_check = if (m$model_status %in% c("ready", "partial"))
        list(k_folds = 5L, model_error = 0.058, null_error = if (m$model_status == "ready") 0.081 else 0.061,
             passed = m$model_status == "ready") else NULL,
      identified_change_share = if (m$model_status == "ready") 0.86 else if (m$model_status == "partial") 0.41 else NULL,
      n_units_used = nrow(used),
      calibration_id = "cal-DEMO-001"
    )
  )
  write_json_file(qualidade, file.path(out_root, release_base, muni_dir, "qualidade.json"))

  uf_dir <- file.path(election_id, paste0("uf=", m$uf))
  pq <- "application/vnd.apache.parquet"
  assets <- list(
    summary = asset(file.path(muni_dir, "resumo.json"), "application/json"),
    quality = asset(file.path(muni_dir, "qualidade.json"), "application/json"),
    sections = asset(file.path(uf_dir, "secoes.parquet"), pq),
    bounds = asset(file.path(uf_dir, "limites.parquet"), pq),
    scenarios = asset(file.path(uf_dir, "cenarios.parquet"), pq)
  )
  if (m$model_status %in% c("ready", "partial")) assets$flows <- asset(file.path(uf_dir, "fluxos_estimados.parquet"), pq)
  manifest <- list(
    schema_version = schema_version, release_id = release_id, election_id = election_id,
    municipio_tse = m$municipio_tse, uf = m$uf, name = m$name, generated_at = generated_at,
    validation_status = m$validation_status,
    features = list(summary = "ready", sections = "ready", bounds = "ready", scenarios = "ready",
                    ecological_model = m$model_status),
    assets = assets,
    sources = list(list(provider = "FIXTURE", dataset = "Bundle sintético de demonstração", file = "make_bundle.R",
                        source_url = NULL, collected_at = NULL, source_sha256 = NULL, bytes = NULL)),
    pipeline_git_sha = git_sha, method_version = method_version
  )
  write_json_file(manifest, file.path(out_root, release_base, muni_dir, "manifest.json"))

  catalog_rows[[k]] <- list(
    municipio_tse = m$municipio_tse, municipio_ibge = NULL, name = m$name, display_name = display_name(m$name),
    uf = m$uf, n_sections = nrow(s), manifest_url = file.path(muni_dir, "manifest.json"),
    publication_status = if (m$validation_status == "passed") "ready" else "partial"
  )
}

catalogo <- list(
  schema_version = schema_version, release_id = release_id, generated_at = generated_at,
  election = list(
    election_id = election_id, year = 2026L, office = "presidente",
    label = "Presidência · 2026 · 1º × 2º turno (DEMONSTRAÇÃO)",
    rounds = list(list(round = 1L, date = "2026-10-04"), list(round = 2L, date = "2026-10-25")),
    slot_rule = "lowest_ballot_number", finalists = finalists
  ),
  municipalities = catalog_rows
)
write_json_file(catalogo, file.path(out_root, release_base, "catalogo.json"))

assumptions <- yaml::read_yaml("config/assumptions.yml")
params <- yaml::read_yaml("config/metodo.yml")
metodo <- list(
  schema_version = schema_version, release_id = release_id, method_version = method_version,
  parameters = params,
  categories = list(
    list(code = "A", round = 1L, label_ptbr = "Finalista A"), list(code = "B", round = 1L, label_ptbr = "Finalista B"),
    list(code = "O", round = 1L, label_ptbr = "Demais candidatos"), list(code = "I", round = 1L, label_ptbr = "Brancos e nulos"),
    list(code = "X", round = 1L, label_ptbr = "Abstenção"), list(code = "N", round = 1L, label_ptbr = "Entrada líquida de aptos"),
    list(code = "A", round = 2L, label_ptbr = "Finalista A"), list(code = "B", round = 2L, label_ptbr = "Finalista B"),
    list(code = "I", round = 2L, label_ptbr = "Brancos e nulos"), list(code = "X", round = 2L, label_ptbr = "Abstenção"),
    list(code = "S", round = 2L, label_ptbr = "Saída líquida de aptos")
  ),
  assumptions = map(assumptions$assumptions, ~ list(id = .x$id, label_ptbr = .x$label_ptbr, description_ptbr = .x$description_ptbr)),
  scenarios = map(assumptions$scenarios, ~ list(id = .x$id, assumption_id = .x$assumption_id,
                                                label_ptbr = .x$label_ptbr, description_ptbr = .x$description_ptbr)),
  calibration = list(calibration_id = "cal-DEMO-001", status = "not_run", target_coverage = 0.90,
                     results = list(), decision = "Fixture: calibração não executada."),
  national_summary = list(municipalities = nrow(municipios), note = "DADOS FICTÍCIOS")
)
write_json_file(metodo, file.path(out_root, release_base, "metodo.json"))

latest <- list(
  schema_version = schema_version, release_id = release_id, published_at = generated_at,
  release_base = paste0(release_base, "/"), catalog_url = file.path(release_base, "catalogo.json"),
  pipeline_git_sha = git_sha, method_version = method_version
)
write_json_file(latest, file.path(out_root, "latest.json"))
cat("Bundle DEMO-001 gerado em", out_root, "\n")
