# Carrega o código do projeto para os testes (rodar a partir da raiz:
# Rscript -e 'testthat::test_dir("tests/testthat")').

local({
  root <- normalizePath(file.path(getwd(), "..", ".."), mustWork = FALSE)
  if (!file.exists(file.path(root, "DESCRIPTION"))) root <- normalizePath(getwd())
  options(caderno.repo_root = root)
  for (f in sort(list.files(file.path(root, "R"), pattern = "[.]R$", recursive = TRUE, full.names = TRUE))) {
    source(f, local = globalenv())
  }
  # Sem R/ecological/ (desenvolvimento da camada de dados), o stub entra no ambiente global, onde o
  # código do pipeline procura ec_bounds/ec_estimate/ec_calibrate.
  if (!exists("ec_bounds", envir = globalenv(), mode = "function")) {
    source(file.path(root, "tests", "testthat", "helper-ecological-stub.R"), local = globalenv())
  }
})

# Executa `code` com a raiz de dados num diretório temporário.
with_temp_data_root <- function(code) {
  old <- Sys.getenv("CADERNO_DATA_DIR", unset = NA)
  tmp <- tempfile("caderno_data_")
  dir.create(tmp)
  Sys.setenv(CADERNO_DATA_DIR = tmp)
  on.exit({
    if (is.na(old)) Sys.unsetenv("CADERNO_DATA_DIR") else Sys.setenv(CADERNO_DATA_DIR = old)
    unlink(tmp, recursive = TRUE)
  }, add = TRUE)
  force(code)
}
