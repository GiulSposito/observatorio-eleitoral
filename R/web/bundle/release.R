# Web bundle — arquivos da release: catalogo.json (03 §5), metodo.json (03 §13) e latest.json (03 §4).

build_catalogo <- function(totals, publication_status, finalists, cfg, ctx) {
  rows <- lapply(seq_len(nrow(totals)), function(i) {
    t <- totals[i, ]
    list(
      municipio_tse = t$municipio_tse, municipio_ibge = NULL, name = t$name,
      display_name = display_name(t$name), uf = t$uf, n_sections = as.integer(t$sections_total),
      manifest_url = municipio_rel_dir(ctx$election_id, t$uf, t$municipio_tse, "manifest.json"),
      publication_status = publication_status[[t$municipio_tse]]
    )
  })
  list(
    schema_version = ctx$schema_version, release_id = ctx$release_id, generated_at = ctx$generated_at,
    election = list(
      election_id = cfg$election_id, year = as.integer(cfg$year), office = cfg$office, label = cfg$label,
      rounds = lapply(cfg$rounds, function(r) list(round = as.integer(r$round), date = r$date)),
      slot_rule = cfg$slot_rule,
      finalists = lapply(seq_len(nrow(finalists)), function(i)
        list(slot = finalists$slot[i], number = finalists$number[i], name = finalists$name[i]))
    ),
    municipalities = rows
  )
}

METHOD_CATEGORIES <- list(
  list(code = "A", round = 1L, label_ptbr = "Finalista A"),
  list(code = "B", round = 1L, label_ptbr = "Finalista B"),
  list(code = "O", round = 1L, label_ptbr = "Demais candidatos"),
  list(code = "I", round = 1L, label_ptbr = "Brancos e nulos"),
  list(code = "X", round = 1L, label_ptbr = "Abstenção"),
  list(code = "N", round = 1L, label_ptbr = "Entrada líquida de aptos"),
  list(code = "A", round = 2L, label_ptbr = "Finalista A"),
  list(code = "B", round = 2L, label_ptbr = "Finalista B"),
  list(code = "I", round = 2L, label_ptbr = "Brancos e nulos"),
  list(code = "X", round = 2L, label_ptbr = "Abstenção"),
  list(code = "S", round = 2L, label_ptbr = "Saída líquida de aptos")
)

count_list <- function(x) {
  tab <- table(x)
  if (!length(tab)) return(empty_object())
  as.list(stats::setNames(as.integer(tab), names(tab)))
}

build_metodo <- function(calibration, assumptions, national, ctx) {
  res <- calibration$result
  report <- res$report
  results <- if (is.null(report) || !nrow(report)) list() else
    lapply(seq_len(nrow(report)), function(i) as.list(report[i, , drop = FALSE]))
  list(
    schema_version = ctx$schema_version, release_id = ctx$release_id,
    method_version = ctx$method_version,
    parameters = calibration$params,
    categories = METHOD_CATEGORIES,
    assumptions = lapply(assumptions$assumptions, function(a)
      list(id = a$id, label_ptbr = a$label_ptbr, description_ptbr = a$description_ptbr)),
    scenarios = lapply(assumptions$scenarios, function(s)
      list(id = s$id, assumption_id = s$assumption_id, label_ptbr = s$label_ptbr, description_ptbr = s$description_ptbr)),
    calibration = list(
      calibration_id = na_null(res$calibration_id),
      status = res$status %||% "not_run",
      target_coverage = as.numeric(calibration$params$calibracao$cobertura_alvo %||% 0.9),
      results = I(results),
      decision = res$decision %||% ""
    ),
    national_summary = national
  )
}

build_latest <- function(ctx) {
  base <- file.path("releases", ctx$release_id)
  list(
    schema_version = ctx$schema_version, release_id = ctx$release_id, published_at = ctx$generated_at,
    release_base = paste0(base, "/"), catalog_url = file.path(base, "catalogo.json"),
    pipeline_git_sha = ctx$git_sha, method_version = ctx$method_version
  )
}

municipio_rel_dir <- function(election_id, uf, municipio_tse, file = NULL) {
  p <- file.path(election_id, "municipios", uf, municipio_tse)
  if (is.null(file)) p else file.path(p, file)
}

uf_rel_dir <- function(election_id, uf, file = NULL) {
  p <- file.path(election_id, paste0("uf=", uf))
  if (is.null(file)) p else file.path(p, file)
}
