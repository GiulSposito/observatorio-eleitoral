# Web bundle — escrita de JSON e descrição de assets (path relativo à base da release, sha256, bytes).

to_json_text <- function(x, pretty = FALSE) {
  jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", na = "null", digits = NA, pretty = pretty)
}

write_json_file <- function(x, path, pretty = FALSE) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  con <- file(path, open = "w", encoding = "UTF-8")
  on.exit(close(con), add = TRUE)
  writeLines(to_json_text(x, pretty = pretty), con, useBytes = TRUE)
  path
}

empty_object <- function() structure(list(), names = character())

# NULL para NA escalar (o contrato usa null, nunca "NA" nem 0).
na_null <- function(x) if (length(x) == 0L || (length(x) == 1L && is.na(x))) NULL else x

asset_entry <- function(release_dir, rel_path, media_type, sha_cache = NULL) {
  abs <- file.path(release_dir, rel_path)
  sha <- if (!is.null(sha_cache) && exists(rel_path, envir = sha_cache, inherits = FALSE)) {
    get(rel_path, envir = sha_cache)
  } else {
    s <- digest::digest(file = abs, algo = "sha256")
    if (!is.null(sha_cache)) assign(rel_path, s, envir = sha_cache)
    s
  }
  list(path = rel_path, media_type = media_type, sha256 = sha, bytes = as.integer(file.size(abs)))
}

MEDIA_JSON <- "application/json"
MEDIA_PARQUET <- "application/vnd.apache.parquet"
