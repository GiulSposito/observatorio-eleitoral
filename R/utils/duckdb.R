# Conexões DuckDB do pipeline. Cada uso abre e fecha a própria conexão em memória, com diretório
# temporário próprio (evita o diretório compartilhado ~/.duckdb entre workers do crew).

db_open <- function(threads = NULL) {
  con <- DBI::dbConnect(duckdb::duckdb(dbdir = ":memory:"))
  tmp <- file.path(tempdir(), "duckdb_tmp")
  dir.create(tmp, showWarnings = FALSE, recursive = TRUE)
  DBI::dbExecute(con, sprintf("SET temp_directory = '%s'", tmp))
  DBI::dbExecute(con, "SET preserve_insertion_order = false")
  if (!is.null(threads)) DBI::dbExecute(con, sprintf("SET threads = %d", as.integer(threads)))
  con
}

db_close <- function(con) {
  try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE)
  invisible(NULL)
}

with_db <- function(fun, threads = NULL) {
  con <- db_open(threads)
  on.exit(db_close(con), add = TRUE)
  fun(con)
}

sql_quote_path <- function(path) {
  paste0("'", gsub("'", "''", normalizePath(path, mustWork = FALSE), fixed = TRUE), "'")
}

read_parquet_df <- function(path, where = NULL) {
  with_db(function(con) {
    sql <- paste0("SELECT * FROM read_parquet(", sql_quote_path(path), ")",
                  if (!is.null(where)) paste0(" WHERE ", where) else "")
    tibble::as_tibble(DBI::dbGetQuery(con, sql))
  })
}
