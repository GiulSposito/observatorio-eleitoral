# Web bundle — escrita de Parquet. write_mart() é o ponto único por onde todo mart passa:
# colunas e tipos de contract/marts.yml, ordenação física `sort`, ZSTD e row groups pequenos para que o
# DuckDB-Wasm leia só o trecho do município via HTTP Range (ADR-04).

MART_ROW_GROUP_SIZE <- 2048L

# `from_sql` é uma relação SQL já disponível na conexão `con` (tabela, view ou subconsulta).
write_mart <- function(con, name, from_sql, path, contract = read_marts_contract()) {
  spec <- mart_spec(name, contract)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  DBI::dbExecute(con, sprintf(
    "COPY (%s) TO %s (FORMAT parquet, COMPRESSION zstd, ROW_GROUP_SIZE %d)",
    mart_select_sql(spec, from_sql), sql_quote_path(path), MART_ROW_GROUP_SIZE))
  path
}

# Variante para data frames em memória.
write_mart_df <- function(con, name, df, path, contract = read_marts_contract()) {
  assert_no_list_cols(df, name)
  view <- paste0("mart_df_", name)
  duckdb::duckdb_register(con, view, df, overwrite = TRUE)
  on.exit(duckdb::duckdb_unregister(con, view), add = TRUE)
  write_mart(con, name, view, path, contract)
}
