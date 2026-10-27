# Configuração, caminhos e utilitários gerais do pipeline.
#
# Raiz de dados: `data/` do repositório ou o caminho de CADERNO_DATA_DIR (R/README.md, "Dados locais").
# Todas as funções que tocam o disco recebem caminhos montados aqui, para que os testes possam
# apontar a raiz para um diretório temporário.

repo_root <- function() {
  root <- getOption("caderno.repo_root")
  if (!is.null(root)) return(root)
  normalizePath(".", mustWork = TRUE)
}

data_root <- function() {
  env <- Sys.getenv("CADERNO_DATA_DIR", unset = "")
  if (nzchar(env)) return(normalizePath(env, mustWork = FALSE))
  file.path(repo_root(), "data")
}

layer_dir <- function(layer, election_id, ..., create = TRUE) {
  path <- file.path(data_root(), layer, election_id, ...)
  if (create) dir.create(path, recursive = TRUE, showWarnings = FALSE)
  path
}

read_election_config <- function(election_id) {
  path <- file.path(repo_root(), "config", "eleicoes", paste0(election_id, ".yml"))
  if (!file.exists(path)) stop("config de eleição não encontrada: ", path, call. = FALSE)
  cfg <- yaml::read_yaml(path)
  checkmate::assert_string(cfg$election_id)
  checkmate::assert_true(identical(cfg$election_id, election_id))
  checkmate::assert_list(cfg$fontes, min.len = 2)
  checkmate::assert_choice(cfg$slot_rule, "lowest_ballot_number")
  cfg
}

read_method_params <- function() {
  yaml::read_yaml(file.path(repo_root(), "config", "metodo.yml"))
}

read_assumptions <- function() {
  yaml::read_yaml(file.path(repo_root(), "config", "assumptions.yml"))
}

# Tolerância de mudança líquida de aptos (05 §3.2): max(tau_minimo, floor(tau_fracao * E1)).
population_tau <- function(e1, params = read_method_params()) {
  p <- params$populacao
  pmax(as.integer(p$tau_minimo_eleitores), as.integer(floor(p$tau_fracao * e1)))
}

tau_rule_text <- function(params = read_method_params()) {
  p <- params$populacao
  sprintf("max(%d, %s%% de E1)", as.integer(p$tau_minimo_eleitores),
          format(100 * p$tau_fracao, decimal.mark = ","))
}

# Seed determinística por (release, município, método) — R/README.md.
seed_for <- function(release_id, municipio_tse, method_id) {
  h <- digest::digest(paste(release_id, municipio_tse, method_id, sep = "|"), algo = "xxhash32")
  strtoi(substr(h, 1, 7), base = 16L)
}

utc_now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

git_sha <- function() {
  sha <- tryCatch(
    system2("git", c("-C", shQuote(repo_root()), "rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE),
    error = function(e) character()
  )
  if (length(sha) == 1L && grepl("^[0-9a-f]{40}$", sha)) sha else "0000000000000000000000000000000000000000"
}

log_msg <- function(...) {
  message(format(Sys.time(), "[%H:%M:%S] "), ...)
}

# Nome em caixa mista (03 §5): preposições em minúsculas.
display_name <- function(x) {
  vapply(x, function(one) {
    words <- strsplit(tolower(one), " ", fixed = TRUE)[[1]]
    keep_lower <- c("de", "da", "do", "das", "dos", "e", "d'")
    out <- ifelse(
      words %in% keep_lower, words,
      paste0(toupper(substr(words, 1, 1)), substr(words, 2, nchar(words)))
    )
    # Hífens e apóstrofos: "pau-d'arco" -> "Pau-d'Arco"
    out <- gsub("-([a-zà-ú])", "-\\U\\1", out, perl = TRUE)
    out <- gsub("^D'([a-zà-ú])", "D'\\U\\1", out, perl = TRUE)
    paste(out, collapse = " ")
  }, character(1), USE.NAMES = FALSE)
}

# Caminhos determinísticos das camadas (os targets de arquivo só registram dependência; as funções
# recebem estes vetores nomeados).
silver_paths <- function(cfg) {
  d <- layer_dir("silver", cfg$election_id)
  c(secao_turno = file.path(d, "secao_turno.parquet"), finalistas = file.path(d, "finalistas.json"),
    municipios = file.path(d, "municipios.parquet"))
}

gold_paths <- function(cfg) {
  d <- layer_dir("gold", cfg$election_id)
  c(secoes = file.path(d, "secoes_mart.parquet"), checks = file.path(d, "checks.parquet"),
    totais = file.path(d, "municipal_totals.parquet"), units = file.path(d, "units.parquet"))
}

extracted_paths <- function(cfg) {
  d <- file.path(layer_dir("bronze", cfg$election_id), "extracted")
  stats::setNames(file.path(d, vapply(cfg$fontes, `[[`, "", "membro")), names(cfg$fontes))
}
