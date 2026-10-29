# Web bundle — orquestrador (03 §3, §16). Monta a release em staging, valida, promove e só então grava
# latest.json; por fim copia para web/data/ (gitignored) para o site local.
#
# Esta camada não analisa nada: seleciona, renomeia, ordena e escreve. Todo cálculo vem da gold e do
# módulo ecológico.

release_id_for <- function(election_id, when = Sys.time()) {
  paste0(election_id, "-", format(when, "%Y%m%dT%H%M%SZ", tz = "UTC"))
}

read_eco_outputs <- function(eco_paths) {
  eco_paths <- unlist(eco_paths, use.names = FALSE)
  pick <- function(name) eco_paths[basename(eco_paths) == name]
  read_all <- function(files) {
    if (!length(files)) return(tibble::tibble())
    with_db(function(con) tibble::as_tibble(DBI::dbGetQuery(con, sprintf(
      "SELECT * FROM read_parquet([%s], union_by_name = true)",
      paste(vapply(files, sql_quote_path, character(1)), collapse = ", ")))))
  }
  models <- list()
  for (f in pick("models.json")) models <- c(models, jsonlite::read_json(f, simplifyVector = FALSE))
  list(limites_files = pick("limites.parquet"), cenarios_files = pick("cenarios.parquet"),
       fluxos_files = pick("fluxos.parquet"), limites = read_all(pick("limites.parquet")),
       cenarios = read_all(pick("cenarios.parquet")), models = models)
}

national_summary <- function(totals, validation, publication, models, secoes_path, finalists) {
  eco <- vapply(totals$municipio_tse, function(m) models[[m]]$status %||% "unavailable", character(1))
  dist <- with_db(function(con) DBI::dbGetQuery(con, sprintf("
    SELECT CASE WHEN eligible_net_change IS NULL THEN 'sem_par'
                WHEN eligible_net_change = 0 THEN '0'
                WHEN abs(eligible_net_change) <= 2 THEN '1-2'
                WHEN abs(eligible_net_change) <= 10 THEN '3-10'
                ELSE '>10' END AS bucket, count(*)::INTEGER AS n
      FROM read_parquet(%s) GROUP BY 1 ORDER BY 1", sql_quote_path(secoes_path))))
  excl <- with_db(function(con) DBI::dbGetQuery(con, sprintf(
    "SELECT coalesce(exclusion_reason, 'in_transition_analysis') AS r, count(*)::INTEGER AS n FROM read_parquet(%s) GROUP BY 1",
    sql_quote_path(secoes_path))))
  fa <- finalists$number[finalists$slot == "A"]; fb <- finalists$number[finalists$slot == "B"]
  list(
    municipalities = nrow(totals),
    by_publication_status = count_list(unlist(publication)),
    by_validation_status = count_list(validation$validation_status),
    by_ecological_model = count_list(eco),
    sections_total = sum(totals$sections_total),
    units_in_transition_analysis = sum(totals$units_in_transition_analysis),
    sections_by_exclusion = as.list(stats::setNames(excl$n, excl$r)),
    eligible_net_change_distribution = lapply(seq_len(nrow(dist)), function(i) list(bucket = dist$bucket[i], n = dist$n[i])),
    finalists_totals = list(
      list(slot = "A", number = fa, round_1_votes = sum(totals$a_1), round_2_votes = sum(totals$a_2)),
      list(slot = "B", number = fb, round_1_votes = sum(totals$b_1), round_2_votes = sum(totals$b_2))
    ),
    official_totals_notes = paste(
      "V3 confere votos por candidato nos dois turnos (votacao_candidato_munzona) e aptos, comparecimento,",
      "brancos e nulos no 1º turno (detalhe_votacao_munzona). O detalhe municipal do 2º turno não estava",
      "publicado na coleta; no 2º turno, esses totais vêm só da soma das seções."),
    exterior = "Votos no exterior (UF ZZ) fora do escopo."
  )
}

build_web_bundle <- function(cfg, gold, eco_paths, calibration, sources, silver, assumptions,
                             out_root = data_root(), web_dir = file.path(repo_root(), "web", "data"),
                             generated_at = utc_now(), release_id = NULL, publish_web = TRUE) {
  params <- calibration$params
  release_id <- release_id %||% release_id_for(cfg$election_id, as.POSIXct(generated_at, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
  ctx <- list(schema_version = CONTRACT_SCHEMA_VERSION, release_id = release_id, election_id = cfg$election_id,
              generated_at = generated_at, git_sha = git_sha(), method_version = params$method_version,
              tau_rule = tau_rule_text(params), calibration_id = calibration$result$calibration_id)
  releases_dir <- file.path(out_root, "releases")
  staging <- file.path(releases_dir, paste0(release_id, ".staging"))
  final <- file.path(releases_dir, release_id)
  unlink(staging, recursive = TRUE)
  dir.create(staging, recursive = TRUE)
  log_msg("montando release ", release_id)

  finalists <- read_finalists(silver[["finalistas"]])
  totals <- read_parquet_df(gold[["totais"]])
  checks <- read_parquet_df(gold[["checks"]])
  validation <- validation_status_from_checks(checks)
  vstat <- stats::setNames(validation$validation_status, validation$municipio_tse)
  publication <- stats::setNames(as.list(ifelse(vstat == "passed", "ready", ifelse(vstat == "partial", "partial", "unavailable"))),
                                 names(vstat))
  eco <- read_eco_outputs(eco_paths)
  contract <- read_marts_contract()

  # ---- Parquets por UF
  ufs <- sort(unique(totals$uf))
  with_db(function(con) {
    DBI::dbExecute(con, sprintf("CREATE VIEW sec AS SELECT * FROM read_parquet(%s)", sql_quote_path(gold[["secoes"]])))
    for (uf in ufs) {
      dir <- file.path(staging, uf_rel_dir(cfg$election_id, uf))
      write_mart(con, "secoes", sprintf("SELECT * FROM sec WHERE uf = '%s'", uf), file.path(dir, "secoes.parquet"), contract)
      lim_f <- eco$limites_files[basename(dirname(eco$limites_files)) == paste0("uf=", uf)]
      cen_f <- eco$cenarios_files[basename(dirname(eco$cenarios_files)) == paste0("uf=", uf)]
      flu_f <- eco$fluxos_files[basename(dirname(eco$fluxos_files)) == paste0("uf=", uf)]
      if (length(lim_f)) write_mart(con, "limites", sprintf("SELECT * FROM read_parquet(%s)", sql_quote_path(lim_f)), file.path(dir, "limites.parquet"), contract)
      if (length(cen_f)) write_mart(con, "cenarios", sprintf("SELECT * FROM read_parquet(%s)", sql_quote_path(cen_f)), file.path(dir, "cenarios.parquet"), contract)
      if (length(flu_f)) write_mart(con, "fluxos_estimados", sprintf("SELECT * FROM read_parquet(%s)", sql_quote_path(flu_f)), file.path(dir, "fluxos_estimados.parquet"), contract)
    }
  })

  # ---- JSON por município
  sources_list <- sources_for_manifest(sources)
  sha_cache <- new.env(parent = emptyenv())
  lim_status <- split(eco$limites$status[eco$limites$scenario_id == "base"],
                      eco$limites$municipio_tse[eco$limites$scenario_id == "base"])
  cen_status <- split(eco$cenarios$status, eco$cenarios$municipio_tse)
  checks_by_mun <- split(checks, checks$municipio_tse)
  for (i in seq_len(nrow(totals))) {
    t <- totals[i, ]
    mun <- t$municipio_tse
    rel_dir <- municipio_rel_dir(cfg$election_id, t$uf, mun)
    model <- eco$models[[mun]] %||% list(status = "unavailable", reason_unavailable = "Sem resultado do módulo ecológico.")
    write_json_file(build_resumo(t, finalists, vstat[[mun]], ctx), file.path(staging, rel_dir, "resumo.json"))
    write_json_file(build_qualidade(t, checks_by_mun[[mun]], model, vstat[[mun]], ctx), file.path(staging, rel_dir, "qualidade.json"))

    eco_status <- model$status %||% "unavailable"
    bounds_status <- feature_from_bounds(lim_status[[mun]] %||% character())
    scen_status <- if (identical(bounds_status, "insufficient_data")) "insufficient_data"
                   else if (length(cen_status[[mun]])) "ready" else "unavailable"
    features <- list(summary = "ready", sections = "ready", bounds = bounds_status,
                     scenarios = scen_status, ecological_model = eco_status)
    uf_dir <- uf_rel_dir(cfg$election_id, t$uf)
    assets <- list(
      summary = asset_entry(staging, file.path(rel_dir, "resumo.json"), MEDIA_JSON),
      quality = asset_entry(staging, file.path(rel_dir, "qualidade.json"), MEDIA_JSON),
      sections = asset_entry(staging, file.path(uf_dir, "secoes.parquet"), MEDIA_PARQUET, sha_cache)
    )
    if (bounds_status %in% c("ready", "partial")) assets$bounds <- asset_entry(staging, file.path(uf_dir, "limites.parquet"), MEDIA_PARQUET, sha_cache)
    if (scen_status %in% c("ready", "partial")) assets$scenarios <- asset_entry(staging, file.path(uf_dir, "cenarios.parquet"), MEDIA_PARQUET, sha_cache)
    if (eco_status %in% c("ready", "partial")) assets$flows <- asset_entry(staging, file.path(uf_dir, "fluxos_estimados.parquet"), MEDIA_PARQUET, sha_cache)
    write_json_file(build_manifest(t, features, assets, sources_list, vstat[[mun]], ctx),
                    file.path(staging, rel_dir, "manifest.json"))
  }

  # ---- Arquivos da release
  write_json_file(build_catalogo(totals, publication, finalists, cfg, ctx), file.path(staging, "catalogo.json"))
  national <- national_summary(totals, validation, publication, eco$models, gold[["secoes"]], finalists)
  write_json_file(build_metodo(calibration, assumptions, national, ctx), file.path(staging, "metodo.json"), pretty = TRUE)

  # ---- Validação, promoção e ponteiro
  validate_release(staging, release_id = release_id, allow_demo = FALSE)
  unlink(final, recursive = TRUE)
  file.rename(staging, final)
  write_json_file(build_latest(ctx), file.path(out_root, "latest.json"), pretty = TRUE)
  validate_web_bundle(out_root, allow_demo = FALSE)
  log_msg("release ", release_id, " validada e publicada em ", out_root)

  if (publish_web) publish_to_web(out_root, release_id, web_dir)
  invisible(list(release_id = release_id, release_dir = final, latest = file.path(out_root, "latest.json")))
}

# Copia latest.json e a release corrente para web/data/ (bundle local do site; gitignored).
publish_to_web <- function(out_root, release_id, web_dir) {
  unlink(web_dir, recursive = TRUE)
  dir.create(file.path(web_dir, "releases"), recursive = TRUE)
  ok <- file.copy(file.path(out_root, "releases", release_id), file.path(web_dir, "releases"), recursive = TRUE)
  if (!ok) stop("falha ao copiar a release para ", web_dir, call. = FALSE)
  file.copy(file.path(out_root, "latest.json"), file.path(web_dir, "latest.json"), overwrite = TRUE)
  log_msg("bundle copiado para ", web_dir)
  invisible(web_dir)
}
