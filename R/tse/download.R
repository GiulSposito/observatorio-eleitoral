# Bronze: download idempotente dos arquivos do TSE com proveniência (05 §2; invariante I1).
#
# Cada arquivo baixado ganha um sidecar `<arquivo>.provenance.json` com URL, bytes, sha256, data de
# coleta e Last-Modified do servidor. Um arquivo local com o mesmo tamanho declarado pelo servidor não é
# baixado de novo; o sha256 é sempre recalculado. Um hash diferente do registrado anteriormente para o
# mesmo arquivo é tratado como nova versão: o sidecar anterior é preservado com sufixo de timestamp.

tse_head <- function(url) {
  resp <- tryCatch(
    httr2::request(url) |>
      httr2::req_method("HEAD") |>
      httr2::req_user_agent("caderno-eleitoral (pipeline de dados abertos)") |>
      httr2::req_timeout(60) |>
      httr2::req_retry(max_tries = 3) |>
      httr2::req_perform(),
    error = function(e) NULL
  )
  if (is.null(resp)) return(list(bytes = NA_real_, last_modified = NA_character_))
  len <- httr2::resp_header(resp, "content-length")
  list(
    bytes = if (is.null(len)) NA_real_ else as.numeric(len),
    last_modified = httr2::resp_header(resp, "last-modified") %||% NA_character_
  )
}

`%||%` <- function(a, b) if (is.null(a)) b else a

file_sha256 <- function(path) digest::digest(file = path, algo = "sha256")

provenance_path <- function(path) paste0(path, ".provenance.json")

read_provenance <- function(path) {
  pp <- provenance_path(path)
  if (!file.exists(pp)) return(NULL)
  jsonlite::read_json(pp, simplifyVector = TRUE)
}

write_provenance <- function(path, prov) {
  jsonlite::write_json(prov, provenance_path(path), auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA)
}

# Baixa `url` para `dest_dir` (se necessário) e devolve uma linha de proveniência.
tse_fetch <- function(url, dest_dir, dataset, provider = "TSE") {
  dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  dest <- file.path(dest_dir, basename(url))
  remote <- tse_head(url)
  previous <- read_provenance(dest)

  have_local <- file.exists(dest) &&
    (is.na(remote$bytes) || isTRUE(file.size(dest) == remote$bytes))

  if (!have_local) {
    log_msg("baixando ", url)
    tmp <- paste0(dest, ".part")
    curl::curl_download(url, tmp, quiet = TRUE,
                        handle = curl::new_handle(useragent = "caderno-eleitoral (pipeline de dados abertos)"))
    if (!is.na(remote$bytes) && file.size(tmp) != remote$bytes) {
      unlink(tmp)
      stop("download incompleto: ", url, call. = FALSE)
    }
    file.rename(tmp, dest)
    collected_at <- utc_now()
  } else {
    collected_at <- previous$collected_at %||%
      format(file.info(dest)$mtime, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  }

  sha <- file_sha256(dest)
  if (!is.null(previous) && !identical(previous$source_sha256, sha)) {
    archived <- paste0(provenance_path(dest), ".", format(Sys.time(), "%Y%m%dT%H%M%S", tz = "UTC"))
    file.copy(provenance_path(dest), archived)
    log_msg("nova versão de ", basename(dest), " (sha256 mudou); proveniência anterior em ", basename(archived))
    if (have_local) collected_at <- format(file.info(dest)$mtime, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  }

  prov <- list(
    provider = provider,
    dataset = dataset,
    file = basename(dest),
    source_url = url,
    collected_at = collected_at,
    source_sha256 = sha,
    bytes = as.numeric(file.size(dest)),
    tse_last_modified = remote$last_modified %||% previous$tse_last_modified %||% NA_character_
  )
  write_provenance(dest, prov)
  tibble::tibble(
    provider = provider, dataset = dataset, file = prov$file, source_url = url,
    collected_at = collected_at, source_sha256 = sha, bytes = prov$bytes,
    tse_last_modified = prov$tse_last_modified, local_path = dest
  )
}

# Extrai um membro de um zip para `dest_dir`, de forma atômica e idempotente.
zip_extract_member <- function(zip_path, member, dest_dir) {
  dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  dest <- file.path(dest_dir, member)
  listing <- utils::unzip(zip_path, list = TRUE)
  row <- listing[listing$Name == member, , drop = FALSE]
  if (nrow(row) != 1L) stop("membro ", member, " não encontrado em ", basename(zip_path), call. = FALSE)
  if (file.exists(dest) && isTRUE(file.size(dest) == row$Length)) return(dest)
  tmpdir <- tempfile("unzip_", tmpdir = dest_dir)
  dir.create(tmpdir)
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)
  # unzip do sistema lida melhor com membros > 2 GB que utils::unzip
  status <- system2("unzip", c("-o", "-q", shQuote(zip_path), shQuote(member), "-d", shQuote(tmpdir)))
  if (!identical(status, 0L)) stop("falha ao extrair ", member, call. = FALSE)
  file.rename(file.path(tmpdir, member), dest)
  dest
}

# Busca todas as fontes declaradas na config da eleição.
fetch_sources <- function(cfg) {
  dest_dir <- layer_dir("bronze", cfg$election_id)
  rows <- lapply(names(cfg$fontes), function(key) {
    src <- cfg$fontes[[key]]
    out <- tse_fetch(src$url, dest_dir, dataset = src$dataset %||% key)
    out$source_key <- key
    out$member <- src$membro %||% NA_character_
    out
  })
  dplyr::bind_rows(rows)
}
