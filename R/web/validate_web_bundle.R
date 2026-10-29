# Web bundle — validador (03 §6 invariantes e §15 testes de contrato). Relê tudo do disco e para na
# primeira violação. É o gate da publicação: uma release só vira latest.json se passar aqui.
#
#   validate_web_bundle(root)          latest.json + release apontada por ele
#   validate_release(release_dir, ...) só a release (usado no staging, antes de existir latest.json)

bundle_fail <- function(...) stop("validate_web_bundle: ", ..., call. = FALSE)

check_json_schema <- function(validator, path, kind) {
  ok <- validator(path, verbose = TRUE, greedy = FALSE)
  if (!isTRUE(ok)) {
    err <- attr(ok, "errors")
    msg <- if (!is.null(err) && nrow(err)) paste(err$dataPath[1], err$message[1]) else "erro desconhecido"
    bundle_fail(kind, " fora do schema em ", path, ": ", msg)
  }
  invisible(TRUE)
}

read_json_strict <- function(path) {
  if (!file.exists(path)) bundle_fail("arquivo ausente: ", path)
  jsonlite::read_json(path, simplifyVector = FALSE)
}

validate_web_bundle <- function(root, allow_demo = FALSE) {
  latest_path <- file.path(root, "latest.json")
  v <- json_validators()
  check_json_schema(v$latest, latest_path, "latest.json")
  latest <- read_json_strict(latest_path)
  if (!identical(latest$schema_version, CONTRACT_SCHEMA_VERSION)) bundle_fail("latest.schema_version ", latest$schema_version)
  if (!identical(latest$release_base, paste0("releases/", latest$release_id, "/"))) bundle_fail("latest.release_base inconsistente")
  if (!file.exists(file.path(root, latest$catalog_url))) bundle_fail("catalog_url inexistente: ", latest$catalog_url)
  validate_release(file.path(root, "releases", latest$release_id), release_id = latest$release_id,
                   allow_demo = allow_demo, validators = v)
}

validate_release <- function(release_dir, release_id, allow_demo = FALSE, validators = json_validators()) {
  v <- validators
  if (!allow_demo && (grepl("^DEMO-", release_id))) bundle_fail("release de demonstração: ", release_id)
  cat_path <- file.path(release_dir, "catalogo.json")
  check_json_schema(v$catalogo, cat_path, "catalogo.json")
  cat <- read_json_strict(cat_path)
  if (!identical(cat$schema_version, CONTRACT_SCHEMA_VERSION)) bundle_fail("catalogo.schema_version ", cat$schema_version)
  if (!identical(cat$release_id, release_id)) bundle_fail("catalogo.release_id difere de ", release_id)
  check_json_schema(v$metodo, file.path(release_dir, "metodo.json"), "metodo.json")
  met <- read_json_strict(file.path(release_dir, "metodo.json"))
  if (!identical(met$release_id, release_id)) bundle_fail("metodo.release_id difere")
  slots <- vapply(cat$election$finalists, `[[`, "", "slot")
  numbers <- as.integer(vapply(cat$election$finalists, `[[`, "", "number"))
  if (!identical(slots[order(numbers)], c("A", "B"))) bundle_fail("regra dos slots violada (menor número deve ser A)")

  sha_cache <- new.env(parent = emptyenv())
  parquet_assets <- list()
  eco_by_mun <- list()
  muns <- cat$municipalities
  ids <- vapply(muns, `[[`, "", "municipio_tse")
  if (anyDuplicated(ids)) bundle_fail("municipio_tse duplicado no catálogo")
  if (!allow_demo && "00000" %in% ids) bundle_fail("município de demonstração 00000 na release")

  for (m in muns) {
    mpath <- file.path(release_dir, m$manifest_url)
    check_json_schema(v$manifest, mpath, "manifest.json")
    man <- read_json_strict(mpath)
    where <- paste0(" (", m$municipio_tse, ")")
    if (!identical(man$release_id, release_id)) bundle_fail("manifest.release_id", where)
    if (!identical(man$schema_version, CONTRACT_SCHEMA_VERSION)) bundle_fail("manifest.schema_version", where)
    if (!identical(man$municipio_tse, m$municipio_tse) || !identical(man$uf, m$uf)) bundle_fail("manifest difere do catálogo", where)
    if (!identical(man$election_id, cat$election$election_id)) bundle_fail("manifest.election_id", where)
    expected_pub <- switch(man$validation_status, passed = "ready", partial = "partial", failed = "unavailable")
    if (!identical(m$publication_status, expected_pub)) bundle_fail("publication_status incoerente com validation_status", where)

    feat_asset <- c(summary = "summary", sections = "sections", bounds = "bounds", scenarios = "scenarios", ecological_model = "flows")
    for (f in names(feat_asset)) {
      st <- man$features[[f]]
      has <- !is.null(man$assets[[feat_asset[[f]]]])
      if (st %in% c("ready", "partial") && !has) bundle_fail("feature ", f, "=", st, " sem asset", where)
      if (!(st %in% c("ready", "partial")) && f == "ecological_model" && has) bundle_fail("asset flows sem feature pronta", where)
    }
    for (a in names(man$assets)) {
      as <- man$assets[[a]]
      abs <- file.path(release_dir, as$path)
      if (!file.exists(abs)) bundle_fail("asset inexistente: ", as$path, where)
      if (!identical(as.integer(file.size(abs)), as.integer(as$bytes))) bundle_fail("bytes divergentes em ", as$path, where)
      sha <- if (exists(as$path, envir = sha_cache, inherits = FALSE)) get(as$path, envir = sha_cache) else {
        s <- digest::digest(file = abs, algo = "sha256"); assign(as$path, s, envir = sha_cache); s
      }
      if (!identical(sha, as$sha256)) bundle_fail("sha256 divergente em ", as$path, where)
      if (identical(as$media_type, MEDIA_PARQUET)) parquet_assets[[as$path]] <- a
    }

    rpath <- file.path(release_dir, man$assets$summary$path)
    check_json_schema(v$resumo, rpath, "resumo.json")
    res <- read_json_strict(rpath)
    if (!identical(res$status, man$features$summary)) bundle_fail("resumo.status != features.summary", where)
    if (!identical(res$validation_status, man$validation_status)) bundle_fail("resumo.validation_status", where)
    if (!identical(res$location$municipio_tse, m$municipio_tse)) bundle_fail("resumo.location", where)
    fa <- res$finalists[[which(vapply(res$finalists, `[[`, "", "slot") == "A")]]
    fb <- res$finalists[[which(vapply(res$finalists, `[[`, "", "slot") == "B")]]
    r1 <- res$totals$round_1; r2 <- res$totals$round_2
    if (!is.null(r1$valid) && r1$valid != fa$round_1_votes + fb$round_1_votes + r1$other) bundle_fail("valid_1 != A + B + others", where)
    if (!is.null(r2$valid) && r2$valid != fa$round_2_votes + fb$round_2_votes) bundle_fail("valid_2 != A + B", where)
    if (!allow_demo && length(res$display_notes) && any(grepl("FICT", toupper(unlist(res$display_notes))))) bundle_fail("nota de dados fictícios", where)

    qpath <- file.path(release_dir, man$assets$quality$path)
    check_json_schema(v$qualidade, qpath, "qualidade.json")
    qua <- read_json_strict(qpath)
    if (!identical(qua$model$status, man$features$ecological_model)) bundle_fail("qualidade.model.status != features.ecological_model", where)
    if (!identical(qua$validation_status, man$validation_status)) bundle_fail("qualidade.validation_status", where)
    # 03 §6: com validation_status = failed só dados observados. (A arquitetura, I5, é mais estrita:
    # != passed. O pipeline segue I5 em run_ecological_uf; o validador aplica o contrato.)
    if (identical(man$validation_status, "failed") && man$features$ecological_model %in% c("ready", "partial"))
      bundle_fail("estimativa publicada com validation_status = failed", where)
    eco_by_mun[[m$municipio_tse]] <- man$features$ecological_model
  }

  validate_parquets(release_dir, parquet_assets, eco_by_mun, allow_demo)
  log_msg("validate_web_bundle: release ", release_id, " ok (", length(muns), " municípios, ",
          length(parquet_assets), " Parquets)")
  invisible(TRUE)
}

validate_parquets <- function(release_dir, parquet_assets, eco_by_mun, allow_demo) {
  contract <- read_marts_contract()
  asset_to_mart <- c(sections = "secoes", bounds = "limites", scenarios = "cenarios", flows = "fluxos_estimados")
  con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE))
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbExecute(con, "SET threads = 1")  # leitura em ordem física, para checar a ordenação
  for (rel in names(parquet_assets)) {
    mart <- asset_to_mart[[parquet_assets[[rel]]]]
    spec <- contract$marts[[mart]]
    src <- sprintf("read_parquet(%s)", sql_quote_path(file.path(release_dir, rel)))
    desc <- DBI::dbGetQuery(con, paste("DESCRIBE SELECT * FROM", src))
    if (!identical(desc$column_name, names(spec$columns))) bundle_fail("colunas fora do contrato em ", rel)
    want <- vapply(spec$columns, `[[`, "", "type")
    if (!identical(unname(desc$column_type), unname(want))) {
      k <- which(desc$column_type != want)[1]
      bundle_fail("tipo de ", desc$column_name[k], " = ", desc$column_type[k], " (esperado ", want[k], ") em ", rel)
    }
    for (col in names(spec$columns)) {
      cs <- spec$columns[[col]]
      if (isFALSE(cs$nullable)) {
        n <- DBI::dbGetQuery(con, sprintf("SELECT count(*) AS n FROM %s WHERE %s IS NULL", src, col))$n
        if (n > 0) bundle_fail(col, " nulo em ", rel)
      }
      if (!is.null(cs$enum)) {
        vals <- paste0("'", unlist(cs$enum), "'", collapse = ", ")
        n <- DBI::dbGetQuery(con, sprintf("SELECT count(*) AS n FROM %s WHERE %s IS NOT NULL AND %s NOT IN (%s)", src, col, col, vals))$n
        if (n > 0) bundle_fail(col, " fora do domínio em ", rel)
      }
    }
    pk <- paste(spec$primary_key, collapse = ", ")
    dup <- DBI::dbGetQuery(con, sprintf("SELECT count(*) AS n FROM (SELECT %s FROM %s GROUP BY ALL HAVING count(*) > 1)", pk, src))$n
    if (dup > 0) bundle_fail("chave primária duplicada em ", rel)
    key <- sprintf("concat_ws(chr(1), %s)", paste(spec$sort, collapse = ", "))
    unsorted <- DBI::dbGetQuery(con, sprintf(
      "SELECT count(*) AS n FROM (SELECT %s AS k, lag(%s) OVER () AS prev FROM %s) WHERE prev IS NOT NULL AND k < prev", key, key, src))$n
    if (unsorted > 0) bundle_fail("ordenação física fora do contrato em ", rel)
    if (!allow_demo) {
      n <- DBI::dbGetQuery(con, sprintf("SELECT count(*) AS n FROM %s WHERE municipio_tse = '00000'", src))$n
      if (n > 0) bundle_fail("município 00000 em ", rel)
    }
    if (mart == "secoes") {
      n <- DBI::dbGetQuery(con, sprintf(
        "SELECT count(*) AS n FROM %s WHERE least(eligible_t1, eligible_t2, turnout_t1, turnout_t2, candidate_a_t1, candidate_a_t2, candidate_b_t1, candidate_b_t2, others_t1, invalid_t1, invalid_t2) < 0
            OR (in_transition_analysis AND (exclusion_reason IS NOT NULL OR section_type <> 'regular' OR population_status NOT IN ('closed', 'net_change')))
            OR (NOT in_transition_analysis AND exclusion_reason IS NULL)", src))$n
      if (n > 0) bundle_fail("secoes com contagem negativa ou unidade de transição inválida em ", rel)
    }
    if (mart == "limites") {
      n <- DBI::dbGetQuery(con, sprintf("SELECT count(*) AS n FROM %s WHERE min_votes > max_votes OR (status = 'feasible' AND (min_votes IS NULL OR max_votes IS NULL))", src))$n
      if (n > 0) bundle_fail("limites inválidos em ", rel)
    }
    if (mart == "fluxos_estimados") {
      tol <- 1e-6
      n <- DBI::dbGetQuery(con, sprintf(
        "SELECT count(*) AS n FROM %s WHERE estimate_votes < interval_low - %g OR estimate_votes > interval_high + %g
            OR estimate_votes < bounds_min - %g OR estimate_votes > bounds_max + %g", src, tol, tol, tol, tol))$n
      if (n > 0) bundle_fail("estimativa fora do intervalo ou dos limites em ", rel)
      st <- DBI::dbGetQuery(con, sprintf("SELECT DISTINCT municipio_tse, model_status FROM %s", src))
      for (k in seq_len(nrow(st))) {
        feat <- eco_by_mun[[st$municipio_tse[k]]]
        if (!identical(feat, st$model_status[k])) bundle_fail("fluxos do município ", st$municipio_tse[k], " sem feature correspondente")
      }
    }
  }
  invisible(TRUE)
}
