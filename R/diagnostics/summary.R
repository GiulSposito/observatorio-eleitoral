# Resumo nacional dos diagnósticos da estimação (para metodo.json -> national_summary e para a página de
# metodologia). Entrada: lista nomeada por municipio_tse de objetos `model` (03 §12), como os que
# ec_estimate() devolve e o runner grava em gold/.../eco/uf=*/models.json.

ec_diagnostics_summary <- function(models) {
  if (!length(models)) {
    return(list(municipalities = 0L, by_model_status = structure(list(), names = character()),
                md_bayes = list(fits = 0L, converged = 0L), top_reasons = list()))
  }
  status <- vapply(models, function(m) m$status %||% NA_character_, character(1))
  md <- lapply(models, function(m) {
    x <- Filter(function(mm) identical(mm$method_id, "md-bayes"), m$methods %||% list())
    if (length(x)) x[[1]] else NULL
  })
  md <- Filter(Negate(is.null), md)
  md_status <- vapply(md, function(x) x$status %||% NA_character_, character(1))
  rhat <- vapply(md, function(x) as.numeric(x$diagnostics$rhat_max %||% NA_real_), numeric(1))
  runtime <- vapply(md, function(x) as.numeric(x$runtime_s %||% NA_real_), numeric(1))
  reasons <- vapply(models, function(m) {
    r <- m$reason_unavailable %||% NA_character_
    # agrupa motivos pela parte antes dos números
    sub(":.*$", "", sub("[0-9].*$", "", r))
  }, character(1))
  reasons <- reasons[!is.na(reasons)]
  top <- sort(table(reasons), decreasing = TRUE)
  list(
    municipalities = length(models),
    by_model_status = as.list(table(status)),
    md_bayes = list(
      fits = length(md), converged = sum(md_status == "ok", na.rm = TRUE),
      rhat_median = if (any(is.finite(rhat))) round(stats::median(rhat, na.rm = TRUE), 3) else NULL,
      runtime_s_total = round(sum(runtime, na.rm = TRUE), 1)
    ),
    top_reasons = lapply(seq_along(top), function(i) list(reason = names(top)[i], municipalities = as.integer(top[[i]])))
  )
}
