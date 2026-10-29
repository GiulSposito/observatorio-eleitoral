# Web bundle — contrato executável (contract/marts.yml e JSON Schemas), contrato 1.3.0.
#
# Todo mart passa por um único ponto de escrita (write_mart, em parquet.R), que seleciona as colunas na
# ordem do contrato, converte para o tipo declarado e grava na ordenação física exigida.

CONTRACT_SCHEMA_VERSION <- "1.3.0"

# YAML 1.1 lê `N`, `Y`, `no`, `yes` sem aspas como booleanos; no contrato só `true`/`false` são
# booleanos (a categoria `N` de origem, por exemplo, é texto).
yaml_bool_strict <- function(x) {
  if (tolower(x) %in% c("true", "false")) as.logical(tolower(x)) else x
}

read_marts_contract <- function() {
  yaml::read_yaml(file.path(repo_root(), "contract", "marts.yml"),
                  handlers = list("bool#yes" = yaml_bool_strict, "bool#no" = yaml_bool_strict))
}

mart_spec <- function(name, contract = read_marts_contract()) {
  spec <- contract$marts[[name]]
  if (is.null(spec)) stop("mart desconhecido no contrato: ", name, call. = FALSE)
  spec
}

assert_no_list_cols <- function(df, name = "<mart>") {
  bad <- names(df)[vapply(df, is.list, logical(1))]
  if (length(bad) > 0L) {
    stop(sprintf("%s tem list-column(s): %s", name, paste(bad, collapse = ", ")), call. = FALSE)
  }
  invisible(df)
}

# SELECT com casts para os tipos do contrato, a partir de uma relação SQL.
mart_select_sql <- function(spec, from_sql) {
  cols <- names(spec$columns)
  exprs <- vapply(cols, function(col) {
    sprintf("CAST(%s AS %s) AS %s", col, spec$columns[[col]]$type, col)
  }, character(1))
  sprintf("SELECT %s FROM (%s) src ORDER BY %s",
          paste(exprs, collapse = ", "), from_sql, paste(spec$sort, collapse = ", "))
}

json_validators <- function() {
  dir <- file.path(repo_root(), "contract")
  kinds <- c("latest", "catalogo", "manifest", "resumo", "qualidade", "metodo")
  stats::setNames(lapply(kinds, function(k) {
    jsonvalidate::json_validator(file.path(dir, paste0(k, ".schema.json")), engine = "ajv")
  }), kinds)
}
